<#
    .SYNOPSIS
    Lab: lists the sites of a tenant with the listing that the Scan uses, changes nothing, and reports what it found.

    .DESCRIPTION
    This script only reads. It signs in (interactive: a window opens), lists the sites with Get-SPSLifecycleTenantSite, which
    is the call that the Scan makes, and prints and saves a report: the pages and the time they took, the counts of the sites
    by lock state, template and so on, and checks on the records. The report never holds the name of the tenant, an address,
    or a title, so that it can be pasted into an issue. Read the checks like this: PASS is what is expected, FAIL is a defect
    or a difference to look at, INFO is worth knowing.

    The script exists to check on a real tenant what the tests cannot: the paged call of the SharePoint admin API, the way
    its records are read, and the resume of a listing. Use a lab or demonstration tenant of a few thousand sites, with a
    SharePoint administrator account. Three runs answer the questions of the listing:

    1. A run with no switch lists the whole tenant. Compare the number of sites with the one that you know (ExpectedSites),
       and the time of a page with the 2.3 to 2.8 s of D7.
    2. A run with StopAfterPages 2 stops after two pages and leaves the checkpoint. The same command without it takes the
       checkpoint up: the report says that it resumed, and its SiteIdDigest is the one of a run with Restart.
    3. A run with CompareWithCmdlet lists the sites a second time with Get-PnPTenantSite (the sign-in is asked again) and
       compares every field of the sites of both calls. A few differences are sites that changed between the two readings
       (the tolerance is 3 sites or 0.1 %); more than that is a field that is not read the same way.

    The report is also saved as listing-lab-report.json in OutputFolder, which holds the checkpoint too.

    What the script prints and writes names nothing of the tenant: not its name, an address, an account or a title. Nothing
    that the module or a library says as text is passed on, cleaned or not, because no cleaning finds a name that it does not
    know. What is shown comes from lists that are written in the script: the reason why a checkpoint was not taken up is told
    in one of a few fixed sentences (its code is StartCode in the report); the reason why the paged call cannot be used is shown
    when it is one of the sentences that the tool writes, and as a reason that the script does not know otherwise; the warnings
    of the listing are counted and not shown, and so is anything else that the listing and the libraries write through the
    streams of PowerShell (information, host, debug, verbose and error lines), which is counted too, and no progress is
    written. The versions are shown by their numbers, and the system by its name.
    The values of a site are shown only when they are words of a list: the words that SharePoint writes for a lock state and an
    archive status, the web templates that it has (in its spelling, with the number), an ID only when it is one. The text of an
    error is never shown: the lab says the sentence of this repository that the error is, if it is one of a few, the type of
    each exception when it is on a list of the types of the framework and of the libraries that the tool uses (any other type is
    not named), the codes that its text holds (an HTTP status, an AADSTS code) and the properties of a site that it names when
    they are ones that the tool reads, and keeps the text in listing-lab-error.txt in OutputFolder. The checkpoint and that
    file, however, name the tenant and the sites: share the report, not that folder. PowerShell also keeps the original errors
    in $Error: do not paste them either.

    What you type is checked by the script, and when a value is not right the lab says which parameter and what it takes, without
    the value. PowerShell does not do that when it refuses a name of parameter that does not exist, a value that goes with no
    parameter, or the value of a common parameter (-ErrorAction and the like): it gives back what was typed, so do not paste
    that line. A library that writes straight to the console, outside the streams of PowerShell, is not held back either: if a
    line shows that the lab did not write, do not paste it.

    .PARAMETER TenantName
    The name of the tenant, in lowercase, as in <name>.onmicrosoft.com. The Microsoft corporate tenants are refused.

    .PARAMETER ClientId
    The application (client) ID of the Entra ID app registration for the interactive sign-in: a GUID.

    .PARAMETER LockState
    The lock states that the Scan lists: ReadOnly, Unlock, or both. With ReadOnly alone, the server filters the listing; with
    both, it gives the whole tenant. Default: both.

    .PARAMETER Source
    Auto (the paged call, and the cmdlet when the paged call is not there), Csom (the paged call only) or Cmdlet.

    .PARAMETER OutputFolder
    Where the checkpoint and the report go. A relative path is relative to the location of the PowerShell session. Default: a
    folder in the temporary folder. The checkpoint holds the addresses and the titles of the sites, and the file of an error
    holds its text: share the report, never this folder.

    .PARAMETER StopAfterPages
    Stops after that many pages read from the tenant in this run, and leaves the checkpoint. A whole number from 0 to 100000;
    0 (the default) does not stop.

    .PARAMETER Restart
    Ignores the checkpoint and starts again.

    .PARAMETER CompareWithCmdlet
    Lists the sites a second time with Get-PnPTenantSite, and compares them with the first listing. It keeps the sites of the
    first listing in memory: use it on a tenant of some thousand sites.

    .PARAMETER ExpectedSites
    The number of sites that the tenant has, if you know it: a whole number from 0 to 100000000. 0 (the default) means that
    it is not given.

    .PARAMETER PassThru
    Gives the report as an object.

    .EXAMPLE
    ./tools/lab/Test-TenantListing.ps1 -TenantName mytenant -ClientId 00000000-0000-0000-0000-000000000000

    .EXAMPLE
    ./tools/lab/Test-TenantListing.ps1 -TenantName mytenant -ClientId 00000000-0000-0000-0000-000000000000 -StopAfterPages 2
    ./tools/lab/Test-TenantListing.ps1 -TenantName mytenant -ClientId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_ -cmatch '^[a-z0-9][a-z0-9-]{0,62}$' }, ErrorMessage = 'The tenant name is the name of the tenant in lowercase, as in <name>.onmicrosoft.com: the letters a to z, digits and hyphens, and not an address.')]
    [System.String]
    $TenantName,

    [Parameter(Mandatory = $true)]
    [System.String]
    $ClientId,

    [Parameter()]
    [System.String[]]
    $LockState = @('ReadOnly', 'Unlock'),

    [Parameter()]
    [System.String]
    $Source = 'Auto',

    [Parameter()]
    [System.String]
    $OutputFolder = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'SPSSiteLifecycle-lab'),

    [Parameter()]
    [System.String]
    $StopAfterPages = '0',

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $Restart,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $CompareWithCmdlet,

    [Parameter()]
    [System.String]
    $ExpectedSites = '0',

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
if (-not $PSBoundParameters.ContainsKey('InformationAction')) {
    $InformationPreference = 'Continue'
}

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$script:Checks = [System.Collections.Generic.List[System.Object]]::new()

# The output folder, once it is known: the text of an error is kept there.
$folder = $null

# What stops the lab is told by what cannot name anything (see ConvertTo-LabErrorSummary), and the exception that is thrown holds
# no inner exception that would say the rest.
trap {
    $summary = ConvertTo-LabErrorSummary -ErrorRecord $_
    $message = "The lab stopped: $($summary.Text)"
    if ($summary.Detail -and (Save-LabErrorDetail -ErrorRecord $_)) {
        $message += ' The text of the error, which can name the tenant, a site or an account, is saved in listing-lab-error.txt in the output folder: do not share that folder.'
    }

    throw [System.InvalidOperationException]::new($message)
}

function Write-LabLine {
    param([System.String]$Text = '')
    Write-Information -MessageData $Text
}

function Format-LabNumber {
    param($Value, [System.Int32]$Decimals = 0)
    ([System.Double]$Value).ToString("N$Decimals", $invariant)
}

function Format-LabDate {
    param($Value)
    if ($null -eq $Value) {
        return ''
    }

    $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant)
}

function Format-LabCount {
    param([System.Collections.IDictionary]$Count)
    (@($Count.GetEnumerator() | ForEach-Object { '{0} {1}' -f $_.Key, (Format-LabNumber $_.Value) }) -join ', ')
}

