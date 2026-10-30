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

        $output = @(& $script:Lab @arguments 3>&1 4>&1)
        $warning = [System.Management.Automation.WarningRecord]
        $verbose = [System.Management.Automation.VerboseRecord]
        [PSCustomObject]@{
            Report   = @($output | Where-Object { $_ -isnot $warning -and $_ -isnot $verbose }) | Select-Object -First 1
            Text     = @($info | ForEach-Object { "$($_.MessageData)" })
            Folder   = $arguments.OutputFolder
            Warnings = @($output | Where-Object { $_ -is $warning } | ForEach-Object { $_.Message })
            Verbose  = @($output | Where-Object { $_ -is $verbose } | ForEach-Object { $_.Message })
        }
    }

    # Everything that the lab said and wrote in a run: what it printed, the warnings and the verbose lines it let through, and the report file.
    function script:Get-LabEverything {
        param($Run)

        $file = Join-Path -Path $Run.Folder -ChildPath 'listing-lab-report.json'
        $json = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw } else { '' }
        (@($Run.Text) + @($Run.Warnings) + @($Run.Verbose) + $json) -join "`n"
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
            'Start-Sleep'                     = @'
param([double]$Seconds)
'@
            'Get-SPSLifecycleTenantSitePage'  = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add("page source=$Source start=[$StartIndex]")
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
        } -Data @{ ApiAvailable = $true; ApiReason = ''; Pages = @(); CmdletSites = $null; PageError = ''; PageErrorLeft = -1 }
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
            @{ Code = 'a code that names fabrikam@contoso.com'; Words = '*does not know*' }
        ) {
            Set-ModuleStub -Stub @{
                'Read-SPSLifecycleListingCheckpoint' = @'
[PSCustomObject]@{ Exists = $true; Usable = $false; Finished = $false; Reason = "The checkpoint was made for fabrikam ($($script:StubData.ReaderCode))."; Code = $script:StubData.ReaderCode; Manifest = $null }
'@
            } -Data @{ ApiAvailable = $true; ApiReason = ''; Pages = @(); CmdletSites = $null; PageError = ''; PageErrorLeft = -1; ReaderCode = $Code }
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

        It 'cleans an error of the tenant of its address, its account and its name, and keeps the rest of the message' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.PageError = 'Synthetic failure at https://contoso-admin.sharepoint.com/sites/private-title for jc@contoso.com (tenant contoso, client 11111111-2222-3333-4444-555555555555): 403' }

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $thrown | Should -Not -BeNullOrEmpty
            $message = $thrown.Exception.Message
            $message | Should -BeLike '*Page 1 of the listing could not be read*'
            $message | Should -BeLike '*Synthetic failure at (address) for (account) (tenant (tenant), client (client)): 403*'
            $message | Should -Not -BeLike '*contoso*'
            $message | Should -Not -BeLike '*private-title*'
            $message | Should -Not -BeLike '*11111111*'
            $thrown.Exception.InnerException | Should -BeNullOrEmpty
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

        It 'makes an error one line of a length that a report can hold, and finds the name in capitals and the ID without hyphens' {
            $null = Set-LabPages
            $emoji = [System.Char]::ConvertFromUtf32(0x1F600)
            $before = 'Page 1 of the listing could not be read after 3 attempts: first line second line (tenant) (client) '
            $text = "first line`nsecond`tline CONTOSO 11111111222233334444555555555555 " + ('x' * (599 - $before.Length)) + $emoji + ('y' * 200)
            & $script:Module { param($t) $script:StubData.PageError = $t } $text

            $thrown = $null
            try {
                $null = Invoke-Lab
            }
            catch {
                $thrown = $_
            }

            $message = $thrown.Exception.Message
            $message | Should -BeLike 'The lab stopped (InvalidOperationException): Page 1 of the listing could not be read after 3 attempts: first line second line (tenant) (client) xxx*'
            $message | Should -Not -Match '[\r\n\t]'
            $message | Should -BeLike '*x...'
            $message | Should -Not -BeLike "*$emoji*"
            $message | Should -Not -Match '[\uD800-\uDBFF](?![\uDC00-\uDFFF])'
            $message.Length | Should -Be ('The lab stopped (InvalidOperationException): '.Length + 599 + 3)
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

        It 'cleans the reason why the cmdlet was used, and the reason why the paged call is refused' {
            $null = Set-LabPages
            & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'No paged call for https://contoso-admin.sharepoint.com (contoso.onmicrosoft.com, jc@contoso.com).' }

            $fallback = Invoke-Lab
            $thrown = $null
            try {
                $null = Invoke-Lab -Parameter @{ Source = 'Csom' }
            }
            catch {
                $thrown = $_
            }

            (Get-LabEverything -Run $fallback) | Should -Not -BeLike '*contoso*'
            (Get-LabEverything -Run $fallback) | Should -Not -BeLike '*sharepoint.com*'
            (Get-LabCheck -Report $fallback.Report -Name 'source').Detail | Should -BeLike '*No paged call for (address) ((address), (account)).*'
            $fallback.Report.Summary.FallbackReason | Should -BeLike 'No paged call for (address)*'
            $thrown.Exception.Message | Should -BeLike '*No paged call for (address) ((address), (account)).*'
            $thrown.Exception.Message | Should -Not -BeLike '*contoso*'
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
