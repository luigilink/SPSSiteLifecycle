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

    .PARAMETER TenantName
    The name of the tenant, in lowercase, as in <name>.onmicrosoft.com. The Microsoft corporate tenants are refused.

    .PARAMETER ClientId
    The application (client) ID of the Entra ID app registration for the interactive sign-in.

    .PARAMETER LockState
    The lock states that the Scan lists. With ReadOnly alone, the server filters the listing; with both, it gives the whole
    tenant. Default: both.

    .PARAMETER Source
    Auto (the paged call, and the cmdlet when the paged call is not there), Csom (the paged call only) or Cmdlet.

    .PARAMETER OutputFolder
    Where the checkpoint and the report go. A relative path is relative to the location of the PowerShell session. Default: a
    folder in the temporary folder.

    .PARAMETER StopAfterPages
    Stops after that many pages read from the tenant in this run, and leaves the checkpoint. 0 (the default) does not stop.

    .PARAMETER Restart
    Ignores the checkpoint and starts again.

    .PARAMETER CompareWithCmdlet
    Lists the sites a second time with Get-PnPTenantSite, and compares them with the first listing. It keeps the sites of the
    first listing in memory: use it on a tenant of some thousand sites.

    .PARAMETER ExpectedSites
    The number of sites that the tenant has, if you know it. 0 (the default) means that it is not given.

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
    [System.Guid]
    $ClientId,

    [Parameter()]
    [ValidateSet('ReadOnly', 'Unlock')]
    [System.String[]]
    $LockState = @('ReadOnly', 'Unlock'),

    [Parameter()]
    [ValidateSet('Auto', 'Csom', 'Cmdlet')]
    [System.String]
    $Source = 'Auto',

    [Parameter()]
    [System.String]
    $OutputFolder = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'SPSSiteLifecycle-lab'),

    [Parameter()]
    [ValidateRange(0, 100000)]
    [System.Int32]
    $StopAfterPages = 0,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $Restart,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $CompareWithCmdlet,

    [Parameter()]
    [ValidateRange(0, 100000000)]
    [System.Int32]
    $ExpectedSites = 0,

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
    $Statistic.LockStates["$($Record.LockState)"] = 1 + [System.Int32]$Statistic.LockStates["$($Record.LockState)"]
    $Statistic.Templates["$($Record.Template)"] = 1 + [System.Int32]$Statistic.Templates["$($Record.Template)"]
    $Statistic.Archive["$($Record.ArchiveStatus)"] = 1 + [System.Int32]$Statistic.Archive["$($Record.ArchiveStatus)"]
    if ($Record.IsTeamsConnected) { $Statistic.TeamsConnected++ }
    if ($Record.IsTeamsChannelConnected) { $Statistic.TeamsChannelConnected++ }
    if ($Record.IsHubSite) { $Statistic.HubSites++ }
    if (-not $Record.GroupId) {
        $Statistic.WithoutGroup++
        if ("$($Record.Template)".StartsWith('GROUP#', [System.StringComparison]::OrdinalIgnoreCase)) { $Statistic.GroupSitesWithoutGroup++ }
    }

    $Statistic.TotalSizeMB += [System.Int64]$Record.StorageUsedMB
    if ([System.Int64]$Record.StorageUsedMB -lt 0) { $Statistic.NegativeSizes++ }
    if ("$($Record.Url)".IndexOf('-my.sharepoint.com', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $Statistic.OneDriveSites++ }

    $guid = [System.Guid]::Empty
    $complete = [System.Guid]::TryParse("$($Record.SiteId)", [ref]$guid) -and
        "$($Record.Url)".StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase) -and
        [bool]$Record.Template -and
        [bool]$Record.LockState
    if (-not $complete) {
        $Statistic.Malformed++
        if ($Statistic.MalformedExamples.Count -lt 3) { $Statistic.MalformedExamples.Add("$($Record.SiteId)") }
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

    for ($exception = $ErrorRecord.Exception; $null -ne $exception; $exception = $exception.InnerException) {
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
    $state = [PSCustomObject]@{ Pages = 0; Stop = $PagesToRead; Print = $Print; Preference = $InformationPreference }

    # A closure is cut off from the functions of this script: it holds only what it is given, and cmdlets.
    $onProgress = {
        param($Progress)
        $InformationPreference = $state.Preference
        if (-not $Progress.FromCheckpoint) {
            $state.Pages++
        }

        if ($state.Print -and ($Progress.Pages -le 3 -or ($Progress.Pages % 10) -eq 0)) {
            $how = if ($Progress.FromCheckpoint) { 'from the checkpoint' } else { $Progress.PageSeconds.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) + ' s' }
            Write-Information -MessageData ('  page {0}: {1} sites so far ({2})' -f $Progress.Pages, $Progress.SitesReturned.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture), $how)
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
        & $Module { param($p) Get-SPSLifecycleTenantSite @p } $parameters | ForEach-Object { & $OnRecord $_ }
        $completed = $true
    }
    catch {
        if (-not (Test-LabStop -ErrorRecord $_)) {
            throw
        }
    }

    [PSCustomObject]@{ Summary = $summary; Completed = $completed; Pages = $state.Pages }
}