function Add-LabCheck {
    param
    (
        [System.String]$Name,

        [ValidateSet('PASS', 'FAIL', 'INFO')]
        [System.String]$Status,

        [System.String]$Detail
    )

    $script:Checks.Add([PSCustomObject][ordered]@{ Name = $Name; Status = $Status; Detail = $Detail })
}

# What the module says about a checkpoint that it did not take up is a sentence that can name the tenant it was made for. The
# lab tells it with its own words, by the code of the reason, and a code that it does not know is not passed on.
$script:StartWords = @{
    'restart'       = 'a new listing was asked for (Restart)'
    'damaged'       = 'the checkpoint was damaged'
    'other-version' = 'the checkpoint was written by another version of the tool'
    'finished'      = 'the checkpoint was of a listing that had ended'
    'other-tenant'  = 'the checkpoint was made for another tenant'
    'other-filter'  = 'the checkpoint was made with another filter'
    'other-options' = 'the checkpoint was made with other options'
    'clock'         = 'the dates of the checkpoint cannot be true (was the clock of this machine changed?)'
    'too-old'       = 'the checkpoint is too old'
}

# The code, in the spelling of the list: a hash table finds a key whatever the case, and the lab shows what the list says.
function ConvertTo-LabCode {
    param($Code)

    $text = "$Code"
    if ($text.Length -eq 0) {
        return ''
    }

    foreach ($known in $script:StartWords.Keys) {
        if ([System.String]::Equals($text, $known, [System.StringComparison]::Ordinal)) {
            return $known
        }
    }

    'unknown'
}

function Get-LabStartSentence {
    param([System.String]$Code)

    if ($script:StartWords.ContainsKey($Code)) {
        return $script:StartWords[$Code]
    }

    'the checkpoint was not taken up for a reason that this script does not know'
}

# The text that the module gives is passed on only when it is one of the sentences that the tool writes, which are fixed (the
# reasons why the paged call cannot be used, of which only the name of a property of the filter and of a type change, from a list),
# and never as a text that was cleaned: no cleaning finds a name that it does not know. Any other text is not shown at all.
$script:KnownApiReasons = @(
    '\AThe types of the SharePoint admin API \(Tenant, SPOSitePropertiesEnumerableFilter, PersonalSiteFilter\) are not in this PnP\.PowerShell\.\z'
    "\AThe filter of the admin API has no property '(?:Filter|IncludeDetail|IncludePersonalSite|StartIndex)' in this PnP\.PowerShell\.\z"
    "\AThe property '(?:Filter|IncludeDetail|IncludePersonalSite|StartIndex)' of the filter of the admin API is not a writable (?:String|Boolean|PersonalSiteFilter) in this PnP\.PowerShell\.\z"
    "\AThe enumeration of the OneDrive sites has no value 'Exclude' in this PnP\.PowerShell\.\z"
    '\AThe tenant of the admin API has no method GetSitePropertiesFromSharePointByFilters that takes the filter in this PnP\.PowerShell\.\z'
    "\AThe page that the admin API gives has no text property 'NextStartIndexFromSharePoint' in this PnP\.PowerShell\.\z"
    '\AThe cmdlet was asked for \(Source Cmdlet\)\.\z'
)

