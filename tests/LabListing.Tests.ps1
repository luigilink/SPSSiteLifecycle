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

        $report = & $script:Lab @arguments
        [PSCustomObject]@{
            Report = $report
            Text   = @($info | ForEach-Object { "$($_.MessageData)" })
            Folder = $arguments.OutputFolder
        }
    }

    function script:Get-LabCheck {
        param($Report, [string]$Name)
        @($Report.Checks | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
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
            'Get-SPSLifecycleTenantSitePage'  = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add("page source=$Source start=[$StartIndex]")
if ($Source -eq 'Cmdlet') {
    $all = if ($null -ne $script:StubData.CmdletSites) { $script:StubData.CmdletSites } else { @($script:StubData.Pages | ForEach-Object { $_ }) }
    return [PSCustomObject]@{ Items = @($all); NextStartIndex = '' }
}

$pages = $script:StubData.Pages
$index = if ($StartIndex -eq '') { 0 } else { [int]$StartIndex.Substring(1) }
$next = if ($index + 1 -lt $pages.Count) { 't' + ($index + 1) } else { '' }
[PSCustomObject]@{ Items = @($pages[$index]); NextStartIndex = $next }
'@
        } -Data @{ ApiAvailable = $true; ApiReason = ''; Pages = @(); CmdletSites = $null }
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

        It 'says that the paged call was used, and says why when the cmdlet was used instead' {
            $null = Set-LabPages
            $paged = Invoke-Lab
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'The types of the admin API are not in this PnP.PowerShell.' }
            $fallback = Invoke-Lab

            (Get-LabCheck -Report $paged.Report -Name 'source').Status | Should -BeExactly 'PASS'
            (Get-LabCheck -Report $fallback.Report -Name 'source').Status | Should -BeExactly 'INFO'
            (Get-LabCheck -Report $fallback.Report -Name 'source').Detail | Should -BeLike '*not in this PnP.PowerShell*'
            $fallback.Report.Summary.Source | Should -BeExactly 'Cmdlet'
        }

        It 'stops, and says why, when the paged call is asked for and is not there' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'No StartIndex.' }

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
    }
}
