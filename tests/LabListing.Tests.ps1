BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Lab = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../tools/lab/Test-TenantListing.ps1')).ProviderPath
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    # A record as the listing gives it. Its address and its title name the tenant and the site, which the lab must never print.
    function script:New-LabRecord {
        param([int]$Index, [hashtable]$Override = @{})

        $values = [ordered]@{
            Url                     = "https://contoso.sharepoint.com/sites/site$Index"
            SiteId                  = ('{0:x8}-0000-4000-8000-{1:x12}' -f $Index, $Index)
            Title                   = "Secret title $Index"
            Template                = 'GROUP#0'
            LockState               = 'ReadOnly'
            GroupId                 = ('{0:x8}-1111-4111-8111-{1:x12}' -f $Index, $Index)
            IsHubSite               = $false
            IsTeamsConnected        = $true
            IsTeamsChannelConnected = $false
            ArchiveStatus           = 'NotArchived'
            StorageUsedMB           = [long](10 * $Index)
            LastContentModified     = $script:Now.AddDays(-$Index)
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    # Five sites in two pages: three group sites, a communication site and a team site that has no group; four are read-only.
    function script:Set-LabPages {
        $records = @(
            New-LabRecord -Index 1
            New-LabRecord -Index 2
            New-LabRecord -Index 3 -Override @{ IsTeamsConnected = $false }
            New-LabRecord -Index 4 -Override @{ Template = 'SITEPAGEPUBLISHING#0'; GroupId = ''; IsTeamsConnected = $false; LockState = 'Unlock' }
            New-LabRecord -Index 5 -Override @{ Template = 'STS#3'; GroupId = ''; IsTeamsConnected = $false; IsHubSite = $true }
        )
        & $script:Module {
            param($r)
            $pages = [System.Collections.Generic.List[System.Object]]::new()
            $pages.Add(@($r[0], $r[1], $r[2]))
            $pages.Add(@($r[3], $r[4]))
            $script:StubData.Pages = $pages.ToArray()
        } $records
        $records
    }

    function script:Invoke-Lab {
        param([hashtable]$Parameter = @{})

        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $arguments = @{
            TenantName          = 'contoso'
            ClientId            = [System.Guid]'11111111-2222-3333-4444-555555555555'
            OutputFolder        = $folder
            InformationAction   = 'SilentlyContinue'
            InformationVariable = 'info'
            WarningAction       = 'SilentlyContinue'
            PassThru            = $true
        }
        foreach ($key in $Parameter.Keys) {
            $arguments[$key] = $Parameter[$key]
        }

        $output = @(& $script:Lab @arguments 2>&1 3>&1 4>&1 5>&1)
        $warning = [System.Management.Automation.WarningRecord]
        $verbose = [System.Management.Automation.VerboseRecord]
        $debug = [System.Management.Automation.DebugRecord]
        $failure = [System.Management.Automation.ErrorRecord]
        [PSCustomObject]@{
            Report   = @($output | Where-Object { $_ -isnot $warning -and $_ -isnot $verbose -and $_ -isnot $debug -and $_ -isnot $failure }) | Select-Object -First 1
            Text     = @($info | ForEach-Object { "$($_.MessageData)" })
            Folder   = $arguments.OutputFolder
            Warnings = @($output | Where-Object { $_ -is $warning } | ForEach-Object { $_.Message })
            Verbose  = @($output | Where-Object { $_ -is $verbose } | ForEach-Object { $_.Message })
            Debug    = @($output | Where-Object { $_ -is $debug } | ForEach-Object { $_.Message })
            Errors   = @($output | Where-Object { $_ -is $failure } | ForEach-Object { "$($_.Exception.Message)" })
        }
    }

    # Everything that the lab said and wrote in a run: what it printed, the warnings and the verbose lines it let through, and the report file.
    function script:Get-LabEverything {
        param($Run)

        $file = Join-Path -Path $Run.Folder -ChildPath 'listing-lab-report.json'
        $json = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw } else { '' }
        (@($Run.Text) + @($Run.Warnings) + @($Run.Verbose) + @($Run.Debug) + @($Run.Errors) + $json) -join "`n"
    }

    function script:Get-LabCheck {
        param($Report, [string]$Name)
        @($Report.Checks | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    }

    # An exception type that is not the framework's and is named like what must never be shown, and one whose inner exception is
    # itself (a type of the library can do that, and the lab walks the chain).
    if (-not ('Microsoft.OfflineLab.SyntheticPrivateBoardException' -as [System.Type])) {
        Add-Type -TypeDefinition @'
public class SyntheticPrivateBoardException : System.Exception
{
    public SyntheticPrivateBoardException(string message) : base(message) { }
}

public class SyntheticPrivateBoardDerivedException : System.InvalidOperationException
{
    public SyntheticPrivateBoardDerivedException(string message) : base(message) { }
}

namespace Microsoft.OfflineLab
{
    public class SyntheticPrivateBoardException : System.Exception
    {
        public SyntheticPrivateBoardException(string message) : base(message) { }
    }
}

namespace System.OfflineLab
{
    public class SyntheticPrivateBoardException : System.Exception
    {
        public SyntheticPrivateBoardException(string message) : base(message) { }
    }
}

namespace PnP.OfflineLab
{
    public class SyntheticPrivateBoardException : System.Exception
    {
        public SyntheticPrivateBoardException(string message) : base(message) { }
    }
}

namespace Newtonsoft.OfflineLab
{
    public class SyntheticPrivateBoardException : System.Exception
    {
        public SyntheticPrivateBoardException(string message) : base(message) { }
    }
}

public class SyntheticCyclicException : System.Exception
{
    public SyntheticCyclicException(string message) : base(message) { }
    public new System.Exception InnerException { get { return this; } }
}
'@
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'The lab script that lists a tenant' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Open-SPSLifecycleTenantSession'  = @'
param($Setting)
$script:StubLog.Add('open')
if ($script:StubData.OpenError) { throw $script:StubData.OpenError }
[PSCustomObject]@{ Connection = 'a connection'; TenantName = 'contoso' }
'@
            'Close-SPSLifecycleTenantSession' = @'
param($Session)
$script:StubLog.Add('close')
'@
            'Test-SPSLifecycleListingApi'     = @'
$script:StubLog.Add('api checked')
[PSCustomObject]@{ Available = $script:StubData.ApiAvailable; Reason = $script:StubData.ApiReason }
'@
            'Start-Sleep'                     = @'
param([double]$Seconds)
'@
            'Get-SPSLifecycleTenantSitePage'  = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add("page source=$Source start=[$StartIndex]")
if ($script:StubData.Noise) {
    Write-Information 'SyntheticPrivateBoard for syntheticowner@fabrikam.example' -InformationAction Continue
    Write-Host 'Host text of SyntheticPrivateBoard'
    $DebugPreference = 'Continue'
    Write-Debug 'Debug text of SyntheticPrivateBoard'
    Write-Error 'Error text of SyntheticPrivateBoard' -ErrorAction Continue
}
if ($script:StubData.Warn) {
    Write-Warning 'Warning text of SyntheticPrivateBoard'
}
if ($script:StubData.PageException) { throw $script:StubData.PageException }
if ($script:StubData.PageError -and $script:StubData.PageErrorLeft -ne 0) { $script:StubData.PageErrorLeft--; throw $script:StubData.PageError }
if ($Source -eq 'Cmdlet') {
    $all = if ($null -ne $script:StubData.CmdletSites) { $script:StubData.CmdletSites } else { @($script:StubData.Pages | ForEach-Object { $_ }) }
    return [PSCustomObject]@{ Items = @($all); NextStartIndex = '' }
}

$pages = $script:StubData.Pages
$index = if ($StartIndex -eq '') { 0 } else { [int]$StartIndex.Substring(1) }
$next = if ($index + 1 -lt $pages.Count) { 't' + ($index + 1) } else { '' }
[PSCustomObject]@{ Items = @($pages[$index]); NextStartIndex = $next }
'@
        } -Data @{ ApiAvailable = $true; ApiReason = ''; Pages = @(); CmdletSites = $null; PageError = ''; PageErrorLeft = -1; OpenError = ''; PageException = $null; Noise = $false }
    }

    AfterEach {
        Clear-ModuleStub
    }

    Context 'Before it reads anything' {
        It 'refuses a tenant name that is not a lowercase ASCII name: <Name>' -ForEach @(
            @{ Name = 'capitals'; Value = 'Contoso' }
            @{ Name = 'an address'; Value = 'contoso.sharepoint.com' }
            @{ Name = 'the admin address'; Value = 'contoso-admin.sharepoint.com' }
            @{ Name = 'an empty name'; Value = '' }
            @{ Name = 'a dotted capital I'; Value = "$([char]0x0130)stanbul" }
            @{ Name = 'the Kelvin sign'; Value = "$([char]0x212A)ilo" }
            @{ Name = 'a leading hyphen'; Value = '-contoso' }
        ) {
            { Invoke-Lab -Parameter @{ TenantName = $Value } } | Should -Throw

            Get-StubLog | Should -HaveCount 0
        }

        It 'refuses a tenant that the tool never runs on, before it signs in' {
            { Invoke-Lab -Parameter @{ TenantName = 'microsoft' } } | Should -Throw -ExpectedMessage '*refused*'

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'The listing' {
        It 'lists the sites with the code of the Scan, and reports what it found' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $run.Report.Completed | Should -BeTrue
            $run.Report.Summary.Source | Should -BeExactly 'Csom'
            $run.Report.Summary.PagesRead | Should -Be 2
            $run.Report.Summary.SitesReturned | Should -Be 5
            $run.Report.Statistics.Sites | Should -Be 5
            $run.Report.Statistics.LockStates.ReadOnly | Should -Be 4
            $run.Report.Statistics.LockStates.Unlock | Should -Be 1
            $run.Report.Statistics.Templates.'GROUP#0' | Should -Be 3
            $run.Report.Statistics.TeamsConnected | Should -Be 2
            $run.Report.Statistics.HubSites | Should -Be 1
            $run.Report.Statistics.WithoutGroup | Should -Be 2
            $run.Report.Statistics.TotalSizeMB | Should -Be 150
            Get-StubLog | Should -Be @('open', 'api checked', 'page source=Csom start=[]', 'page source=Csom start=[t1]', 'close')
            @($run.Report.Checks | Where-Object Status -eq 'FAIL') | Should -HaveCount 0
        }

        It 'asks the server for the whole tenant when both lock states are listed, and for one state otherwise' {
            $null = Set-LabPages

            $both = Invoke-Lab
            $one = Invoke-Lab -Parameter @{ LockState = 'ReadOnly' }

            $both.Report.Summary.Filter | Should -BeExactly ''
            $one.Report.Summary.Filter | Should -BeExactly "LockState -eq 'ReadOnly'"
        }

        It 'writes the same report to a file of the output folder' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $file = Join-Path -Path $run.Folder -ChildPath 'listing-lab-report.json'
            Test-Path -LiteralPath $file | Should -BeTrue
            $json = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            $json.Statistics.Sites | Should -Be 5
            $json.Summary.Source | Should -BeExactly 'Csom'
            @($json.Checks) | Should -Not -BeNullOrEmpty
        }

        It 'never prints or writes the name of the tenant, an address or a title' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $everything = ($run.Text -join "`n") + (Get-Content -LiteralPath (Join-Path -Path $run.Folder -ChildPath 'listing-lab-report.json') -Raw)
            $everything | Should -Not -BeLike '*contoso*'
            $everything | Should -Not -BeLike '*sharepoint.com*'
            $everything | Should -Not -BeLike '*Secret title*'
            $everything | Should -Not -BeLike '*11111111-2222-3333-4444-555555555555*'
            $run.Text.Count | Should -BeGreaterThan 10
        }

        It 'names the sites that changed last, newest first, with their date in UTC' {
            $records = Set-LabPages

            $run = Invoke-Lab

            @($run.Report.Statistics.NewestSites | ForEach-Object { $_.SiteId }) | Should -Be @($records[0].SiteId, $records[1].SiteId, $records[2].SiteId)
            $run.Report.Statistics.NewestSites[0].LastContentModified | Should -BeExactly '2026-10-29T09:00:00Z'
            ($run.Text -join "`n") | Should -BeLike '*2026-10-29T09:00:00Z*'
        }

        It 'gives a digest of the sites, which is the same whatever the order of the pages' {
            $null = Set-LabPages
            $first = Invoke-Lab

            & $script:Module { $script:StubData.Pages = @($script:StubData.Pages[1], $script:StubData.Pages[0]) }
            $second = Invoke-Lab

            $first.Report.Statistics.SiteIdDigest | Should -Match '^[0-9a-f]{16}$'
            $second.Report.Statistics.SiteIdDigest | Should -BeExactly $first.Report.Statistics.SiteIdDigest
        }

        It 'passes the check of the number of sites when it is the one that was given, and fails it when it is not' {
            $null = Set-LabPages

            $right = Invoke-Lab -Parameter @{ ExpectedSites = 5 }
            $wrong = Invoke-Lab -Parameter @{ ExpectedSites = 6 }

            (Get-LabCheck -Report $right.Report -Name 'expected-sites').Status | Should -BeExactly 'PASS'
            (Get-LabCheck -Report $wrong.Report -Name 'expected-sites').Status | Should -BeExactly 'FAIL'
            (Get-LabCheck -Report $wrong.Report -Name 'expected-sites').Detail | Should -BeLike '*5*6*'
        }

        It 'reports a group site with no group, for the Scan gives it a review verdict' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Pages[0][1].GroupId = '' }

            $run = Invoke-Lab

            $check = Get-LabCheck -Report $run.Report -Name 'group-sites-have-a-group'
            $check.Status | Should -BeExactly 'INFO'
            $check.Detail | Should -BeLike '*1 sites*'
            $run.Report.Statistics.GroupSitesWithoutGroup | Should -Be 1
        }

        It 'counts a site whose group is the empty GUID as a site with no group' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Pages[0][1].GroupId = '00000000-0000-0000-0000-000000000000' }

            $run = Invoke-Lab

            $run.Report.Statistics.WithoutGroup | Should -Be 3
            $run.Report.Statistics.GroupSitesWithoutGroup | Should -Be 1
            (Get-LabCheck -Report $run.Report -Name 'group-sites-have-a-group').Status | Should -BeExactly 'INFO'
        }

        It 'counts a site with no size apart from a site of size zero, and does not add it up as a size' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Pages[0][0].StorageUsedMB = $null; $script:StubData.Pages[0][1].StorageUsedMB = [long]0 }

            $run = Invoke-Lab

            $run.Report.Statistics.WithoutSize | Should -Be 1
            $run.Report.Statistics.TotalSizeMB | Should -Be 120
            $check = Get-LabCheck -Report $run.Report -Name 'sizes'
            $check.Status | Should -BeExactly 'INFO'
            $check.Detail | Should -BeLike '*1 sites with no size*'
            $check.Detail | Should -BeLike '*0 sites with a size below zero*'
        }

        It 'fails a size below zero, whether or not a size is missing too' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Pages[0][0].StorageUsedMB = [long]-5; $script:StubData.Pages[0][1].StorageUsedMB = $null }

            $run = Invoke-Lab

            $run.Report.Statistics.NegativeSizes | Should -Be 1
            (Get-LabCheck -Report $run.Report -Name 'sizes').Status | Should -BeExactly 'FAIL'
            (Get-LabCheck -Report $run.Report -Name 'sizes').Detail | Should -BeLike '*1 sites with a size below zero*'
        }

        It 'passes the check of the sizes when every site has one' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $run.Report.Statistics.WithoutSize | Should -Be 0
            (Get-LabCheck -Report $run.Report -Name 'sizes').Status | Should -BeExactly 'PASS'
        }

        It 'says that the paged call was used, and says why when the cmdlet was used instead' {
            $null = Set-LabPages
            $paged = Invoke-Lab
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'The types of the SharePoint admin API (Tenant, SPOSitePropertiesEnumerableFilter, PersonalSiteFilter) are not in this PnP.PowerShell.' }
            $fallback = Invoke-Lab

            (Get-LabCheck -Report $paged.Report -Name 'source').Status | Should -BeExactly 'PASS'
            (Get-LabCheck -Report $fallback.Report -Name 'source').Status | Should -BeExactly 'INFO'
            (Get-LabCheck -Report $fallback.Report -Name 'source').Detail | Should -BeLike '*(Tenant, SPOSitePropertiesEnumerableFilter, PersonalSiteFilter) are not in this PnP.PowerShell.*'
            $fallback.Report.Summary.Source | Should -BeExactly 'Cmdlet'
        }

        It 'stops, and says why, when the paged call is asked for and is not there' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = "The filter of the admin API has no property 'StartIndex' in this PnP.PowerShell." }

            { Invoke-Lab -Parameter @{ Source = 'Csom' } } | Should -Throw -ExpectedMessage '*StartIndex*'
        }
    }

    Context 'The resume' {
        It 'stops after the pages that it was told to, leaves the checkpoint, and says how to go on' {
            $null = Set-LabPages

            $run = Invoke-Lab -Parameter @{ StopAfterPages = 1 }

            $run.Report.Completed | Should -BeFalse
            $run.Report.Summary.PagesRead | Should -Be 1
            (Get-LabCheck -Report $run.Report -Name 'listing-ended').Status | Should -BeExactly 'INFO'
            Test-Path -LiteralPath (Join-Path -Path $run.Folder -ChildPath 'listing-checkpoint/manifest.json') | Should -BeTrue
            ($run.Text -join "`n") | Should -BeLike '*without -StopAfterPages*'
            Get-StubLog | Should -Not -Contain 'page source=Csom start=[t1]'
            @(Get-StubLog)[-1] | Should -BeExactly 'close'
        }

        It 'takes the listing up where it stopped, and gives the same sites as a listing that started again' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'resume'

            $stopped = Invoke-Lab -Parameter @{ StopAfterPages = 1; OutputFolder = $folder }
            $resumed = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            $again = Invoke-Lab -Parameter @{ OutputFolder = $folder; Restart = $true }

            $stopped.Report.Completed | Should -BeFalse
            $resumed.Report.Completed | Should -BeTrue
            $resumed.Report.Summary.Resumed | Should -BeTrue
            $resumed.Report.Summary.PagesFromCheckpoint | Should -Be 1
            $resumed.Report.Summary.PagesRead | Should -Be 1
            (Get-LabCheck -Report $resumed.Report -Name 'resume').Status | Should -BeExactly 'PASS'
            $resumed.Report.Statistics.Sites | Should -Be 5
            $again.Report.Summary.Resumed | Should -BeFalse
            $resumed.Report.Statistics.SiteIdDigest | Should -BeExactly $again.Report.Statistics.SiteIdDigest
        }
    }

    Context 'What it never says' {
        It 'does not name the tenant that a checkpoint was made for, in what it prints, warns, writes or lets through as verbose' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'other-tenant'
            $null = Invoke-Lab -Parameter @{ TenantName = 'fabrikam'; StopAfterPages = 1; OutputFolder = $folder }
            $before = $global:VerbosePreference
            $global:VerbosePreference = 'Continue'
            try {
                $run = Invoke-Lab -Parameter @{ OutputFolder = $folder; WarningAction = 'Continue'; Verbose = $true }
            }
            finally {
                $global:VerbosePreference = $before
            }

            $everything = Get-LabEverything -Run $run
            $everything | Should -Not -BeLike '*fabrikam*'
            $everything | Should -Not -BeLike '*contoso*'
            $run.Report.Summary.Resumed | Should -BeFalse
            $run.Report.Summary.StartCode | Should -BeExactly 'other-tenant'
            $run.Report.Summary.PSObject.Properties.Name | Should -Not -Contain 'StartReason'
            ($run.Text -join "`n") | Should -BeLike '*made for another tenant*'
            (Get-LabCheck -Report $run.Report -Name 'resume').Detail | Should -BeLike '*made for another tenant*'
        }

        It 'says that the listing warned, without the text of the warning, which can name a tenant' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'warned'
            $null = Invoke-Lab -Parameter @{ TenantName = 'fabrikam'; StopAfterPages = 1; OutputFolder = $folder }

            $warned = Invoke-Lab -Parameter @{ OutputFolder = $folder; WarningAction = 'Continue' }
            $quiet = Invoke-Lab

            $warned.Warnings | Should -HaveCount 0
            (Get-LabCheck -Report $warned.Report -Name 'listing-warnings').Status | Should -BeExactly 'INFO'
            (Get-LabCheck -Report $warned.Report -Name 'listing-warnings').Detail | Should -BeLike '*1 warning*not shown*'
            $warned.Report.Summary.WarningCount | Should -Be 1
            (Get-LabCheck -Report $quiet.Report -Name 'listing-warnings').Status | Should -BeExactly 'PASS'
            $quiet.Report.Summary.WarningCount | Should -Be 0
        }

        It 'says why a checkpoint was not taken up with its own words, whatever the module wrote: <Code>' -ForEach @(
            @{ Code = 'damaged'; Words = '*was damaged*' }
            @{ Code = 'other-version'; Words = '*another version*' }
            @{ Code = 'finished'; Words = '*had ended*' }
            @{ Code = 'other-tenant'; Words = '*another tenant*' }
            @{ Code = 'other-filter'; Words = '*another filter*' }
            @{ Code = 'other-options'; Words = '*other options*' }
            @{ Code = 'clock'; Words = '*clock*' }
            @{ Code = 'too-old'; Words = '*too old*' }
            @{ Code = 'a-code-from-the-future'; Words = '*does not know*' }
            @{ Code = 'DAMAGED'; Words = '*does not know*' }
            @{ Code = 'Other-Tenant'; Words = '*does not know*' }
            @{ Code = 'a code that names fabrikam@contoso.com'; Words = '*does not know*' }
        ) {
            Set-ModuleStub -Stub @{
                'Read-SPSLifecycleListingCheckpoint' = @'
[PSCustomObject]@{ Exists = $true; Usable = $false; Finished = $false; Reason = "The checkpoint was made for fabrikam ($($script:StubData.ReaderCode))."; Code = $script:StubData.ReaderCode; Manifest = $null }
'@
            } -Data @{ ApiAvailable = $true; ApiReason = ''; Pages = @(); CmdletSites = $null; PageError = ''; PageErrorLeft = -1; OpenError = ''; PageException = $null; Noise = $false; ReaderCode = $Code }
            $null = Set-LabPages

            $run = Invoke-Lab

            $everything = Get-LabEverything -Run $run
            $everything | Should -Not -BeLike '*fabrikam*'
            $everything | Should -Not -BeLike '*contoso*'
            (Get-LabCheck -Report $run.Report -Name 'resume').Detail | Should -BeLike $Words
            ($run.Text -join "`n") | Should -BeLike "*not taken up: *$Words"
            if ($Code -cmatch '^[a-z]+(-[a-z]+)*$' -and $Code -ne 'a-code-from-the-future') {
                $run.Report.Summary.StartCode | Should -BeExactly $Code
            }
            else {
                $run.Report.Summary.StartCode | Should -BeExactly 'unknown'
            }
        }

        It 'says nothing of a checkpoint when there was none, and when the listing was asked to start again' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'restart'

            $none = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            $again = Invoke-Lab -Parameter @{ OutputFolder = $folder; Restart = $true }

            $none.Report.Summary.StartCode | Should -BeExactly ''
            ($none.Text -join "`n") | Should -BeLike '*Checkpoint: none to take up*'
            $again.Report.Summary.StartCode | Should -BeExactly 'restart'
            ($again.Text -join "`n") | Should -BeLike '*Checkpoint: not taken up: a new listing was asked for*'
        }

        It 'says the type of an error of the tenant, the codes that it holds and where it stopped, and never its text, which can name anything' {
            $null = Set-LabPages
            $raw = 'Synthetic failure for site SyntheticPrivateBoard, owned by syntheticowner (jc@fabrikam.com); tenant fabrikam at https://fabrikam.sharepoint.com/sites/x. (403) Forbidden. AADSTS65001: consent was not given.'
            & $script:Module { param($t) $script:StubData.PageError = $t } $raw

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $message = $thrown.Exception.Message
            $message | Should -BeLike 'The lab stopped: Page 1 of the listing could not be read after 3 attempts.*'
            $message | Should -BeLike '*InvalidOperationException*caused by RuntimeException*'
            $message | Should -BeLike '*HTTP 403*'
            $message | Should -BeLike '*AADSTS65001*'
            foreach ($name in 'Synthetic', 'syntheticowner', 'fabrikam', 'contoso', 'sharepoint', 'Forbidden', 'consent') {
                $message | Should -Not -BeLike "*$name*" -Because $name
            }

            $thrown.Exception.InnerException | Should -BeNullOrEmpty
        }

        It 'keeps the text of an error in a file of the output folder, with the checkpoint, and says so' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'error-file'
            $raw = 'Synthetic failure for site SyntheticPrivateBoard (403) Forbidden.'
            & $script:Module { param($t) $script:StubData.PageError = $t } $raw

            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            }
            catch {
                $thrown = $_
            }

            $file = Join-Path -Path $folder -ChildPath 'listing-lab-error.txt'
            Test-Path -LiteralPath $file | Should -BeTrue
            $saved = Get-Content -LiteralPath $file -Raw
            $saved | Should -BeLike '*SyntheticPrivateBoard*'
            $saved | Should -BeLike '*InvalidOperationException*'
            $saved | Should -BeLike '*RuntimeException*'
            $thrown.Exception.Message | Should -BeLike '*listing-lab-error.txt in the output folder*'
            $thrown.Exception.Message | Should -BeLike '*not share*'
            $thrown.Exception.Message | Should -Not -BeLike '*error-file*'
        }

        It 'says that the sign-in failed, with its code, and not why in words, which can name the account' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.OpenError = 'The sign-in to the admin site of the tenant failed: AADSTS50126 Error validating credentials for jc@contoso.com in the tenant contoso.' }

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike 'The lab stopped: The sign-in to the admin site of the tenant failed.*AADSTS50126*'
            $thrown.Exception.Message | Should -Not -BeLike '*jc@*'
            $thrown.Exception.Message | Should -Not -BeLike '*contoso*'
            $thrown.Exception.Message | Should -Not -BeLike '*credentials*'
        }

        It 'prints the sections of the report, each after a blank line, with the lines of the listing and of the sites' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $text = @($run.Text)
            foreach ($heading in 'The listing', 'The sites', 'The checks') {
                $at = [System.Array]::IndexOf($text, $heading)
                $at | Should -BeGreaterThan 0 -Because $heading
                $text[$at - 1] | Should -BeExactly '' -Because $heading
            }

            [System.Array]::IndexOf($text, 'The listing') | Should -BeLessThan ([System.Array]::IndexOf($text, 'The sites'))
            [System.Array]::IndexOf($text, 'The sites') | Should -BeLessThan ([System.Array]::IndexOf($text, 'The checks'))
            $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            $text | Should -Contain '  Source: Csom'
            $text | Should -Contain '  Filter of the server: (none)'
            $text | Should -Contain '  Checkpoint: none to take up'
            $text | Should -Contain '  Pages read from the tenant: 2, 5 sites; retries: 0'
            $text | Should -Contain '  Sites returned: 5'
            $text | Should -Contain '  Lock states: ReadOnly 4, Unlock 1'
            $text | Should -Contain '  Templates (top 10): GROUP#0 3, SITEPAGEPUBLISHING#0 1, STS#3 1'
            $text | Should -Contain '  Archive status: NotArchived 5'
            $text | Should -Contain '  Connected to Teams: 2; channel sites: 0; hub sites: 1; with no group: 2'
            $text | Should -Contain '  Size: 0.1 GB in all'
            $text | Should -Contain "  Last change (UTC): oldest $($script:Now.AddDays(-5).ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)), newest $($script:Now.AddDays(-1).ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)); sites with no date: 0"
            foreach ($index in 1..3) {
                $text | Should -Contain ('    {0:x8}-0000-4000-8000-{1:x12}  {2}' -f $index, $index, $script:Now.AddDays(-$index).ToString($format, [System.Globalization.CultureInfo]::InvariantCulture))
            }

            @($text | Where-Object { $_ -like '    *-0000-4000-8000-*' }) | Should -HaveCount 3
            @($text | Where-Object { $_ -match '^  Digest of the site IDs: [0-9a-f]{16}$' }) | Should -HaveCount 1
        }

        It 'reports one check for each thing that it looks at, in this order' {
            $null = Set-LabPages

            $run = Invoke-Lab

            @($run.Report.Checks | ForEach-Object { "$($_.Status) $($_.Name)" }) | Should -Be @(
                'PASS listing-ended', 'PASS source', 'INFO resume', 'PASS listing-warnings', 'PASS unique-site-ids', 'PASS records-are-complete',
                'PASS no-onedrive-site', 'PASS sizes', 'PASS group-sites-have-a-group', 'PASS dates')
            (Get-LabCheck -Report $run.Report -Name 'unique-site-ids').Detail | Should -BeExactly '5 different site IDs for 5 sites.'
            (Get-LabCheck -Report $run.Report -Name 'records-are-complete').Detail | Should -BeExactly 'Every site has a site ID, an https address, a template and a lock state.'
            $run.Text | Should -Contain '  9 PASS, 0 FAIL, 1 INFO.'
        }

        It 'takes up a checkpoint that holds every page, reads no page from the tenant, and still reports' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'all-pages-read'
            $stopped = Invoke-Lab -Parameter @{ OutputFolder = $folder; StopAfterPages = 2 }

            $resumed = Invoke-Lab -Parameter @{ OutputFolder = $folder }

            $stopped.Report.Completed | Should -BeFalse
            $resumed.Report.Completed | Should -BeTrue
            $resumed.Report.Summary.PagesRead | Should -Be 0
            $resumed.Report.Summary.PagesFromCheckpoint | Should -Be 2
            $resumed.Report.Statistics.Sites | Should -Be 5
            $resumed.Text | Should -Contain '  Pages read from the tenant: 0, 0 sites; retries: 0'
            ($resumed.Text -join "`n") | Should -Match '  Time: [0-9,]+\.[0-9] s in all; a page took 0\.00 s on average and 0\.00 s at most;'
        }

        It 'writes the report as UTF-8 with no byte order mark' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $run.Folder -ChildPath 'listing-lab-report.json'))
            $bytes.Length | Should -BeGreaterThan 3
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
            $bytes[0] | Should -Be ([byte][char]'{')
        }

        It 'prints the progress of the listing for the first three pages and every tenth, with the numbers written the same way whatever the culture, and says which pages came from the checkpoint' {
            $records = @(1..1200 | ForEach-Object { New-LabRecord -Index $_ })
            & $script:Module {
                param($r)
                $pages = [System.Collections.Generic.List[System.Object]]::new()
                for ($i = 0; $i -lt 12; $i++) {
                    $pages.Add(@($r[($i * 100)..($i * 100 + 99)]))
                }

                $script:StubData.Pages = $pages.ToArray()
            } $records
            $folder = Join-Path -Path $TestDrive -ChildPath 'progress'
            $saved = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $first = Invoke-Lab -Parameter @{ OutputFolder = $folder; StopAfterPages = 2 }
                $second = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $saved
            }

            @($first.Text | Where-Object { $_ -like '  page *' }) | Should -HaveCount 2
            @($second.Text | Where-Object { $_ -like '  page *' }) | Should -HaveCount 4
            $lines = @($second.Text | Where-Object { $_ -like '  page *' })
            $lines[0] | Should -BeExactly '  page 1: 100 sites so far (from the checkpoint)'
            $lines[1] | Should -BeExactly '  page 2: 200 sites so far (from the checkpoint)'
            $lines[2] | Should -Match '^  page 3: 300 sites so far \([0-9]+\.[0-9]{2} s\)$'
            $lines[3] | Should -Match '^  page 10: 1,000 sites so far \([0-9]+\.[0-9]{2} s\)$'
            ($second.Text -join "`n") | Should -Not -BeLike '*  page 4:*'
            ($second.Text -join "`n") | Should -Not -BeLike '*  page 11:*'
            ($second.Text -join "`n") | Should -Not -BeLike '*  page 12:*'
            ($second.Text -join "`n") | Should -BeLike '*Pages read from the tenant: 10, 1,000 sites; retries: 0*'
            ($second.Text -join "`n") | Should -Match '  Time: [0-9,]+\.[0-9] s in all; a page took [0-9]+\.[0-9]{2} s on average and [0-9]+\.[0-9]{2} s at most; [0-9,]+ sites/s'
            ($second.Text -join "`n") | Should -BeLike '*  Left out by the listing: 0 OneDrive sites, 0 sites that came twice*'
            ($second.Text -join "`n") | Should -BeLike '*  Sites returned: 1,200*'
        }

        It 'starts with what it is, what it runs on and what it was asked, and says that a window opens: <Name>' -ForEach @(
            @{ Name = 'nothing but the defaults'; Parameter = @{}; Asked = 'Asked: source Auto, lock states ReadOnly, Unlock.' }
            @{ Name = 'a source and a lock state in lowercase'; Parameter = @{ Source = 'csom'; LockState = 'readonly' }; Asked = 'Asked: source Csom, lock states ReadOnly.' }
            @{ Name = 'a stop after some pages'; Parameter = @{ StopAfterPages = 1 }; Asked = 'Asked: source Auto, lock states ReadOnly, Unlock, stop after 1 page(s).' }
            @{ Name = 'a restart'; Parameter = @{ Restart = $true }; Asked = 'Asked: source Auto, lock states ReadOnly, Unlock, restart.' }
            @{ Name = 'a comparison'; Parameter = @{ CompareWithCmdlet = $true }; Asked = 'Asked: source Auto, lock states ReadOnly, Unlock, compare with the cmdlet.' }
            @{ Name = 'all of them'; Parameter = @{ Source = 'Csom'; LockState = @('Unlock', 'ReadOnly'); StopAfterPages = 1; Restart = $true; CompareWithCmdlet = $true }; Asked = 'Asked: source Csom, lock states Unlock, ReadOnly, stop after 1 page(s), restart, compare with the cmdlet.' }
        ) {
            $null = Set-LabPages

            $run = Invoke-Lab -Parameter $Parameter

            $run.Text[0] | Should -BeExactly 'SPSSiteLifecycle listing lab: it only reads.'
            $run.Text[1] | Should -BeLike 'PowerShell * on *; PnP.PowerShell *; module *.'
            $run.Text[2] | Should -BeExactly $Asked
            $run.Text[3] | Should -BeExactly 'Signing in (interactive): a window opens.'
        }

        It 'lists the sites a second time for the comparison, says so, prints no progress for it, and adds what it wrote to the counts' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Noise = $true; $script:StubData.Warn = $true }

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            ($run.Text -join "`n") | Should -BeLike '*Listing the sites a second time with Get-PnPTenantSite (the sign-in is asked again).*'
            @($run.Text | Where-Object { $_ -like '  page 1:*' }) | Should -HaveCount 1
            $run.Report.Summary.WarningCount | Should -Be 3
            $run.Report.Summary.OutputCount | Should -Be 12
            $run.Report.Compare.PagedSites | Should -Be 5
            $run.Report.Compare.CmdletSites | Should -Be 5
        }

        It 'counts the warnings even when the session does not show them' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Warn = $true }
            $before = $global:WarningPreference
            try {
                $global:WarningPreference = 'SilentlyContinue'
                $run = Invoke-Lab
            }
            finally {
                $global:WarningPreference = $before
            }

            $run.Report.Summary.WarningCount | Should -Be 2
        }

        It 'tells the warnings and the other lines of output apart in what it says: <Name>' -ForEach @(
            @{ Name = 'a warning only'; Noise = $false; Warn = $true; Line = '  Warnings of the listing: 2; other lines of output: 0 (not shown: their text can name the tenant, a filter or a site)'; Detail = 'The listing gave 2 warning(s), not shown: their text can name the tenant, a filter or a site. Run the Scan to read them.' }
            @{ Name = 'other lines only'; Noise = $true; Warn = $false; Line = '  Warnings of the listing: 0; other lines of output: 8 (not shown: their text can name the tenant, a filter or a site)'; Detail = 'The listing gave 8 other line(s) of output, not shown: their text can name the tenant, a filter or a site. Run the Scan to read them.' }
            @{ Name = 'both'; Noise = $true; Warn = $true; Line = '  Warnings of the listing: 2; other lines of output: 8 (not shown: their text can name the tenant, a filter or a site)'; Detail = 'The listing gave 2 warning(s) and 8 other line(s) of output, not shown: their text can name the tenant, a filter or a site. Run the Scan to read them.' }
        ) {
            $null = Set-LabPages
            & $script:Module { param($n, $w) $script:StubData.Noise = $n; $script:StubData.Warn = $w } $Noise $Warn

            $run = Invoke-Lab

            $run.Text | Should -Contain $Line
            (Get-LabCheck -Report $run.Report -Name 'listing-warnings').Detail | Should -BeExactly $Detail
        }

        It 'says nothing of warnings and output when the listing gave none' {
            $null = Set-LabPages

            $run = Invoke-Lab

            ($run.Text -join "`n") | Should -Not -BeLike '*Warnings of the listing*'
            (Get-LabCheck -Report $run.Report -Name 'listing-warnings').Detail | Should -BeExactly 'The listing gave no warning and wrote nothing but its sites.'
        }

        It 'writes the report in an output folder that did not exist, whatever the source' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'not-yet/there'

            $run = Invoke-Lab -Parameter @{ Source = 'Cmdlet'; OutputFolder = $folder }

            Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'listing-lab-report.json') | Should -BeTrue
            $run.Report.Completed | Should -BeTrue
        }

        It 'tells each error of the table in its own words, and keeps the text of the error in a file only when the words do not say it all: <Name>' -ForEach @(
            @{ Name = 'PnP.PowerShell is not installed'; Text = 'PnP.PowerShell is not installed. Install version 3 or later with: Install-Module -Name PnP.PowerShell -Scope CurrentUser (it needs PowerShell 7.4 or later).'; Words = 'The lab stopped: PnP.PowerShell is not installed (version 3 or later is needed). Error types: *'; File = $false }
            @{ Name = 'PnP.PowerShell is too old'; Text = 'PnP.PowerShell 2.12.0 is too old: the tool needs version 3.0.0 or later. Update it with: Update-Module -Name PnP.PowerShell'; Words = 'The lab stopped: PnP.PowerShell 2.12.0 is too old (version 3 or later is needed). Error types: *'; File = $false }
            @{ Name = 'PnP.PowerShell is loaded and too old'; Text = 'PnP.PowerShell 2.12.0 is loaded, and the tool needs version 3.0.0 or later. Start a new PowerShell session after updating it with: Update-Module -Name PnP.PowerShell'; Words = 'The lab stopped: PnP.PowerShell 2.12.0 is loaded and is too old: start a new session after updating it. Error types: *'; File = $false }
            @{ Name = 'the sign-in failed'; Text = 'The sign-in to the admin site of the tenant failed: Synthetic text that names SyntheticPrivateBoard.'; Words = 'The lab stopped: The sign-in to the admin site of the tenant failed. Error types: *'; File = $true }
            @{ Name = 'the sign-in gave no connection'; Text = 'The sign-in to the admin site of the tenant gave no connection. The calls that follow would use another one.'; Words = 'The lab stopped: The sign-in to the admin site of the tenant gave no connection. Error types: *'; File = $false }
            @{ Name = 'the listing did not end'; Text = 'The listing did not end after 500000 pages, which is the most that it may have: it is asked again and again without reaching its end.'; Words = 'The lab stopped: The listing did not end after 500000 pages. Error types: *'; File = $false }
            @{ Name = 'the paged call cannot be used'; Text = 'The paged listing was asked for and cannot be used: The cmdlet was asked for (Source Cmdlet).'; Words = 'The lab stopped: The paged call was asked for and cannot be used: The cmdlet was asked for (Source Cmdlet). Error types: *'; File = $false }
            @{ Name = 'a site that came twice'; Text = "The site '11111111-2222-3333-4444-555555555555' came twice in the listing with another value for a field that guards it (Template). Start again."; Words = "The lab stopped: The site '11111111-2222-3333-4444-555555555555' came twice in the listing with another value for a field that guards it, so the tenant changed while it was read: start the listing again from the first page (Restart). Error types: *"; File = $false }
            @{ Name = 'a text that is not in the table'; Text = 'Synthetic failure that names SyntheticPrivateBoard.'; Words = 'The lab stopped: an error whose text is not shown. Error types: *'; File = $true }
        ) {
            $null = Set-LabPages
            & $script:Module { param($t) $script:StubData.OpenError = $t } $Text
            $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))

            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike $Words
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
            ($thrown.Exception.Message -like '*listing-lab-error.txt in the output folder*') | Should -Be $File
            Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'listing-lab-error.txt') | Should -Be $File
        }

        It 'says in its own words that the tenant is refused, and that nothing was written' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'refused'

            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ TenantName = 'microsoft'; OutputFolder = $folder }
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike 'The lab stopped: The tenant is refused*'
            $thrown.Exception.Message | Should -Not -BeLike "*'microsoft'*"
            $thrown.Exception.Message | Should -Not -BeLike '*listing-lab-error.txt*'
            Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'listing-lab-error.txt') | Should -BeFalse
        }

        It 'says which site came twice with another value, by its ID only' {
            $null = Set-LabPages
            $first = New-LabRecord -Index 1
            $again = New-LabRecord -Index 1 -Override @{ IsHubSite = $true; Title = 'Secret title of the second reading' }
            & $script:Module { param($a, $b) $script:StubData.Pages = @(, @($a, $b)) } $first $again

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike "*The site '$($first.SiteId)' came twice in the listing with another value for a field that guards it*"
            $thrown.Exception.Message | Should -Not -BeLike '*Secret title*'
            $thrown.Exception.Message | Should -Not -BeLike '*contoso*'
        }

        It 'names the property of a site that an error is about, and not what it holds, in the error of a page that cannot be read' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.PageError = "Site 'https://contoso.sharepoint.com/sites/private-title': the property 'StorageUsage' is not a number of megabytes ('a text that names SyntheticPrivateBoard')." }

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike '*Page 1 of the listing could not be read after 3 attempts*'
            $thrown.Exception.Message | Should -BeLike '*Properties named: StorageUsage.*'
            $thrown.Exception.Message | Should -Not -BeLike '*megabytes*'
            $thrown.Exception.Message | Should -Not -BeLike '*private-title*'
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
            $thrown.Exception.Message | Should -Not -BeLike '*contoso*'
        }

        It 'says that the text of an error is not shown when nothing in it is known' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.OpenError = 'Something that names SyntheticPrivateBoard went wrong.' }

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike 'The lab stopped: an error whose text is not shown*RuntimeException*'
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
        }

        It 'shows no verbose line of the listing, which says why a page was read again and can name the tenant' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.PageError = 'Synthetic failure at https://contoso-admin.sharepoint.com'; $script:StubData.PageErrorLeft = 1 }
            $before = $global:VerbosePreference
            $global:VerbosePreference = 'Continue'
            try {
                $run = Invoke-Lab -Parameter @{ Verbose = $true }
            }
            finally {
                $global:VerbosePreference = $before
            }

            $run.Report.Summary.Retries | Should -Be 1
            $run.Verbose | Should -HaveCount 0
            Get-LabEverything -Run $run | Should -Not -BeLike '*contoso*'
        }

        It 'recognizes the reason why the cmdlet was used as it is written, whatever the culture of the machine: <Culture>' -ForEach @(
            @{ Culture = 'en-US' }
            @{ Culture = 'tr-TR' }
            @{ Culture = 'fr-FR' }
        ) {
            $null = Set-LabPages
            $reason = "The property 'IncludeDetail' of the filter of the admin API is not a writable Boolean in this PnP.PowerShell."
            & $script:Module { param($t) $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = $t } $reason
            $before = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                $run = Invoke-Lab -Parameter @{ TenantName = 'fabrikam' }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $before
            }

            $run.Report.Summary.FallbackReason | Should -BeExactly $reason
        }

        It 'does not print where the report is, because the folder can be named after the tenant, a site or a person' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'contoso-SyntheticPrivateBoard'

            $run = Invoke-Lab -Parameter @{ OutputFolder = $folder }

            $text = $run.Text -join "`n"
            $text | Should -BeLike '*Report saved: listing-lab-report.json, in the output folder*'
            $text | Should -Not -BeLike '*SyntheticPrivateBoard*'
            $text | Should -Not -BeLike '*contoso*'
            Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'listing-lab-report.json') | Should -BeTrue
        }

        It 'shows a lock state, a template and an archive status as SharePoint writes them, whatever the name of the tenant: <Tenant>' -ForEach @(
            @{ Tenant = 'group' }
            @{ Tenant = 'readonly' }
            @{ Tenant = 'notarchived' }
            @{ Tenant = 'unlock' }
            @{ Tenant = 'sts' }
        ) {
            $null = Set-LabPages

            $run = Invoke-Lab -Parameter @{ TenantName = $Tenant }

            $run.Report.Statistics.LockStates.ReadOnly | Should -Be 4
            $run.Report.Statistics.LockStates.Unlock | Should -Be 1
            $run.Report.Statistics.Templates.'GROUP#0' | Should -Be 3
            $run.Report.Statistics.Templates.'STS#3' | Should -Be 1
            $run.Report.Statistics.ArchiveStatus.NotArchived | Should -Be 5
            ($run.Text -join "`n") | Should -BeLike '*Lock states: ReadOnly 4, Unlock 1*'
            ($run.Text -join "`n") | Should -BeLike '*Templates (top 10): GROUP#0 3, SITEPAGEPUBLISHING#0 1, STS#3 1*'
        }

        It 'shows only the words that SharePoint writes for a lock state and an archive status, and a template only in its form' {
            $null = Set-LabPages
            & $script:Module {
                $script:StubData.Pages[0][0].LockState = 'readonly'
                $script:StubData.Pages[0][1].LockState = 'contoso'
                $script:StubData.Pages[0][2].LockState = 'NoAdditions'
                $script:StubData.Pages[1][0].LockState = 'NoAccess'
                $script:StubData.Pages[0][0].ArchiveStatus = 'FullyArchived'
                $script:StubData.Pages[0][1].ArchiveStatus = 'contoso'
                $script:StubData.Pages[0][2].ArchiveStatus = 'RecentlyArchived'
                $script:StubData.Pages[0][0].Template = 'contoso'
                $script:StubData.Pages[0][1].Template = 'RedirectSite#0'
                $script:StubData.Pages[0][2].Template = 'EHS#-1'
            }

            $run = Invoke-Lab

            $states = $run.Report.Statistics.LockStates
            $states.ReadOnly | Should -Be 2
            $states.'(not a name)' | Should -Be 1
            $states.NoAdditions | Should -Be 1
            $states.NoAccess | Should -Be 1
            $archive = $run.Report.Statistics.ArchiveStatus
            $archive.FullyArchived | Should -Be 1
            $archive.RecentlyArchived | Should -Be 1
            $archive.'(not a name)' | Should -Be 1
            $archive.NotArchived | Should -Be 2
            $templates = $run.Report.Statistics.Templates
            $templates.'(not a name)' | Should -Be 1
            $templates.'RedirectSite#0' | Should -Be 1
            $templates.'EHS#-1' | Should -Be 1
            Get-LabEverything -Run $run | Should -Not -BeLike '*contoso*'
        }

        It 'names only the properties of a site that the tool reads, and not a word that an error puts after the word property' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.PageError = "The property 'contoso' is not available; property 'SyntheticPrivateBoard' is not loaded. The property 'storageusage' is below zero, and Property 'LastContentModifiedDate' too." }

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike '*Properties named: StorageUsage, LastContentModifiedDate.*'
            $thrown.Exception.Message | Should -Not -BeLike '*contoso*'
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
        }

        It 'names the type of an exception when it is the framework or the library, and not when it is any other: <Name>' -ForEach @(
            @{ Name = 'a type of the framework'; Make = { [System.IO.FileNotFoundException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by FileNotFoundException.*' }
            @{ Name = 'a type of PowerShell'; Make = { [System.Management.Automation.ItemNotFoundException]::new('x') }; Expected = '*caused by ItemNotFoundException.*' }
            @{ Name = 'a type that is named like a site, in a namespace of Microsoft'; Make = { [Microsoft.OfflineLab.SyntheticPrivateBoardException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
            @{ Name = 'a type that is named like a site, in a namespace of System'; Make = { [System.OfflineLab.SyntheticPrivateBoardException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
            @{ Name = 'a type that is named like a site, in a namespace of PnP'; Make = { [PnP.OfflineLab.SyntheticPrivateBoardException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
            @{ Name = 'a type that is named like a site, in a namespace of Newtonsoft'; Make = { [Newtonsoft.OfflineLab.SyntheticPrivateBoardException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
            @{ Name = 'a type that is named like a site, in no namespace'; Make = { [SyntheticPrivateBoardException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
            @{ Name = 'a type that derives from a known type, which is not the known type'; Make = { [SyntheticPrivateBoardDerivedException]::new('x') }; Expected = '*Error types: InvalidOperationException, caused by (another type).*' }
        ) {
            $null = Set-LabPages
            & $script:Module { param($e) $script:StubData.PageException = $e } (& $Make)

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike $Expected
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
        }

        It 'stops walking the exceptions of an error whose inner exception is itself, and says that the chain was cut' {
            $null = Set-LabPages
            $folder = Join-Path -Path $TestDrive -ChildPath 'cyclic'
            & $script:Module { param($e) $script:StubData.PageException = $e } ([SyntheticCyclicException]::new('Synthetic failure that comes back on itself.'))

            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ OutputFolder = $folder }
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike '*Error types: InvalidOperationException, caused by (another type), caused by more (the chain is cut).*'
            $saved = Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'listing-lab-error.txt') -Raw
            $saved | Should -BeLike '*Synthetic failure that comes back on itself.*'
            $saved | Should -BeLike '*the chain goes on or comes back on itself*'
        }

        It 'keeps the types of a very long chain of exceptions to a few, and the message to a length that a person can read' {
            $null = Set-LabPages
            $deep = [System.Exception]::new('level 0')
            for ($i = 1; $i -le 60; $i++) {
                $deep = [System.InvalidOperationException]::new("level $i", $deep)
            }

            & $script:Module { param($e) $script:StubData.PageException = $e } $deep

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike '*caused by more (the chain is cut).*'
            @([regex]::Matches($thrown.Exception.Message, 'InvalidOperationException')).Count | Should -BeLessOrEqual 10
            $thrown.Exception.Message.Length | Should -BeLessThan 800
        }

        It 'says nothing of the text of an error that has no exception, or an exception with no text' {
            $null = Set-LabPages
            & $script:Module { param($e) $script:StubData.PageException = $e } ([System.InvalidOperationException]::new(''))

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike 'The lab stopped: Page 1 of the listing could not be read after 3 attempts.*'
        }

        It 'shows a template only when it is one that SharePoint has, in the spelling of SharePoint, and never a word of the tenant: <Template>' -ForEach @(
            @{ Template = 'contoso#0'; Expected = '(not a name)' }
            @{ Template = 'contoso'; Expected = '(not a name)' }
            @{ Template = 'STS#3'; Expected = 'STS#3' }
            @{ Template = 'sts#-1'; Expected = 'STS#-1' }
            @{ Template = 'GROUP#0'; Expected = 'GROUP#0' }
            @{ Template = 'group#0'; Expected = 'GROUP#0' }
            @{ Template = 'TEAMCHANNEL#1'; Expected = 'TEAMCHANNEL#1' }
            @{ Template = 'redirectsite#0'; Expected = 'RedirectSite#0' }
            @{ Template = 'SITEPAGEPUBLISHING#0'; Expected = 'SITEPAGEPUBLISHING#0' }
            @{ Template = 'STS#99999'; Expected = '(not a name)' }
            @{ Template = 'STS#x'; Expected = '(not a name)' }
            @{ Template = 'STS# 3'; Expected = '(not a name)' }
            @{ Template = "STS#3`n"; Expected = '(not a name)' }
        ) {
            $null = Set-LabPages
            & $script:Module { param($t) $script:StubData.Pages[0][0].Template = $t } $Template

            $run = Invoke-Lab

            $run.Report.Statistics.Templates.$Expected | Should -BeGreaterOrEqual 1
            Get-LabEverything -Run $run | Should -Not -BeLike '*contoso*'
        }

        It 'shows nothing that the listing writes outside its records, and counts it, while it keeps its own progress lines' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.Noise = $true; $script:StubData.Warn = $true }

            $run = Invoke-Lab

            Get-LabEverything -Run $run | Should -Not -BeLike '*SyntheticPrivateBoard*'
            Get-LabEverything -Run $run | Should -Not -BeLike '*syntheticowner*'
            ($run.Text -join "`n") | Should -BeLike '*page 1: 3 sites so far*'
            ($run.Text -join "`n") | Should -BeLike '*page 2: 5 sites so far*'
            $run.Report.Summary.WarningCount | Should -Be 2
            $run.Report.Summary.OutputCount | Should -Be 8
            (Get-LabCheck -Report $run.Report -Name 'listing-warnings').Detail | Should -BeLike '*2 warning(s) and 8 other line(s) of output, not shown*'
            (Get-LabCheck -Report $run.Report -Name 'listing-warnings').Status | Should -BeExactly 'INFO'
            $run.Warnings | Should -HaveCount 0
            $run.Debug | Should -HaveCount 0
            $run.Errors | Should -HaveCount 0
        }

        It 'counts no line of output when the listing writes none' {
            $null = Set-LabPages

            $run = Invoke-Lab

            $run.Report.Summary.OutputCount | Should -Be 0
            (Get-LabCheck -Report $run.Report -Name 'listing-warnings').Status | Should -BeExactly 'PASS'
        }

        It 'shows the version of PowerShell by its numbers, and the system by a word and a number, whatever the label that they carry' {
            $null = Set-LabPages
            $saved = $PSVersionTable.PSVersion
            try {
                $PSVersionTable.PSVersion = [System.Management.Automation.SemanticVersion]::new(7, 6, 7, 'SyntheticPrivateBoard')
                $run = Invoke-Lab
            }
            finally {
                $PSVersionTable.PSVersion = $saved
            }

            Get-LabEverything -Run $run | Should -Not -BeLike '*SyntheticPrivateBoard*'
            $run.Report.Environment.PowerShell | Should -BeExactly '7.6.7 (pre-release)'
            $run.Report.Environment.OS | Should -Match '^(Windows|macOS|Linux|FreeBSD|another system) [0-9]+(\.[0-9]+){1,3}$'
            $run.Report.Environment.Module | Should -Match '^[0-9]+(\.[0-9]+){1,3}$'
            $run.Report.Environment.PnPPowerShell | Should -Match '^([0-9]+(\.[0-9]+){1,3}|not found)$'
            ($run.Text -join "`n") | Should -BeLike "*PowerShell 7.6.7 (pre-release) on $($run.Report.Environment.OS);*"
        }

        It 'shows a version of PowerShell that has no label as its three numbers' {
            $null = Set-LabPages
            $saved = $PSVersionTable.PSVersion
            try {
                $PSVersionTable.PSVersion = [System.Management.Automation.SemanticVersion]::new(7, 4, 22)
                $run = Invoke-Lab
            }
            finally {
                $PSVersionTable.PSVersion = $saved
            }

            $run.Report.Environment.PowerShell | Should -BeExactly '7.4.22'
        }

        It 'says in its own words what is wrong with a parameter, and never gives the value back: <Name>' -ForEach @(
            @{ Name = 'a source that is not one'; Parameter = @{ Source = 'SyntheticPrivateBoard' }; Rule = 'Source must be Auto, Csom or Cmdlet' }
            @{ Name = 'a lock state that is not one'; Parameter = @{ LockState = @('ReadOnly', 'SyntheticPrivateBoard') }; Rule = 'LockState must be ReadOnly, Unlock, or both' }
            @{ Name = 'no lock state'; Parameter = @{ LockState = @() }; Rule = 'LockState must be ReadOnly, Unlock, or both' }
            @{ Name = 'a client ID that is an account'; Parameter = @{ ClientId = 'syntheticowner@fabrikam.example' }; Rule = 'ClientId must be the application (client) ID of the app registration: a GUID' }
            @{ Name = 'a number of pages that is a word'; Parameter = @{ StopAfterPages = 'SyntheticPrivateBoard' }; Rule = 'StopAfterPages must be a whole number from 0 to 100000' }
            @{ Name = 'a number of pages that is too large'; Parameter = @{ StopAfterPages = 100001 }; Rule = 'StopAfterPages must be a whole number from 0 to 100000' }
            @{ Name = 'a number of pages below zero'; Parameter = @{ StopAfterPages = -1 }; Rule = 'StopAfterPages must be a whole number from 0 to 100000' }
            @{ Name = 'a number of sites that is a word'; Parameter = @{ ExpectedSites = 'syntheticowner' }; Rule = 'ExpectedSites must be a whole number from 0 to 100000000' }
            @{ Name = 'a number of sites that is too large'; Parameter = @{ ExpectedSites = 100000001 }; Rule = 'ExpectedSites must be a whole number from 0 to 100000000' }
        ) {
            $null = Set-LabPages

            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter $Parameter
            }
            catch {
                $thrown = $_
            }

            $thrown.Exception.Message | Should -BeLike "The lab stopped: $Rule. Error types: ArgumentException.*"
            $thrown.Exception.Message | Should -Not -BeLike '*SyntheticPrivateBoard*'
            $thrown.Exception.Message | Should -Not -BeLike '*syntheticowner*'
            $thrown.Exception.Message | Should -Not -BeLike '*fabrikam*'
            $thrown.Exception.Message | Should -Not -BeLike '*listing-lab-error*'
            Get-StubLog | Should -HaveCount 0
        }

        It 'accepts the parameters in the forms that a person writes them, and shows them in the spelling of the lab: <Name>' -ForEach @(
            @{ Name = 'a source in lowercase'; Parameter = @{ Source = 'csom' }; Check = { $r.Report.Asked.Source | Should -BeExactly 'Csom' } }
            @{ Name = 'a source in capitals'; Parameter = @{ Source = 'CMDLET' }; Check = { $r.Report.Asked.Source | Should -BeExactly 'Cmdlet' } }
            @{ Name = 'a lock state in lowercase, given twice'; Parameter = @{ LockState = @('readonly', 'READONLY') }; Check = { @($r.Report.Asked.LockState) | Should -Be @('ReadOnly') } }
            @{ Name = 'a client ID with no hyphens'; Parameter = @{ ClientId = '11111111222233334444555555555555' }; Check = { $r.Report.Completed | Should -BeTrue } }
            @{ Name = 'a client ID with braces'; Parameter = @{ ClientId = '{11111111-2222-3333-4444-555555555555}' }; Check = { $r.Report.Completed | Should -BeTrue } }
            @{ Name = 'a number of pages as a text'; Parameter = @{ StopAfterPages = '1' }; Check = { $r.Report.Asked.StopAfterPages | Should -Be 1 } }
            @{ Name = 'a number of sites'; Parameter = @{ ExpectedSites = 5 }; Check = { $r.Report.Asked.ExpectedSites | Should -Be 5 } }
            @{ Name = 'the largest numbers'; Parameter = @{ StopAfterPages = 100000; ExpectedSites = 100000000 }; Check = { $r.Report.Asked.StopAfterPages | Should -Be 100000 } }
        ) {
            $null = Set-LabPages

            $r = Invoke-Lab -Parameter $Parameter

            & $Check
            Get-LabEverything -Run $r | Should -Not -BeLike '*11111111-2222-3333-4444-555555555555*'
        }

        It 'counts a value that is not a name apart from a value that is missing, for the template, the lock state and the archive status' {
            $null = Set-LabPages
            & $script:Module {
                $script:StubData.Pages[0][0].ArchiveStatus = ''
                $script:StubData.Pages[0][1].LockState = 'Locked for good reasons'
                $script:StubData.Pages[0][2].Template = 'T' * 80
            }

            $run = Invoke-Lab

            $run.Report.Statistics.ArchiveStatus.'(none)' | Should -Be 1
            $run.Report.Statistics.LockStates.'(not a name)' | Should -Be 1
            $run.Report.Statistics.Templates.'(not a name)' | Should -Be 1
            $run.Report.Summary.PersonalSites | Should -BeExactly 'Excluded'
        }

        It 'shows what differs between two listings in a shape that cannot hold a name: <Field>, <Paged> and <Cmdlet>' -ForEach @(
            @{ Field = 'Template'; Paged = 'GROUP#0'; Cmdlet = 'STS#3'; ShownPaged = 'GROUP#0'; ShownCmdlet = 'STS#3' }
            @{ Field = 'LockState'; Paged = 'ReadOnly'; Cmdlet = 'Locked by hand'; ShownPaged = 'ReadOnly'; ShownCmdlet = '(not a name)' }
            @{ Field = 'ArchiveStatus'; Paged = 'NotArchived'; Cmdlet = ''; ShownPaged = 'NotArchived'; ShownCmdlet = '(none)' }
            @{ Field = 'IsHubSite'; Paged = $true; Cmdlet = 'contoso'; ShownPaged = 'True'; ShownCmdlet = '(not a boolean)' }
            @{ Field = 'IsTeamsConnected'; Paged = $false; Cmdlet = $true; ShownPaged = 'False'; ShownCmdlet = 'True' }
            @{ Field = 'GroupId'; Paged = '11111111-1111-4111-8111-111111111111'; Cmdlet = ''; ShownPaged = '11111111-1111-4111-8111-111111111111'; ShownCmdlet = '(none)' }
            @{ Field = 'GroupId'; Paged = '00000000-0000-0000-0000-000000000000'; Cmdlet = 'a group of contoso'; ShownPaged = '(none)'; ShownCmdlet = '(not an ID)' }
            @{ Field = 'StorageUsedMB'; Paged = 5; Cmdlet = $null; ShownPaged = '5'; ShownCmdlet = '(none)' }
            @{ Field = 'LastContentModified'; Paged = [System.DateTime]::new(2026, 10, 1, 8, 30, 0, [System.DateTimeKind]::Utc); Cmdlet = '2026-10-01T09:30:00Z'; ShownPaged = '2026-10-01T08:30:00Z'; ShownCmdlet = '(not a date)' }
            @{ Field = 'LastContentModified'; Paged = [System.DateTime]::new(2026, 10, 1, 8, 30, 0, [System.DateTimeKind]::Utc); Cmdlet = $null; ShownPaged = '2026-10-01T08:30:00Z'; ShownCmdlet = '(none)' }
            @{ Field = 'Title'; Paged = 'Secret title 1'; Cmdlet = 'Another secret title'; ShownPaged = '(not shown)'; ShownCmdlet = '(not shown)' }
            @{ Field = 'Url'; Paged = 'https://contoso.sharepoint.com/sites/site1'; Cmdlet = 'https://contoso.sharepoint.com/sites/other'; ShownPaged = '(not shown)'; ShownCmdlet = '(not shown)' }
        ) {
            $records = Set-LabPages
            $copies = @($records | ForEach-Object { $_.PSObject.Copy() })
            $records[0].$Field = $Paged
            $copies[0].$Field = $Cmdlet
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $copies

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $example = @($run.Report.Compare.Fields.$Field.Examples)[0]
            $example.SiteId | Should -BeExactly $records[0].SiteId
            $example.Paged | Should -BeExactly $ShownPaged
            $example.Cmdlet | Should -BeExactly $ShownCmdlet
            Get-LabEverything -Run $run | Should -Not -BeLike '*contoso*'
            Get-LabEverything -Run $run | Should -Not -BeLike '*secret title*'
        }

        It 'shows a reason why the paged call cannot be used as it is when the tool gives it, and never another: <Name>' -ForEach @(
            @{ Name = 'the types are not there'; Reason = 'The types of the SharePoint admin API (Tenant, SPOSitePropertiesEnumerableFilter, PersonalSiteFilter) are not in this PnP.PowerShell.'; Known = $true }
            @{ Name = 'a property of the filter is missing'; Reason = "The filter of the admin API has no property 'IncludePersonalSite' in this PnP.PowerShell."; Known = $true }
            @{ Name = 'a property of the filter is not writable'; Reason = "The property 'Filter' of the filter of the admin API is not a writable String in this PnP.PowerShell."; Known = $true }
            @{ Name = 'a property of the filter has another type'; Reason = "The property 'IncludePersonalSite' of the filter of the admin API is not a writable PersonalSiteFilter in this PnP.PowerShell."; Known = $true }
            @{ Name = 'the enumeration has no value'; Reason = "The enumeration of the OneDrive sites has no value 'Exclude' in this PnP.PowerShell."; Known = $true }
            @{ Name = 'the method is missing'; Reason = 'The tenant of the admin API has no method GetSitePropertiesFromSharePointByFilters that takes the filter in this PnP.PowerShell.'; Known = $true }
            @{ Name = 'the page has no token'; Reason = "The page that the admin API gives has no text property 'NextStartIndexFromSharePoint' in this PnP.PowerShell."; Known = $true }
            @{ Name = 'words of the tenant'; Reason = 'SyntheticPrivateBoard in tenant fabrikam.'; Known = $false }
            @{ Name = 'a known form with a property that is not one of the filter'; Reason = "The filter of the admin API has no property 'fabrikam' in this PnP.PowerShell."; Known = $false }
            @{ Name = 'a known form with a type that is not one that the check writes'; Reason = "The property 'Filter' of the filter of the admin API is not a writable SyntheticPrivateBoard in this PnP.PowerShell."; Known = $false }
            @{ Name = 'a known form with more after it'; Reason = "The enumeration of the OneDrive sites has no value 'Exclude' in this PnP.PowerShell. fabrikam"; Known = $false }
            @{ Name = 'a known form with a line break and more after it'; Reason = "The enumeration of the OneDrive sites has no value 'Exclude' in this PnP.PowerShell.`nfabrikam"; Known = $false }
            @{ Name = 'a known form in lowercase'; Reason = "the enumeration of the onedrive sites has no value 'exclude' in this pnp.powershell."; Known = $false }
            @{ Name = 'an address'; Reason = 'No paged call for https://fabrikam-admin.sharepoint.com (jc@fabrikam.com).'; Known = $false }
        ) {
            $null = Set-LabPages
            & $script:Module { param($t) $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = $t } $Reason
            $unknown = 'a reason that this script does not know'

            $fallback = Invoke-Lab -Parameter @{ TenantName = 'fabrikam' }
            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ TenantName = 'fabrikam'; Source = 'Csom' }
            }
            catch {
                $thrown = $_
            }

            $shown = if ($Known) { $Reason } else { $unknown }
            $fallback.Report.Summary.FallbackReason | Should -BeExactly $shown
            (Get-LabCheck -Report $fallback.Report -Name 'source').Detail | Should -BeLike "*$($shown.Replace('[', '`[').Replace(']', '`]'))*"
            $thrown.Exception.Message | Should -BeLike "*The paged call was asked for and cannot be used: $($shown.Replace('[', '`[').Replace(']', '`]'))*"
            foreach ($run in $fallback.Text + $fallback.Warnings + @($thrown.Exception.Message)) {
                $run | Should -Not -BeLike '*fabrikam*'
                $run | Should -Not -BeLike '*SyntheticPrivateBoard*'
            }

            (Get-LabEverything -Run $fallback) | Should -Not -BeLike '*fabrikam*'
        }

        It 'does not print a record that is not what it should be, whatever text it holds' {
            $null = Set-LabPages
            & $script:Module {
                $record = $script:StubData.Pages[0][0]
                $record.SiteId = 'https://contoso.sharepoint.com/sites/private-title'
                $record.Template = 'Template of contoso at https://contoso.sharepoint.com'
                $record.LockState = 'Locked by jc@contoso.com'
                $record.ArchiveStatus = 'Secret title 1'
            }

            $run = Invoke-Lab

            (Get-LabCheck -Report $run.Report -Name 'records-are-complete').Status | Should -BeExactly 'FAIL'
            $everything = Get-LabEverything -Run $run
            $everything | Should -Not -BeLike '*contoso*'
            $everything | Should -Not -BeLike '*sharepoint.com*'
            $everything | Should -Not -BeLike '*private-title*'
            $everything | Should -Not -BeLike '*jc@*'
            $everything | Should -Not -BeLike '*Secret title*'
            $everything | Should -BeLike '*(not an ID)*'
        }

        It 'does not print what differs in a record of the cmdlet either' {
            $records = Set-LabPages
            $cmdlet = @($records | ForEach-Object { $_.PSObject.Copy() })
            $cmdlet[0].Template = 'Template of contoso at https://contoso.sharepoint.com'
            $cmdlet[1].SiteId = 'https://contoso.sharepoint.com/sites/private-title'
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $cmdlet

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $run.Report.Compare.Fields.Template.Differing | Should -Be 1
            $everything = Get-LabEverything -Run $run
            $everything | Should -Not -BeLike '*contoso*'
            $everything | Should -Not -BeLike '*sharepoint.com*'
            $everything | Should -Not -BeLike '*private-title*'
        }
    }

    Context 'The comparison with the cmdlet' {
        It 'lists the sites a second time with the cmdlet and finds that every field is the same' {
            $null = Set-LabPages

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            Get-StubLog | Should -Contain 'page source=Cmdlet start=[]'
            $run.Report.Compare.PagedSites | Should -Be 5
            $run.Report.Compare.CmdletSites | Should -Be 5
            (Get-LabCheck -Report $run.Report -Name 'compare-sites').Status | Should -BeExactly 'PASS'
            foreach ($field in 'Url', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified') {
                (Get-LabCheck -Report $run.Report -Name "compare-$field").Status | Should -BeExactly 'PASS' -Because $field
            }
        }

        It 'keeps the checkpoint of the cmdlet apart from the one of the paged call' {
            $null = Set-LabPages

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            Test-Path -LiteralPath (Join-Path -Path $run.Folder -ChildPath 'cmdlet/listing-checkpoint/manifest.json') | Should -BeTrue
        }

        It 'fails a field that is not the same for the sites of both calls, and says the largest difference' {
            $records = Set-LabPages
            $cmdlet = @($records | ForEach-Object { $copy = $_.PSObject.Copy(); $copy.StorageUsedMB = $_.StorageUsedMB * 1024; $copy })
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $cmdlet

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $check = Get-LabCheck -Report $run.Report -Name 'compare-StorageUsedMB'
            $check.Status | Should -BeExactly 'FAIL'
            $check.Detail | Should -BeLike '*5 of 5*'
            $run.Report.Compare.Fields.StorageUsedMB.Differing | Should -Be 5
            $run.Report.Compare.Fields.StorageUsedMB.MaxDifference | Should -Be (50 * 1023)
            (Get-LabCheck -Report $run.Report -Name 'compare-Template').Status | Should -BeExactly 'PASS'
        }

        It 'accepts up to 3 differences, which are sites that changed between the two readings, and fails more: <Count> differing is <Status>' -ForEach @(
            @{ Count = 1; Status = 'PASS' }
            @{ Count = 3; Status = 'PASS' }
            @{ Count = 4; Status = 'FAIL' }
        ) {
            $records = Set-LabPages
            $cmdlet = @($records | ForEach-Object { $_.PSObject.Copy() })
            for ($i = 0; $i -lt $Count; $i++) {
                $cmdlet[$i].StorageUsedMB = 999
            }

            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $cmdlet

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            (Get-LabCheck -Report $run.Report -Name 'compare-StorageUsedMB').Status | Should -BeExactly $Status
            $run.Report.Compare.Fields.StorageUsedMB.Differing | Should -Be $Count
        }

        It 'shows the ID of a site whose address or title differs, and never the address or the title' {
            $records = Set-LabPages
            $cmdlet = @($records | ForEach-Object { $_.PSObject.Copy() })
            $cmdlet[0].Title = 'Another secret title'
            $cmdlet[0].Url = 'https://contoso.sharepoint.com/sites/another'
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $cmdlet

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $everything = ($run.Text -join "`n") + (Get-Content -LiteralPath (Join-Path -Path $run.Folder -ChildPath 'listing-lab-report.json') -Raw)
            $run.Report.Compare.Fields.Title.Differing | Should -Be 1
            $run.Report.Compare.Fields.Url.Differing | Should -Be 1
            $everything | Should -BeLike "*difference in Title for site $($records[0].SiteId)*"
            $everything | Should -Not -BeLike '*secret title*'
            $everything | Should -Not -BeLike '*contoso*'
            $everything | Should -Not -BeLike '*another*'
        }

        It 'fails when sites are in one listing and not in the other' {
            $records = Set-LabPages
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } @($records[0])

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            (Get-LabCheck -Report $run.Report -Name 'compare-sites').Status | Should -BeExactly 'FAIL'
            $run.Report.Compare.OnlyInPaged | Should -Be 4
            $run.Report.Compare.OnlyInCmdlet | Should -Be 0
        }

        It 'does not compare the cmdlet with itself, and does not compare a listing that was stopped' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'no API' }
            $fallback = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }
            & $script:Module { $script:StubData.ApiAvailable = $true; $script:StubData.ApiReason = '' }
            $stopped = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true; StopAfterPages = 1 }

            (Get-LabCheck -Report $fallback.Report -Name 'compare').Status | Should -BeExactly 'INFO'
            (Get-LabCheck -Report $stopped.Report -Name 'compare').Status | Should -BeExactly 'INFO'
            $fallback.Report.Compare | Should -BeNullOrEmpty
            $stopped.Report.Compare | Should -BeNullOrEmpty
        }

        It 'takes an empty group ID and the empty GUID for the same thing, and a group and no group for two things' {
            $records = Set-LabPages
            $cmdlet = @($records | ForEach-Object { $_.PSObject.Copy() })
            $cmdlet[3].GroupId = '00000000-0000-0000-0000-000000000000'
            $cmdlet[0].GroupId = '00000000-0000-0000-0000-000000000000'
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $cmdlet

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $run.Report.Compare.Fields.GroupId.Differing | Should -Be 1
        }

        It 'tells a size of zero from a size that is not known: <Paged> in the paged listing, <Cmdlet> in the cmdlet one' -ForEach @(
            @{ Paged = 0; Cmdlet = $null; Differing = 5 }
            @{ Paged = $null; Cmdlet = 0; Differing = 5 }
            @{ Paged = $null; Cmdlet = $null; Differing = 0 }
            @{ Paged = 0; Cmdlet = 0; Differing = 0 }
        ) {
            $records = Set-LabPages
            foreach ($record in $records) {
                $record.StorageUsedMB = $Paged
            }

            $copies = @($records | ForEach-Object { $copy = $_.PSObject.Copy(); $copy.StorageUsedMB = $Cmdlet; $copy })
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $copies

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $run.Report.Compare.Fields.StorageUsedMB.Differing | Should -Be $Differing
            $check = Get-LabCheck -Report $run.Report -Name 'compare-StorageUsedMB'
            if ($Differing -gt 0) {
                $run.Report.Compare.Fields.StorageUsedMB.OneSided | Should -Be $Differing
                $check.Status | Should -BeExactly 'FAIL'
                $check.Detail | Should -BeLike '*5 of 5 sites differ*5 known in one listing only*'
            }
            else {
                $check.Status | Should -BeExactly 'PASS'
            }
        }

        It 'tells a date from a missing date, and takes two dates of the same second for the same' -ForEach @(
            @{ Name = 'a date and none'; Paged = 0; Cmdlet = $null; Differing = 5; OneSided = 5 }
            @{ Name = 'none and none'; Paged = $null; Cmdlet = $null; Differing = 0; OneSided = 0 }
            @{ Name = 'a second apart'; Paged = 0; Cmdlet = 1; Differing = 0; OneSided = 0 }
            @{ Name = 'two seconds apart'; Paged = 0; Cmdlet = 2; Differing = 5; OneSided = 0 }
        ) {
            $records = Set-LabPages
            foreach ($record in $records) {
                $record.LastContentModified = if ($null -eq $Paged) { $null } else { $script:Now.AddSeconds($Paged) }
            }

            $copies = @($records | ForEach-Object { $copy = $_.PSObject.Copy(); $copy.LastContentModified = if ($null -eq $Cmdlet) { $null } else { $script:Now.AddSeconds($Cmdlet) }; $copy })
            & $script:Module { param($c) $script:StubData.CmdletSites = $c } $copies

            $run = Invoke-Lab -Parameter @{ CompareWithCmdlet = $true }

            $run.Report.Compare.Fields.LastContentModified.Differing | Should -Be $Differing -Because $Name
            $run.Report.Compare.Fields.LastContentModified.OneSided | Should -Be $OneSided -Because $Name
        }
    }
}