function Compare-LabListing {
    param([System.Collections.IDictionary]$Paged, [System.Collections.IDictionary]$Cmdlet)

    # The values of these fields can be shown in the report; the address and the title name the tenant and the site.
    $shown = @('Template', 'LockState', 'GroupId', 'ArchiveStatus', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'StorageUsedMB', 'LastContentModified')
    $fields = [ordered]@{}
    foreach ($name in 'Url', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified') {
        $fields[$name] = [PSCustomObject]@{ Differing = 0; MaxDifference = 0; Examples = [System.Collections.Generic.List[System.Object]]::new() }
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
            if ($name -eq 'StorageUsedMB') {
                $difference = [System.Math]::Abs([System.Int64]$a - [System.Int64]$b)
                $same = $difference -eq 0
            }
            elseif ($name -eq 'LastContentModified') {
                if ($null -eq $a -or $null -eq $b) {
                    $same = $null -eq $a -and $null -eq $b
                }
                else {
                    $difference = [System.Math]::Abs(([System.DateTime]$a - [System.DateTime]$b).TotalSeconds)
                    $same = $difference -le 1
                }
            }
            else {
                $same = [System.String]::Equals("$a", "$b", [System.StringComparison]::OrdinalIgnoreCase)
            }

            if (-not $same) {
                $entry = $fields[$name]
                $entry.Differing++
                if ($difference -gt $entry.MaxDifference) {
                    $entry.MaxDifference = $difference
                }

                if ($entry.Examples.Count -lt 3) {
                    $example = if ($shown -contains $name) { [PSCustomObject]@{ SiteId = $id; Paged = "$a"; Cmdlet = "$b" } } else { [PSCustomObject]@{ SiteId = $id; Paged = '(not shown)'; Cmdlet = '(not shown)' } }
                    $entry.Examples.Add($example)
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
} $TenantName $ClientId $folder $LockState
& $module { param($s) Assert-SPSLifecycleTenantAllowed -Setting $s } $setting

$installed = @(Get-Module -Name 'PnP.PowerShell' -ListAvailable | Sort-Object -Property Version -Descending) | Select-Object -First 1
$environment = [PSCustomObject][ordered]@{
    PowerShell    = $PSVersionTable.PSVersion.ToString()
    OS            = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    Module        = $module.Version.ToString()
    PnPPowerShell = if ($null -ne $installed) { $installed.Version.ToString() } else { 'not found' }
}

$asked = "source $Source, lock states $($LockState -join ', ')"
if ($StopAfterPages -gt 0) { $asked += ", stop after $StopAfterPages page(s)" }
if ($Restart) { $asked += ', restart' }
if ($CompareWithCmdlet) { $asked += ', compare with the cmdlet' }
Write-LabLine 'SPSSiteLifecycle listing lab: it only reads.'
Write-LabLine "PowerShell $($environment.PowerShell) on $($environment.OS); PnP.PowerShell $($environment.PnPPowerShell); module $($environment.Module)."
Write-LabLine "Asked: $asked."
Write-LabLine 'Signing in (interactive): a window opens.'

# The first listing: the one that is checked.
$statistic = Initialize-LabStatistic
$paged = if ($CompareWithCmdlet) { @{} } else { $null }
$main = Invoke-LabListing -Module $module -Setting $setting -ListingSource $Source -RestartListing ([System.Boolean]$Restart) -PagesToRead $StopAfterPages -Print $true -OnRecord {
    param($record)
    Add-LabRecord -Statistic $statistic -Record $record
    if ($null -ne $paged) {
        $paged["$($record.SiteId)"] = $record
    }
}
$summary = $main.Summary

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
        $null = Invoke-LabListing -Module $module -Setting $cmdletSetting -ListingSource 'Cmdlet' -RestartListing $true -PagesToRead 0 -Print $false -OnRecord {
            param($record)
            $other["$($record.SiteId)"] = $record
        }
        $compare = Compare-LabListing -Paged $paged -Cmdlet $other
    }
}

# What was read.
$pagesInThisRun = [System.Int32]$summary.PagesRead
$averagePage = if ($pagesInThisRun -gt 0) { $summary.PageSecondsTotal / $pagesInThisRun } else { 0.0 }
$rate = if ($summary.PageSecondsTotal -gt 0) { $summary.SitesRead / $summary.PageSecondsTotal } else { 0.0 }
$digest = Get-LabDigest -SiteId $statistic.SiteIds
$newest = @($statistic.NewestSites | ForEach-Object { [PSCustomObject][ordered]@{ SiteId = $_.SiteId; LastContentModified = Format-LabDate -Value $_.Date } })
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
    WithoutDate            = $statistic.WithoutDate
    OldestChange           = Format-LabDate -Value $statistic.Oldest
    NewestChange           = Format-LabDate -Value $statistic.Newest
    NewestSites            = $newest
    SiteIdDigest           = $digest
}