function ConvertTo-LabApiReason {
    param($Reason)

    $text = "$Reason"
    if ($text -eq '') {
        return ''
    }

    foreach ($pattern in $script:KnownApiReasons) {
        if ([System.Text.RegularExpressions.Regex]::IsMatch($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            return $text
        }
    }

    'a reason that this script does not know'
}

# The filter that the server applies is empty, or the lock state that the Scan asked for.
function ConvertTo-LabFilter {
    param($Filter)

    $text = "$Filter"
    if ($text -eq '') {
        return ''
    }

    if ([System.Text.RegularExpressions.Regex]::IsMatch($text, "\ALockState -eq '(?:ReadOnly|Unlock|NoAccess)'\z", [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        return $text
    }

    'a filter that this script does not know'
}

# A word of a short list that the module writes, shown as it is, or as unknown.
function ConvertTo-LabWord {
    param($Text, [System.String[]]$Known)

    $value = "$Text"
    if ($value -eq '') {
        return ''
    }

    foreach ($word in $Known) {
        if ([System.String]::Equals($value, $word, [System.StringComparison]::Ordinal)) {
            return $word
        }
    }

    'unknown'
}

# A lock state and an archive status are words that SharePoint writes, and a template is the name of one of its web templates, a
# number sign and a number. They are shown only when they are that, and in the spelling of this list and not as they were read, so
# that nothing that was read is repeated: a text that is not in a list can be anything, a tenant name included (contoso#0 has the
# form of a template). A word that is not in a list (a lock state that is new, a template that is custom) is shown as not being a
# name, and counted: the checkpoint holds what it was.
$script:KnownLockStates = @('Unlock', 'NoAdditions', 'ReadOnly', 'NoAccess')
$script:KnownArchiveStatuses = @('NotArchived', 'RecentlyArchived', 'FullyArchived')
$script:KnownTemplates = @(
    'STS', 'BLOG', 'WIKI', 'ENTERWIKI', 'PROJECTSITE', 'PWA', 'PWS', 'MPS', 'SGS', 'SPS', 'SPSPERS', 'SPSMSITEHOST', 'SPSNEWS', 'SPSNHOME',
    'SPSTOPIC', 'SPSTOC', 'SPSCOMMU', 'SPSREPORTCENTER', 'SPSPORTAL', 'SPSSITES', 'CENTRALADMIN', 'TENANTADMIN', 'APPCATALOG', 'SRCHCEN',
    'SRCHCENTERLITE', 'EHS', 'EDISC', 'BDR', 'OFFILE', 'POLICYCTR', 'REVIEWCTR', 'DEV', 'COMMUNITY', 'COMMUNITYPORTAL', 'SITEPAGEPUBLISHING',
    'GROUP', 'TEAMCHANNEL', 'RedirectSite', 'POINTPUBLISHINGHUB', 'POINTPUBLISHINGPERSONAL', 'POINTPUBLISHINGTOPIC', 'BICENTERSITE',
    'PRODUCTCATALOG', 'VISPRUS', 'CSPCONTAINER'
)

function ConvertTo-LabIdentifier {
    param
    (
        $Text,

        [ValidateSet('LockState', 'ArchiveStatus', 'Template')]
        [System.String]$Kind
    )

    $value = "$Text"
    if ($value -eq '') {
        return '(none)'
    }

    if ($Kind -ne 'Template') {
        $known = if ($Kind -eq 'LockState') { $script:KnownLockStates } else { $script:KnownArchiveStatuses }
        foreach ($word in $known) {
            if ([System.String]::Equals($value, $word, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $word
            }
        }

        return '(not a name)'
    }

    $match = [System.Text.RegularExpressions.Regex]::Match($value, '\A(?<base>[A-Za-z]{2,30})#(?<number>-?[0-9]{1,4})\z')
    if ($match.Success) {
        foreach ($word in $script:KnownTemplates) {
            if ([System.String]::Equals($match.Groups['base'].Value, $word, [System.StringComparison]::OrdinalIgnoreCase)) {
                return "$word#$($match.Groups['number'].Value)"
            }
        }
    }

    '(not a name)'
}

# The ID of a site is shown only when it is an ID: any other text can be anything.
function ConvertTo-LabSiteId {
    param($Value)

    $guid = [System.Guid]::Empty
    if ([System.Guid]::TryParse("$Value", [ref]$guid) -and $guid -ne [System.Guid]::Empty) {
        return $guid.ToString()
    }

    '(not an ID)'
}

# No group is an empty text or the empty GUID: the paged call and the cmdlet do not say it the same way. Gives null for no
# group, the ID of the group, or (not an ID) for a text that is not one.
function ConvertTo-LabGroup {
    param($Value)

    $text = "$Value"
    if ($text -eq '') {
        return $null
    }

    $guid = [System.Guid]::Empty
    if (-not [System.Guid]::TryParse($text, [ref]$guid)) {
        return '(not an ID)'
    }

    if ($guid -eq [System.Guid]::Empty) {
        return $null
    }

    $guid.ToString()
}

# A value of a site, in a shape that cannot hold a name: by its type, never as the text that it holds.
function Format-LabValue {
    param([System.String]$Name, $Value)

    switch ($Name) {
        { $_ -in 'Template', 'LockState', 'ArchiveStatus' } {
            return ConvertTo-LabIdentifier -Text $Value -Kind $Name
        }

        'GroupId' {
            $group = ConvertTo-LabGroup -Value $Value
            if ($null -eq $group) {
                return '(none)'
            }

            return $group
        }

        { $_ -in 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected' } {
            if ($Value -is [System.Boolean]) {
                return "$Value"
            }

            return '(not a boolean)'
        }

        'StorageUsedMB' {
            if ($null -eq $Value) {
                return '(none)'
            }

            return ([System.Int64]$Value).ToString($invariant)
        }

        'LastContentModified' {
            if ($null -eq $Value) {
                return '(none)'
            }

            if ($Value -is [System.DateTime]) {
                return Format-LabDate -Value $Value
            }

            return '(not a date)'
        }

        default {
            return '(not shown)'
        }
    }
}

# What can be said of an error without its text. The text of an error, whoever wrote it, can name the tenant, a site, an account or
# another tenant (the message of a sign-in carries the one of the library), and no cleaning can find what it does not know. So the
# lab says only: the sentences of this repository that are made of fixed words and numbers (the table below, each by the form that
# it has from its first letter), the type of each exception when it is on a list, the codes that the text holds (an HTTP status, an
# AADSTS code: letters and digits of a code, never a name), and the names of the properties of a site that it is about when they
# are ones that the tool reads. The text itself is kept in a file of the output folder, which holds the checkpoint and is not to be
# shared either.
$script:KnownProperties = @(
    'Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus',
    'StorageUsage', 'StorageUsageCurrent', 'LastContentModifiedDate', 'Filter', 'IncludeDetail', 'IncludePersonalSite', 'StartIndex', 'NextStartIndexFromSharePoint'
)
# What is said of a value that is not right for a parameter: the name of the parameter and what it takes, never the value.
$script:ParameterRules = @{
    ClientId       = 'ClientId must be the application (client) ID of the app registration: a GUID'
    Source         = 'Source must be Auto, Csom or Cmdlet'
    LockState      = 'LockState must be ReadOnly, Unlock, or both'
    StopAfterPages = 'StopAfterPages must be a whole number from 0 to 100000'
    ExpectedSites  = 'ExpectedSites must be a whole number from 0 to 100000000'
}
$script:KnownErrors = @(
    @{ Pattern = '\ALabParameter: (?<name>ClientId|Source|LockState|StopAfterPages|ExpectedSites)\z'; Detail = $false; Say = { param($match) $script:ParameterRules[$match.Groups['name'].Value] } }
    @{ Pattern = "\ATenantName: the tenant '[^']*' is refused\."; Detail = $false; Say = { 'The tenant is refused: the tool never runs on the Microsoft corporate tenants or on a tenant that RefusedTenants lists' } }
    @{ Pattern = '\APnP\.PowerShell is not installed\.'; Detail = $false; Say = { 'PnP.PowerShell is not installed (version 3 or later is needed)' } }
    @{ Pattern = '\APnP\.PowerShell (?<version>[0-9][0-9.]*) is too old'; Detail = $false; Say = { param($match) "PnP.PowerShell $($match.Groups['version'].Value) is too old (version 3 or later is needed)" } }
    @{ Pattern = '\APnP\.PowerShell (?<version>[0-9][0-9.]*) is loaded'; Detail = $false; Say = { param($match) "PnP.PowerShell $($match.Groups['version'].Value) is loaded and is too old: start a new session after updating it" } }
    @{ Pattern = '\AThe sign-in to the admin site of the tenant failed'; Detail = $true; Say = { 'The sign-in to the admin site of the tenant failed' } }
    @{ Pattern = '\AThe sign-in to the admin site of the tenant gave no connection'; Detail = $false; Say = { 'The sign-in to the admin site of the tenant gave no connection' } }
    @{ Pattern = '\APage (?<page>[0-9]+) of the listing could not be read after (?<times>[0-9]+) attempts'; Detail = $true; Say = { param($match) "Page $($match.Groups['page'].Value) of the listing could not be read after $($match.Groups['times'].Value) attempts" } }
    @{ Pattern = '\AThe paged listing was asked for and cannot be used: (?<reason>[\s\S]+)\z'; Detail = $false; Say = { param($match) "The paged call was asked for and cannot be used: $(ConvertTo-LabApiReason -Reason $match.Groups['reason'].Value)" } }
    @{ Pattern = "\AThe site '(?<id>[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})' came twice in the listing with another value for a field that guards it"; Detail = $false; Say = { param($match) "The site '$($match.Groups['id'].Value)' came twice in the listing with another value for a field that guards it, so the tenant changed while it was read: start the listing again from the first page (Restart)" } }
    @{ Pattern = '\AThe listing did not end after (?<pages>[0-9]+) pages'; Detail = $false; Say = { param($match) "The listing did not end after $($match.Groups['pages'].Value) pages" } }
)

# The exceptions of an error, from the outside in, as far as a person can read: a chain that goes on for ever, or comes back on
# itself (an exception that gives itself as its inner exception), is cut, and says so.
function Get-LabExceptionChain {
    param($Exception, [System.Int32]$MaxDepth = 10)

    $items = [System.Collections.Generic.List[System.Object]]::new()
    $seen = [System.Collections.Generic.HashSet[System.Object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    $truncated = $false
    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($items.Count -ge $MaxDepth -or -not $seen.Add($current)) {
            $truncated = $true
            break
        }

        $items.Add($current)
    }

    [PSCustomObject]@{ Items = $items.ToArray(); Truncated = $truncated }
}

# The types of exception that the lab names, each by its full name: the ones of the framework, of PowerShell and of the libraries that
# the tool uses. A type that is not on the list is not named, whatever its namespace: a library, or a module that is loaded, can
# have a type that is named like a site or a person, in a namespace that begins like one of the framework.
$script:KnownExceptionTypes = @(
    'System.Exception', 'System.AggregateException', 'System.ArgumentException', 'System.ArgumentNullException', 'System.ArgumentOutOfRangeException',
    'System.BadImageFormatException', 'System.FormatException', 'System.InvalidCastException', 'System.InvalidOperationException',
    'System.NotImplementedException', 'System.NotSupportedException', 'System.NullReferenceException', 'System.ObjectDisposedException',
    'System.OperationCanceledException', 'System.OutOfMemoryException', 'System.TimeoutException', 'System.TypeLoadException',
    'System.UnauthorizedAccessException', 'System.Collections.Generic.KeyNotFoundException', 'System.IO.DirectoryNotFoundException',
    'System.IO.FileLoadException', 'System.IO.FileNotFoundException', 'System.IO.IOException', 'System.Net.WebException',
    'System.Net.Http.HttpRequestException', 'System.Net.Sockets.SocketException', 'System.Reflection.TargetInvocationException',
    'System.Security.SecurityException', 'System.Security.Authentication.AuthenticationException', 'System.Text.Json.JsonException',
    'System.Threading.Tasks.TaskCanceledException',
    'System.Management.Automation.ActionPreferenceStopException', 'System.Management.Automation.CommandNotFoundException',
    'System.Management.Automation.ItemNotFoundException', 'System.Management.Automation.MethodException',
    'System.Management.Automation.MethodInvocationException', 'System.Management.Automation.ParameterBindingException',
    'System.Management.Automation.ParameterBindingValidationException', 'System.Management.Automation.ParentContainsErrorRecordException',
    'System.Management.Automation.PSArgumentException', 'System.Management.Automation.PSInvalidOperationException',
    'System.Management.Automation.PSNotSupportedException', 'System.Management.Automation.RuntimeException',
    'System.Management.Automation.ValidationMetadataException',
    'Microsoft.Identity.Client.MsalClientException', 'Microsoft.Identity.Client.MsalException', 'Microsoft.Identity.Client.MsalServiceException',
    'Microsoft.Identity.Client.MsalUiRequiredException',
    'Microsoft.SharePoint.Client.ClientRequestException', 'Microsoft.SharePoint.Client.CollectionNotInitializedException',
    'Microsoft.SharePoint.Client.PropertyOrFieldNotInitializedException', 'Microsoft.SharePoint.Client.ServerException',
    'Microsoft.SharePoint.Client.ServerUnauthorizedAccessException',
    'Newtonsoft.Json.JsonReaderException', 'Newtonsoft.Json.JsonSerializationException'
)

# The name of the type of an exception when the type is on the list, taken from the list, and (another type) otherwise.
function Get-LabTypeName {
    param($Exception)

    $fullName = $Exception.GetType().FullName
    foreach ($known in $script:KnownExceptionTypes) {
        if ([System.String]::Equals($fullName, $known, [System.StringComparison]::Ordinal)) {
            return $known.Substring($known.LastIndexOf('.') + 1)
        }
    }

    '(another type)'
}

function ConvertTo-LabErrorSummary {
    param($ErrorRecord)

    # Nothing in here may throw: this runs in the handler of the error that stops the lab.
    try {
        $chain = Get-LabExceptionChain -Exception $ErrorRecord.Exception
        $names = @($chain.Items | ForEach-Object { Get-LabTypeName -Exception $_ })
        $texts = @($chain.Items | ForEach-Object { "$($_.Message)" })
        $first = if ($texts.Count -gt 0) { $texts[0] } else { '' }

        $sentence = 'an error whose text is not shown'
        $detail = $true
        foreach ($known in $script:KnownErrors) {
            $match = [System.Text.RegularExpressions.Regex]::Match($first, $known.Pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            if ($match.Success) {
                $sentence = & $known.Say $match
                $detail = $known.Detail
                break
            }
        }

        $all = $texts -join "`n"
        $codes = [System.Collections.Generic.List[System.String]]::new()
        foreach ($found in [System.Text.RegularExpressions.Regex]::Matches($all, '\(([1-5][0-9]{2})\)')) {
            $code = "HTTP $($found.Groups[1].Value)"
            if (-not $codes.Contains($code)) { $codes.Add($code) }
        }

        foreach ($found in [System.Text.RegularExpressions.Regex]::Matches($all, 'AADSTS[0-9]{4,7}')) {
            if (-not $codes.Contains($found.Value)) { $codes.Add($found.Value) }
        }

        $properties = [System.Collections.Generic.List[System.String]]::new()
        foreach ($found in [System.Text.RegularExpressions.Regex]::Matches($all, "[Pp]roperty '([A-Za-z][A-Za-z0-9]{0,39})'")) {
            foreach ($known in $script:KnownProperties) {
                if ([System.String]::Equals($found.Groups[1].Value, $known, [System.StringComparison]::OrdinalIgnoreCase) -and -not $properties.Contains($known)) {
                    $properties.Add($known)
                }
            }
        }

        $types = if ($names.Count -gt 0) { $names -join ', caused by ' } else { '(none)' }
        if ($chain.Truncated) { $types += ', caused by more (the chain is cut)' }
        $line = "$($sentence.TrimEnd('.')). Error types: $types."
        if ($codes.Count -gt 0) { $line += " Codes in its text: $($codes -join ', ')." }
        if ($properties.Count -gt 0) { $line += " Properties named: $($properties -join ', ')." }
        [PSCustomObject]@{ Text = $line; Detail = $detail }
    }
    catch {
        [PSCustomObject]@{ Text = 'an error whose text is not shown.'; Detail = $true }
    }
}

# The error as it was written, in the output folder: for the person who runs the lab, and for no one else. Nothing stops for a file that
# cannot be written.
function Save-LabErrorDetail {
    param($ErrorRecord)

    if ($null -eq $folder) {
        return $false
    }

    try {
        $chain = Get-LabExceptionChain -Exception $ErrorRecord.Exception -MaxDepth 20
        $lines = [System.Collections.Generic.List[System.String]]::new()
        $lines.Add('SPSSiteLifecycle listing lab: the error that stopped it, as it was written.')
        $lines.Add('It can name the tenant, a site, an account or another tenant. Do not share this file, or the folder that holds it.')
        $lines.Add('')
        $lines.Add((Format-LabDate -Value ([System.DateTime]::UtcNow)))
        $level = 0
        foreach ($exception in $chain.Items) {
            $level++
            $lines.Add(('{0}[{1}] {2}: {3}' -f $(if ($level -gt 1) { 'caused by ' } else { '' }), $level, $exception.GetType().FullName, $exception.Message))
        }

        if ($chain.Truncated) {
            $lines.Add("(the chain goes on or comes back on itself: only the first $level exceptions are written)")
        }

        $lines.Add('')
        $lines.Add('Script stack trace:')
        $lines.Add("$($ErrorRecord.ScriptStackTrace)")
        $null = New-Item -ItemType Directory -Path $folder -Force
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'listing-lab-error.txt'), ($lines -join [System.Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
        return $true
    }
    catch {
        return $false
    }
}

# The summary of the listing as the report holds it: the fields that are counts and times, and the ones that are text, each a word or a
# sentence of a list. The reason why a checkpoint was not taken up is its code, and the text of the module is left out.
function ConvertTo-LabSummary {
    param($Summary, [System.Int32]$Warning, [System.Int32]$Output)

    [PSCustomObject][ordered]@{
        Source              = ConvertTo-LabWord -Text $Summary.Source -Known 'Csom', 'Cmdlet'
        FallbackReason      = ConvertTo-LabApiReason -Reason $Summary.FallbackReason
        Filter              = ConvertTo-LabFilter -Filter $Summary.Filter
        PersonalSites       = ConvertTo-LabWord -Text $Summary.PersonalSites -Known 'Excluded'
        StartedOn           = $Summary.StartedOn
        FinishedOn          = $Summary.FinishedOn
        ElapsedSeconds      = $Summary.ElapsedSeconds
        Resumed             = $Summary.Resumed
        StartCode           = ConvertTo-LabCode -Code $Summary.StartCode
        PagesFromCheckpoint = $Summary.PagesFromCheckpoint
        SitesFromCheckpoint = $Summary.SitesFromCheckpoint
        PagesRead           = $Summary.PagesRead
        SitesRead           = $Summary.SitesRead
        OneDriveDropped     = $Summary.OneDriveDropped
        DuplicatesDropped   = $Summary.DuplicatesDropped
        SitesReturned       = $Summary.SitesReturned
        Retries             = $Summary.Retries
        PageSecondsTotal    = $Summary.PageSecondsTotal
        PageSecondsMax      = $Summary.PageSecondsMax
        WarningCount        = $Warning
        OutputCount         = $Output
    }
}

function Initialize-LabStatistic {
    [PSCustomObject]@{
        Sites                  = 0
        LockStates             = @{}
        Templates              = @{}
        Archive                = @{}
        TeamsConnected         = 0
        TeamsChannelConnected  = 0
        HubSites               = 0
        WithoutGroup           = 0
        GroupSitesWithoutGroup = 0
        TotalSizeMB            = [System.Int64]0
        NegativeSizes          = 0
        WithoutSize            = 0
        WithoutDate            = 0
        Oldest                 = $null
        Newest                 = $null
        NewestSites            = [System.Collections.Generic.List[System.Object]]::new()
        OneDriveSites          = 0
        Malformed              = 0
        MalformedExamples      = [System.Collections.Generic.List[System.String]]::new()
        SiteIds                = [System.Collections.Generic.List[System.String]]::new()
    }
}

function Add-LabRecord {
    param($Statistic, $Record)

    $Statistic.Sites++
    $Statistic.SiteIds.Add("$($Record.SiteId)")
    $lockState = ConvertTo-LabIdentifier -Text $Record.LockState -Kind LockState
    $Statistic.LockStates[$lockState] = 1 + [System.Int32]$Statistic.LockStates[$lockState]
    $template = ConvertTo-LabIdentifier -Text $Record.Template -Kind Template
    $Statistic.Templates[$template] = 1 + [System.Int32]$Statistic.Templates[$template]
    $archive = ConvertTo-LabIdentifier -Text $Record.ArchiveStatus -Kind ArchiveStatus
    $Statistic.Archive[$archive] = 1 + [System.Int32]$Statistic.Archive[$archive]
    if ($Record.IsTeamsConnected) { $Statistic.TeamsConnected++ }
    if ($Record.IsTeamsChannelConnected) { $Statistic.TeamsChannelConnected++ }
    if ($Record.IsHubSite) { $Statistic.HubSites++ }
    $group = ConvertTo-LabGroup -Value $Record.GroupId
    if ($null -eq $group) {
        $Statistic.WithoutGroup++
        if ("$($Record.Template)".StartsWith('GROUP#', [System.StringComparison]::OrdinalIgnoreCase)) { $Statistic.GroupSitesWithoutGroup++ }
    }

    # A size that is not known is not a size of zero.
    $storage = $Record.StorageUsedMB
    if ($null -eq $storage -or "$storage" -eq '') {
        $Statistic.WithoutSize++
    }
    else {
        $Statistic.TotalSizeMB += [System.Int64]$storage
        if ([System.Int64]$storage -lt 0) { $Statistic.NegativeSizes++ }
    }

    if ("$($Record.Url)".IndexOf('-my.sharepoint.com', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $Statistic.OneDriveSites++ }

    $complete = (ConvertTo-LabSiteId -Value $Record.SiteId) -ne '(not an ID)' -and
        "$($Record.Url)".StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase) -and
        [bool]$Record.Template -and
        [bool]$Record.LockState -and
        $group -ne '(not an ID)'
    if (-not $complete) {
        $Statistic.Malformed++
        if ($Statistic.MalformedExamples.Count -lt 3) { $Statistic.MalformedExamples.Add((ConvertTo-LabSiteId -Value $Record.SiteId)) }
    }

    $date = $Record.LastContentModified
    if ($null -eq $date) {
        $Statistic.WithoutDate++
        return
    }

    if ($null -eq $Statistic.Oldest -or $date -lt $Statistic.Oldest) { $Statistic.Oldest = $date }
    if ($null -eq $Statistic.Newest -or $date -gt $Statistic.Newest) { $Statistic.Newest = $date }
    $list = $Statistic.NewestSites
    if ($list.Count -lt 3 -or $date -gt $list[$list.Count - 1].Date) {
        $list.Add([PSCustomObject]@{ SiteId = "$($Record.SiteId)"; Date = $date })
        $sorted = @($list | Sort-Object -Property Date -Descending | Select-Object -First 3)
        $list.Clear()
        $list.AddRange($sorted)
    }
}

function Get-LabDigest {
    param([System.Collections.Generic.List[System.String]]$SiteId)

    $sorted = $SiteId.ToArray()
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes(($sorted -join "`n")))
    [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant().Substring(0, 16)
}

function ConvertTo-LabCount {
    param([System.Collections.IDictionary]$Count, [System.Int32]$Top = 0)

    $result = [ordered]@{}
    $entries = @($Count.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } })
    if ($Top -gt 0) {
        $entries = @($entries | Select-Object -First $Top)
    }

    foreach ($entry in $entries) {
        $result[$entry.Key] = $entry.Value
    }

    $result
}

function Test-LabStop {
    param($ErrorRecord)

    foreach ($exception in (Get-LabExceptionChain -Exception $ErrorRecord.Exception -MaxDepth 20).Items) {
        if ($exception -is [System.OperationCanceledException]) {
            return $true
        }
    }

    $false
}

function Invoke-LabListing {
    param
    (
        $Module,
        $Setting,
        [System.String]$ListingSource,
        [System.Boolean]$RestartListing,
        [System.Int32]$PagesToRead,
        [System.Management.Automation.ScriptBlock]$OnRecord,
        [System.Boolean]$Print
    )

    $summary = & $Module { Initialize-SPSLifecycleListingSummary }

    # The lines that the lab writes while the listing runs carry a tag that the listing cannot know: any other information record is
    # one of the listing or of a library, and is counted.
    $tag = [System.Guid]::NewGuid().ToString('N')
    $state = [PSCustomObject]@{ Pages = 0; Stop = $PagesToRead; Print = $Print; Warnings = 0; Other = 0; Tag = $tag }

    # A closure is cut off from the functions of this script: it holds only what it is given, and cmdlets.
    $onProgress = {
        param($Progress)
        if (-not $Progress.FromCheckpoint) {
            $state.Pages++
        }

        if ($state.Print -and ($Progress.Pages -le 3 -or ($Progress.Pages % 10) -eq 0)) {
            $how = if ($Progress.FromCheckpoint) { 'from the checkpoint' } else { $Progress.PageSeconds.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + ' s' }
            Write-Information -MessageData ('  page {0}: {1} sites so far ({2})' -f $Progress.Pages, $Progress.SitesReturned.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture), $how) -Tags $state.Tag
        }

        if ($state.Stop -gt 0 -and $state.Pages -ge $state.Stop) {
            throw [System.OperationCanceledException]::new('The listing was stopped on purpose (StopAfterPages).')
        }
    }.GetNewClosure()

    $parameters = @{ Setting = $Setting; Summary = $summary; Source = $ListingSource; OnProgress = $onProgress }
    if ($RestartListing) {
        $parameters.Restart = $true
    }

    $completed = $false
    try {
        # What the listing and the libraries write, other than the sites, can name the tenant, a filter or a site: the warnings, and the
        # information, host, debug, verbose and error lines, are counted and not shown (a library can force the verbose lines with
        # -Verbose, whatever the preference), and no progress is written: the text of a progress bar goes straight to the screen, and
        # the lab prints its own progress lines.
        & $Module {
            param($p)
            $WarningPreference = 'Continue'
            $VerbosePreference = 'SilentlyContinue'
            $ProgressPreference = 'SilentlyContinue'
            Get-SPSLifecycleTenantSite @p
        } $parameters 2>&1 3>&1 4>&1 5>&1 6>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.WarningRecord]) {
                $state.Warnings++
            }
            elseif ($_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains $state.Tag) {
                Write-LabLine -Text "$($_.MessageData)"
            }
            elseif ($_ -is [System.Management.Automation.InformationRecord] -or $_ -is [System.Management.Automation.ErrorRecord] -or $_ -is [System.Management.Automation.DebugRecord] -or $_ -is [System.Management.Automation.VerboseRecord]) {
                $state.Other++
            }
            else {
                & $OnRecord $_
            }
        }

        $completed = $true
    }
    catch {
        if (-not (Test-LabStop -ErrorRecord $_)) {
            throw
        }
    }

    [PSCustomObject]@{ Summary = $summary; Completed = $completed; Pages = $state.Pages; Warnings = $state.Warnings; Output = $state.Other }
}

function Compare-LabListing {
    param([System.Collections.IDictionary]$Paged, [System.Collections.IDictionary]$Cmdlet)

    # The address and the title name the tenant and the site, and Format-LabValue never shows them.
    $fields = [ordered]@{}
    foreach ($name in 'Url', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified') {
        $fields[$name] = [PSCustomObject]@{ Differing = 0; OneSided = 0; MaxDifference = 0; Examples = [System.Collections.Generic.List[System.Object]]::new() }
    }

    $inBoth = 0
    $onlyPaged = 0
    foreach ($id in $Paged.Keys) {
        if (-not $Cmdlet.Contains($id)) {
            $onlyPaged++
            continue
        }

        $inBoth++
        $left = $Paged[$id]
        $right = $Cmdlet[$id]
        foreach ($name in @($fields.Keys)) {
            $a = $left.$name
            $b = $right.$name
            $difference = 0
            $oneSided = $false
            $missingA = $null -eq $a -or "$a" -eq ''
            $missingB = $null -eq $b -or "$b" -eq ''
            if ($name -in 'StorageUsedMB', 'LastContentModified') {
                # A value that is not known is not zero, and is not a date: it differs from every value that is known.
                if ($missingA -or $missingB) {
                    $same = $missingA -and $missingB
                    $oneSided = -not $same
                }
                elseif ($name -eq 'StorageUsedMB') {
                    $difference = [System.Math]::Abs([System.Int64]$a - [System.Int64]$b)
                    $same = $difference -eq 0
                }
                else {
                    $difference = [System.Math]::Abs(([System.DateTime]$a - [System.DateTime]$b).TotalSeconds)
                    $same = $difference -le 1
                }
            }
            elseif ($name -eq 'GroupId') {
                # No group is an empty text for one listing and the empty GUID for the other.
                $same = [System.String]::Equals("$(ConvertTo-LabGroup -Value $a)", "$(ConvertTo-LabGroup -Value $b)", [System.StringComparison]::OrdinalIgnoreCase)
            }
            else {
                $same = [System.String]::Equals("$a", "$b", [System.StringComparison]::OrdinalIgnoreCase)
            }

            if (-not $same) {
                $entry = $fields[$name]
                $entry.Differing++
                if ($oneSided) {
                    $entry.OneSided++
                }

                if ($difference -gt $entry.MaxDifference) {
                    $entry.MaxDifference = $difference
                }

                if ($entry.Examples.Count -lt 3) {
                    $entry.Examples.Add([PSCustomObject]@{ SiteId = ConvertTo-LabSiteId -Value $id; Paged = Format-LabValue -Name $name -Value $a; Cmdlet = Format-LabValue -Name $name -Value $b })
                }
            }
        }
    }

    $onlyCmdlet = 0
    foreach ($id in $Cmdlet.Keys) {
        if (-not $Paged.Contains($id)) {
            $onlyCmdlet++
        }
    }

    [PSCustomObject][ordered]@{
        PagedSites   = $Paged.Count
        CmdletSites  = $Cmdlet.Count
        InBoth       = $inBoth
        OnlyInPaged  = $onlyPaged
        OnlyInCmdlet = $onlyCmdlet
        Fields       = $fields
    }
}

# What was typed for a parameter is checked here, and not by the parameter itself: when its own check fails, PowerShell gives the
# value back as it was typed, in a message that is not the lab's. The error that is thrown here names the parameter and nothing of the
# value (see ParameterRules), and the words that go on in the report are the ones of the lab, not the ones that were typed.
function Get-LabParameterError {
    param([ValidateSet('ClientId', 'Source', 'LockState', 'StopAfterPages', 'ExpectedSites')][System.String]$Name)

    [System.ArgumentException]::new("LabParameter: $Name")
}

# The name of the system, from a list: the description that .NET gives is the text of the kernel.
function Get-LabPlatformName {
    foreach ($candidate in @(
            @{ Name = 'Windows'; Platform = [System.Runtime.InteropServices.OSPlatform]::Windows }
            @{ Name = 'macOS'; Platform = [System.Runtime.InteropServices.OSPlatform]::OSX }
            @{ Name = 'Linux'; Platform = [System.Runtime.InteropServices.OSPlatform]::Linux }
            @{ Name = 'FreeBSD'; Platform = [System.Runtime.InteropServices.OSPlatform]::FreeBSD }
        )) {
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform($candidate.Platform)) {
            return $candidate.Name
        }
    }

    'another system'
}

# The word of a list that was typed, in the spelling of the list, whatever the case that was typed; nothing when it is none of them.
function Get-LabParameterWord {
    param([System.String]$Text, [System.String[]]$Known)

    foreach ($word in $Known) {
        if ([System.String]::Equals($Text, $word, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $word
        }
    }

    $null
}

function ConvertTo-LabWholeNumber {
    param($Text, [System.Int64]$Maximum, [System.String]$Name)

    $number = [System.Int64]0
    if (-not [System.Int64]::TryParse("$Text", [System.Globalization.NumberStyles]::None, $invariant, [ref]$number) -or $number -gt $Maximum) {
        throw (Get-LabParameterError -Name $Name)
    }

    [System.Int32]$number
}

$clientGuid = [System.Guid]::Empty
if (-not [System.Guid]::TryParse($ClientId, [ref]$clientGuid)) {
    throw (Get-LabParameterError -Name ClientId)
}

$sourceName = Get-LabParameterWord -Text $Source -Known 'Auto', 'Csom', 'Cmdlet'
if ($null -eq $sourceName) {
    throw (Get-LabParameterError -Name Source)
}

$lockStates = [System.Collections.Generic.List[System.String]]::new()
foreach ($typed in @($LockState)) {
    $lockStateName = Get-LabParameterWord -Text "$typed" -Known 'ReadOnly', 'Unlock'
    if ($null -eq $lockStateName) {
        throw (Get-LabParameterError -Name LockState)
    }

    if (-not $lockStates.Contains($lockStateName)) {
        $lockStates.Add($lockStateName)
    }
}

if ($lockStates.Count -eq 0) {
    throw (Get-LabParameterError -Name LockState)
}

$pagesLimit = ConvertTo-LabWholeNumber -Text $StopAfterPages -Maximum 100000 -Name StopAfterPages
$sitesExpected = ConvertTo-LabWholeNumber -Text $ExpectedSites -Maximum 100000000 -Name ExpectedSites

# The module of the repository. A copy that is already loaded from this very folder is used as it is.
$manifest = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1')).ProviderPath
$moduleFolder = [System.IO.Path]::GetDirectoryName($manifest)
$module = @(Get-Module -Name 'SPSSiteLifecycle.Common') | Where-Object { [System.String]::Equals($_.ModuleBase, $moduleFolder, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
if ($null -eq $module) {
    $module = Import-Module -Name $manifest -Force -PassThru
}

$folder = & $module { param($path) Resolve-SPSLifecycleFileSystemPath -Path $path } $OutputFolder
$setting = & $module {
    param($tenant, $client, $path, $states)
    [PSCustomObject][ordered]@{
        TenantName     = $tenant
        AdminUrl       = "https://$tenant-admin.sharepoint.com"
        ClientId       = "$client"
        RefusedTenants = @(Get-SPSLifecycleRefusedTenantList)
        OutputFolder   = $path
        Scan           = [PSCustomObject]@{ LockStates = @($states) }
    }
} $TenantName $clientGuid $folder $lockStates.ToArray()
& $module { param($s) Assert-SPSLifecycleTenantAllowed -Setting $s } $setting

$installed = @(Get-Module -Name 'PnP.PowerShell' -ListAvailable | Sort-Object -Property Version -Descending) | Select-Object -First 1

# The versions by their numbers and the system by its name and a number: a version of PowerShell can carry a label of a pre-release,
# and the description of the system that .NET gives is the text of its kernel, and neither is a text that the lab can vouch for.
$psVersion = $PSVersionTable.PSVersion
$powerShellText = '{0}.{1}.{2}' -f $psVersion.Major.ToString($invariant), $psVersion.Minor.ToString($invariant), $psVersion.Patch.ToString($invariant)
if (-not [System.String]::IsNullOrEmpty($psVersion.PreReleaseLabel)) {
    $powerShellText += ' (pre-release)'
}

$environment = [PSCustomObject][ordered]@{
    PowerShell    = $powerShellText
    OS            = "$(Get-LabPlatformName) $([System.Environment]::OSVersion.Version.ToString())"
    Module        = $module.Version.ToString()
    PnPPowerShell = if ($null -ne $installed) { $installed.Version.ToString() } else { 'not found' }
}

$asked = "source $sourceName, lock states $($lockStates -join ', ')"
if ($pagesLimit -gt 0) { $asked += ", stop after $pagesLimit page(s)" }
if ($Restart) { $asked += ', restart' }
if ($CompareWithCmdlet) { $asked += ', compare with the cmdlet' }
Write-LabLine 'SPSSiteLifecycle listing lab: it only reads.'
Write-LabLine "PowerShell $($environment.PowerShell) on $($environment.OS); PnP.PowerShell $($environment.PnPPowerShell); module $($environment.Module)."
Write-LabLine "Asked: $asked."
Write-LabLine 'Signing in (interactive): a window opens.'

# The first listing: the one that is checked.
$statistic = Initialize-LabStatistic
$paged = if ($CompareWithCmdlet) { @{} } else { $null }
$main = Invoke-LabListing -Module $module -Setting $setting -ListingSource $sourceName -RestartListing ([System.Boolean]$Restart) -PagesToRead $pagesLimit -Print $true -OnRecord {
    param($record)
    Add-LabRecord -Statistic $statistic -Record $record
    if ($null -ne $paged) {
        $paged["$($record.SiteId)"] = $record
    }
}
$summary = $main.Summary
$warningCount = $main.Warnings
$outputCount = $main.Output

# The comparison: the same sites with Get-PnPTenantSite.
$compare = $null
$compareNote = ''
if ($CompareWithCmdlet) {
    if (-not $main.Completed) {
        $compareNote = 'Not made: the first listing was stopped before its end.'
    }
    elseif ($summary.Source -eq 'Cmdlet') {
        $compareNote = 'Not made: the first listing used Get-PnPTenantSite already, and would be compared with itself.'
    }
    else {
        Write-LabLine 'Listing the sites a second time with Get-PnPTenantSite (the sign-in is asked again).'
        $cmdletSetting = $setting.PSObject.Copy()
        $cmdletSetting.OutputFolder = Join-Path -Path $folder -ChildPath 'cmdlet'
        $other = @{}
        $second = Invoke-LabListing -Module $module -Setting $cmdletSetting -ListingSource 'Cmdlet' -RestartListing $true -PagesToRead 0 -Print $false -OnRecord {
            param($record)
            $other["$($record.SiteId)"] = $record
        }
        $warningCount += $second.Warnings
        $outputCount += $second.Output
        $compare = Compare-LabListing -Paged $paged -Cmdlet $other
    }
}

# What was read.
$pagesInThisRun = [System.Int32]$summary.PagesRead
$averagePage = if ($pagesInThisRun -gt 0) { $summary.PageSecondsTotal / $pagesInThisRun } else { 0.0 }
$rate = if ($summary.PageSecondsTotal -gt 0) { $summary.SitesRead / $summary.PageSecondsTotal } else { 0.0 }
$digest = Get-LabDigest -SiteId $statistic.SiteIds
$newest = @($statistic.NewestSites | ForEach-Object { [PSCustomObject][ordered]@{ SiteId = ConvertTo-LabSiteId -Value $_.SiteId; LastContentModified = Format-LabDate -Value $_.Date } })
$statistics = [PSCustomObject][ordered]@{
    Sites                  = $statistic.Sites
    LockStates             = ConvertTo-LabCount -Count $statistic.LockStates
    Templates              = ConvertTo-LabCount -Count $statistic.Templates -Top 10
    ArchiveStatus          = ConvertTo-LabCount -Count $statistic.Archive
    TeamsConnected         = $statistic.TeamsConnected
    TeamsChannelConnected  = $statistic.TeamsChannelConnected
    HubSites               = $statistic.HubSites
    WithoutGroup           = $statistic.WithoutGroup
    GroupSitesWithoutGroup = $statistic.GroupSitesWithoutGroup
    TotalSizeMB            = $statistic.TotalSizeMB
    NegativeSizes          = $statistic.NegativeSizes
    WithoutSize            = $statistic.WithoutSize
    WithoutDate            = $statistic.WithoutDate
    OldestChange           = Format-LabDate -Value $statistic.Oldest
    NewestChange           = Format-LabDate -Value $statistic.Newest
    NewestSites            = $newest
    SiteIdDigest           = $digest
}

# The summary that the report holds, and the only one that is printed: its text is from lists, and the reason why a checkpoint was
# not taken up is a code, told with the words of this script.
$safeSummary = ConvertTo-LabSummary -Summary $summary -Warning $warningCount -Output $outputCount
$sourceText = $safeSummary.Source
if ($safeSummary.FallbackReason) { $sourceText += " ($($safeSummary.FallbackReason))" }
$filterText = if ($safeSummary.Filter) { $safeSummary.Filter } else { '(none)' }
$startWords = Get-LabStartSentence -Code $safeSummary.StartCode
if ($summary.Resumed) {
    $checkpointText = "taken up ($($summary.PagesFromCheckpoint) pages, $(Format-LabNumber $summary.SitesFromCheckpoint) sites from it)"
}
elseif ($safeSummary.StartCode) {
    $checkpointText = "not taken up: $startWords"
}
else {
    $checkpointText = 'none to take up'
}

$returned = Format-LabNumber $summary.SitesReturned
if (-not $main.Completed) { $returned += ' (the listing was stopped on purpose)' }
Write-LabLine
Write-LabLine 'The listing'
Write-LabLine "  Source: $sourceText"
Write-LabLine "  Filter of the server: $filterText"
Write-LabLine "  Checkpoint: $checkpointText"
Write-LabLine "  Pages read from the tenant: $(Format-LabNumber $pagesInThisRun), $(Format-LabNumber $summary.SitesRead) sites; retries: $($summary.Retries)"
Write-LabLine "  Time: $(Format-LabNumber $summary.ElapsedSeconds 1) s in all; a page took $(Format-LabNumber $averagePage 2) s on average and $(Format-LabNumber $summary.PageSecondsMax 2) s at most; $(Format-LabNumber $rate) sites/s"
Write-LabLine "  Left out by the listing: $(Format-LabNumber $summary.OneDriveDropped) OneDrive sites, $(Format-LabNumber $summary.DuplicatesDropped) sites that came twice"
if ($warningCount -gt 0 -or $outputCount -gt 0) {
    Write-LabLine "  Warnings of the listing: $(Format-LabNumber $warningCount); other lines of output: $(Format-LabNumber $outputCount) (not shown: their text can name the tenant, a filter or a site)"
}
Write-LabLine "  Sites returned: $returned"
Write-LabLine
Write-LabLine 'The sites'
Write-LabLine "  Lock states: $(Format-LabCount $statistics.LockStates)"
Write-LabLine "  Templates (top 10): $(Format-LabCount $statistics.Templates)"
Write-LabLine "  Archive status: $(Format-LabCount $statistics.ArchiveStatus)"
Write-LabLine "  Connected to Teams: $(Format-LabNumber $statistics.TeamsConnected); channel sites: $(Format-LabNumber $statistics.TeamsChannelConnected); hub sites: $(Format-LabNumber $statistics.HubSites); with no group: $(Format-LabNumber $statistics.WithoutGroup)"
Write-LabLine "  Size: $(Format-LabNumber ($statistics.TotalSizeMB / 1024) 1) GB in all"
Write-LabLine "  Last change (UTC): oldest $($statistics.OldestChange), newest $($statistics.NewestChange); sites with no date: $(Format-LabNumber $statistics.WithoutDate)"
foreach ($site in $newest) {
    Write-LabLine "    $($site.SiteId)  $($site.LastContentModified)"
}

Write-LabLine "  Digest of the site IDs: $digest"

# The checks.
if ($main.Completed) {
    Add-LabCheck -Name 'listing-ended' -Status PASS -Detail "The listing ended: $(Format-LabNumber $summary.SitesReturned) sites."
}
else {
    Add-LabCheck -Name 'listing-ended' -Status INFO -Detail "Stopped on purpose after $($main.Pages) page(s). The checkpoint is kept: run the script again without -StopAfterPages to take it up."
}

if ($summary.Source -eq 'Csom') {
    Add-LabCheck -Name 'source' -Status PASS -Detail 'The paged call of the SharePoint admin API was used.'
}
else {
    $why = if ($safeSummary.FallbackReason) { $safeSummary.FallbackReason } else { 'It was asked for.' }
    Add-LabCheck -Name 'source' -Status INFO -Detail "Get-PnPTenantSite was used. $why"
}

if ($summary.Resumed) {
    Add-LabCheck -Name 'resume' -Status PASS -Detail "The listing took up a checkpoint: $($summary.PagesFromCheckpoint) pages ($(Format-LabNumber $summary.SitesFromCheckpoint) sites) came from it; pages read from the tenant: $pagesInThisRun."
}
else {
    $why = if ($safeSummary.StartCode) { " Why it did not take a checkpoint up: $startWords." } else { '' }
    Add-LabCheck -Name 'resume' -Status INFO -Detail "The listing started from the first page.$why"
}

if ($warningCount -eq 0 -and $outputCount -eq 0) {
    Add-LabCheck -Name 'listing-warnings' -Status PASS -Detail 'The listing gave no warning and wrote nothing but its sites.'
}
else {
    $given = [System.Collections.Generic.List[System.String]]::new()
    if ($warningCount -gt 0) { $given.Add("$(Format-LabNumber $warningCount) warning(s)") }
    if ($outputCount -gt 0) { $given.Add("$(Format-LabNumber $outputCount) other line(s) of output") }
    Add-LabCheck -Name 'listing-warnings' -Status INFO -Detail "The listing gave $($given -join ' and '), not shown: their text can name the tenant, a filter or a site. Run the Scan to read them."
}

if ($main.Completed -and $sitesExpected -gt 0) {
    if ($statistic.Sites -eq $sitesExpected) {
        Add-LabCheck -Name 'expected-sites' -Status PASS -Detail "$(Format-LabNumber $statistic.Sites) sites, as expected."
    }
    else {
        Add-LabCheck -Name 'expected-sites' -Status FAIL -Detail "$(Format-LabNumber $statistic.Sites) sites were listed, and $(Format-LabNumber $sitesExpected) were expected."
    }
}

$distinct = [System.Collections.Generic.HashSet[System.String]]::new($statistic.SiteIds, [System.StringComparer]::Ordinal).Count
Add-LabCheck -Name 'unique-site-ids' -Status $(if ($distinct -eq $statistic.Sites) { 'PASS' } else { 'FAIL' }) -Detail "$(Format-LabNumber $distinct) different site IDs for $(Format-LabNumber $statistic.Sites) sites."
if ($statistic.Malformed -eq 0) {
    Add-LabCheck -Name 'records-are-complete' -Status PASS -Detail 'Every site has a site ID, an https address, a template and a lock state.'
}
else {
    Add-LabCheck -Name 'records-are-complete' -Status FAIL -Detail "$(Format-LabNumber $statistic.Malformed) sites lack one of them, for example $($statistic.MalformedExamples -join ', ')."
}

Add-LabCheck -Name 'no-onedrive-site' -Status $(if ($statistic.OneDriveSites -eq 0) { 'PASS' } else { 'FAIL' }) -Detail "$(Format-LabNumber $statistic.OneDriveSites) OneDrive sites among the sites that the listing gave."
$sizeStatus = if ($statistic.NegativeSizes -gt 0) { 'FAIL' } elseif ($statistic.WithoutSize -gt 0) { 'INFO' } else { 'PASS' }
$sizeDetail = "$(Format-LabNumber $statistic.NegativeSizes) sites with a size below zero, $(Format-LabNumber $statistic.WithoutSize) sites with no size"
if ($statistic.WithoutSize -gt 0) { $sizeDetail += ' (the Scan gives them a review verdict)' }
Add-LabCheck -Name 'sizes' -Status $sizeStatus -Detail "$sizeDetail."
if ($statistic.GroupSitesWithoutGroup -eq 0) {
    Add-LabCheck -Name 'group-sites-have-a-group' -Status PASS -Detail 'Every site with a group template has a group ID.'
}
else {
    Add-LabCheck -Name 'group-sites-have-a-group' -Status INFO -Detail "$(Format-LabNumber $statistic.GroupSitesWithoutGroup) sites with a group template have no group ID (a site whose group was deleted?): the Scan gives them a review verdict."
}

Add-LabCheck -Name 'dates' -Status $(if ($statistic.WithoutDate -eq 0) { 'PASS' } else { 'INFO' }) -Detail "$(Format-LabNumber $statistic.WithoutDate) sites with no date of last change."

if ($compareNote) {
    Add-LabCheck -Name 'compare' -Status INFO -Detail $compareNote
}

if ($null -ne $compare) {
    $tolerance = [System.Math]::Max(3, [System.Math]::Ceiling(0.001 * [System.Math]::Max($compare.PagedSites, $compare.CmdletSites)))
    $missing = $compare.OnlyInPaged + $compare.OnlyInCmdlet
    Add-LabCheck -Name 'compare-sites' -Status $(if ($missing -le $tolerance) { 'PASS' } else { 'FAIL' }) -Detail "$(Format-LabNumber $compare.InBoth) sites in both listings; only in the paged one: $($compare.OnlyInPaged); only in the cmdlet one: $($compare.OnlyInCmdlet) (tolerance $tolerance)."
    foreach ($name in $compare.Fields.Keys) {
        $field = $compare.Fields[$name]
        $largest = ''
        if ($field.MaxDifference -gt 0 -and $name -eq 'StorageUsedMB') { $largest = ", largest difference $(Format-LabNumber $field.MaxDifference) MB" }
        if ($field.MaxDifference -gt 0 -and $name -eq 'LastContentModified') { $largest = ", largest difference $(Format-LabNumber $field.MaxDifference) s" }
        if ($field.OneSided -gt 0) { $largest += ", $(Format-LabNumber $field.OneSided) known in one listing only" }
        Add-LabCheck -Name "compare-$name" -Status $(if ($field.Differing -le $tolerance) { 'PASS' } else { 'FAIL' }) -Detail "$($field.Differing) of $($compare.InBoth) sites differ$largest."
    }
}

Write-LabLine
Write-LabLine 'The checks'
foreach ($check in $script:Checks) {
    Write-LabLine "  [$($check.Status)] $($check.Name): $($check.Detail)"
}

$failed = @($script:Checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$passed = @($script:Checks | Where-Object { $_.Status -eq 'PASS' }).Count
$informational = @($script:Checks | Where-Object { $_.Status -eq 'INFO' }).Count
Write-LabLine "  $passed PASS, $failed FAIL, $informational INFO."

if ($null -ne $compare) {
    foreach ($name in $compare.Fields.Keys) {
        foreach ($example in $compare.Fields[$name].Examples) {
            Write-LabLine "  difference in $name for site $($example.SiteId): paged $($example.Paged), cmdlet $($example.Cmdlet)"
        }
    }
}

$report = [PSCustomObject][ordered]@{
    Tool        = 'SPSSiteLifecycle listing lab'
    GeneratedOn = Format-LabDate -Value ([System.DateTime]::UtcNow)
    Environment = $environment
    Asked       = [PSCustomObject][ordered]@{
        Source            = $sourceName
        LockState         = @($lockStates)
        StopAfterPages    = $pagesLimit
        Restart           = [System.Boolean]$Restart
        CompareWithCmdlet = [System.Boolean]$CompareWithCmdlet
        ExpectedSites     = $sitesExpected
    }
    Completed   = $main.Completed
    Summary     = $safeSummary
    Statistics  = $statistics
    Checks      = $script:Checks.ToArray()
    Compare     = $compare
}

$null = New-Item -ItemType Directory -Path $folder -Force
$reportPath = Join-Path -Path $folder -ChildPath 'listing-lab-report.json'
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-LabLine '  Report saved: listing-lab-report.json, in the output folder.'

if ($failed -gt 0) {
    Write-Warning -Message "$failed check(s) failed: read the lines marked FAIL."
}

if ($PassThru) {
    $report
}