$sourceText = $summary.Source
if ($summary.FallbackReason) { $sourceText += " ($($summary.FallbackReason))" }
$filterText = if ($summary.Filter) { $summary.Filter } else { '(none)' }
if ($summary.Resumed) {
    $checkpointText = "taken up ($($summary.PagesFromCheckpoint) pages, $(Format-LabNumber $summary.SitesFromCheckpoint) sites from it)"
}
elseif ($summary.StartReason) {
    $checkpointText = "not taken up: $($summary.StartReason)"
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
    $why = if ($summary.FallbackReason) { $summary.FallbackReason } else { 'It was asked for.' }
    Add-LabCheck -Name 'source' -Status INFO -Detail "Get-PnPTenantSite was used. $why"
}

if ($summary.Resumed) {
    Add-LabCheck -Name 'resume' -Status PASS -Detail "The listing took up a checkpoint: $($summary.PagesFromCheckpoint) pages ($(Format-LabNumber $summary.SitesFromCheckpoint) sites) came from it; pages read from the tenant: $pagesInThisRun."
}
else {
    $why = if ($summary.StartReason) { " $($summary.StartReason)" } else { '' }
    Add-LabCheck -Name 'resume' -Status INFO -Detail "The listing started from the first page.$why"
}

if ($main.Completed -and $ExpectedSites -gt 0) {
    if ($statistic.Sites -eq $ExpectedSites) {
        Add-LabCheck -Name 'expected-sites' -Status PASS -Detail "$(Format-LabNumber $statistic.Sites) sites, as expected."
    }
    else {
        Add-LabCheck -Name 'expected-sites' -Status FAIL -Detail "$(Format-LabNumber $statistic.Sites) sites were listed, and $(Format-LabNumber $ExpectedSites) were expected."
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
Add-LabCheck -Name 'sizes' -Status $(if ($statistic.NegativeSizes -eq 0) { 'PASS' } else { 'FAIL' }) -Detail "$(Format-LabNumber $statistic.NegativeSizes) sites with a size below zero."
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
        if ($field.Differing -gt 0 -and $name -eq 'StorageUsedMB') { $largest = ", largest difference $(Format-LabNumber $field.MaxDifference) MB" }
        if ($field.Differing -gt 0 -and $name -eq 'LastContentModified') { $largest = ", largest difference $(Format-LabNumber $field.MaxDifference) s" }
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
        Source            = $Source
        LockState         = @($LockState)
        StopAfterPages    = $StopAfterPages
        Restart           = [System.Boolean]$Restart
        CompareWithCmdlet = [System.Boolean]$CompareWithCmdlet
        ExpectedSites     = $ExpectedSites
    }
    Completed   = $main.Completed
    Summary     = $summary
    Statistics  = $statistics
    Checks      = $script:Checks.ToArray()
    Compare     = $compare
}

$null = New-Item -ItemType Directory -Path $folder -Force
$reportPath = Join-Path -Path $folder -ChildPath 'listing-lab-report.json'
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-LabLine "  Report saved: $reportPath"

if ($failed -gt 0) {
    Write-Warning -Message "$failed check(s) failed: read the lines marked FAIL."
}

if ($PassThru) {
    $report
}
