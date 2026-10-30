BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'
    $script:GroupB = '22222222-2222-2222-2222-222222222222'

    function script:Get-TestDate {
        param([string]$Text)
        [System.DateTime]::SpecifyKind([System.DateTime]::ParseExact($Text, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Utc)
    }

    # An import of an activity report, as Import-SPSLifecycleActivityReport gives it.
    function script:New-TestReport {
        param(
            [ValidateSet('SharePoint', 'Teams', 'Groups')][string]$Kind,
            [hashtable]$ById = @{},
            [hashtable]$ByUrl = @{},
            $ByUrlId = @{}
        )

        $report = [ordered]@{ Kind = $Kind; Name = "$Kind.csv"; RowCount = $ById.Count; DeletedRowCount = 0; ById = $ById; ByUrl = $ByUrl }
        if ($null -ne $ByUrlId) {
            $report.ByUrlId = $ByUrlId
        }

        [PSCustomObject]$report
    }

    function script:Find-TestActivity {
        param($SharePoint = $null, $Teams = $null, $Groups = $null, $SiteId = '', $Url = '', $GroupId = '')
        & $script:Module { param($p) Find-SPSLifecycleActivity @p } @{ SharePoint = $SharePoint; Teams = $Teams; Groups = $Groups; SiteId = $SiteId; Url = $Url; GroupId = $GroupId }
    }
}

Describe 'Find-SPSLifecycleActivity' {
    Context 'The SharePoint report' {
        It 'finds a site by its ID, whatever its address' {
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2026-09-15') }

            $activity = Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/renamed'

            $activity.HasRow | Should -BeTrue
            $activity.LastActivity | Should -Be (Get-TestDate '2026-09-15')
            $activity.LastActivitySource | Should -BeExactly 'SharePoint'
            $activity.SharePoint | Should -Be (Get-TestDate '2026-09-15')
        }

        It 'normalizes the ID that it is given: braces and capitals' {
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2026-09-15') }

            (Find-TestActivity -SharePoint $report -SiteId '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}').HasRow | Should -BeTrue
        }

        It 'knows a site that has a row and no date: the site is in the report, and had no activity' {
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null }

            $activity = Find-TestActivity -SharePoint $report -SiteId $script:SiteA

            $activity.HasRow | Should -BeTrue
            $activity.LastActivity | Should -BeNullOrEmpty
            $activity.LastActivitySource | Should -BeExactly ''
            $activity.SharePoint | Should -BeNullOrEmpty
        }

        It 'finds a site by its address when the row has no usable site ID' {
            $report = New-TestReport -Kind SharePoint -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2026-09-15') } -ByUrlId @{ 'https://contoso.sharepoint.com/sites/a' = '' }

            $activity = Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a'

            $activity.HasRow | Should -BeTrue
            $activity.LastActivity | Should -Be (Get-TestDate '2026-09-15')
        }

        It 'finds the address whatever its spelling: case, trailing slash, port, percent-encoding' -ForEach @(
            @{ Url = 'https://CONTOSO.sharepoint.com/Sites/A/' }
            @{ Url = 'https://contoso.sharepoint.com:443/sites/a' }
            @{ Url = 'https://contoso.sharepoint.com/sites/a?x=1' }
            @{ Url = 'https://contoso.sharepoint.com/sites/%61' }
        ) {
            $report = New-TestReport -Kind SharePoint -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2026-09-15') } -ByUrlId @{ 'https://contoso.sharepoint.com/sites/a' = '' }

            (Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url $Url).HasRow | Should -BeTrue
        }

        It 'does not give a site the row of another site that had its address, nor of several sites: <Name>' -ForEach @(
            @{ Name = 'a row of another site ID'; RowId = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c' }
            @{ Name = 'a row that rows with different IDs share'; RowId = '*' }
        ) {
            $report = New-TestReport -Kind SharePoint -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2020-01-01') } -ByUrlId @{ 'https://contoso.sharepoint.com/sites/a' = $RowId }

            $activity = Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a'

            $activity.HasRow | Should -BeFalse
            $activity.LastActivity | Should -BeNullOrEmpty
        }

        It 'prefers the row of the site ID to a row of the same address that has another ID' {
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2025-01-01') } -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2026-09-15') } -ByUrlId @{ 'https://contoso.sharepoint.com/sites/a' = '*' }

            (Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a').LastActivity | Should -Be (Get-TestDate '2025-01-01')
        }

        It 'finds nothing for a site whose ID is unknown, even when its address is in the report: <Id>' -ForEach @(
            @{ Id = '' }
            @{ Id = $null }
            @{ Id = '00000000-0000-0000-0000-000000000000' }
            @{ Id = 'not a guid' }
        ) {
            $report = New-TestReport -Kind SharePoint -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2026-09-15') } -ByUrlId @{ 'https://contoso.sharepoint.com/sites/a' = '' }

            (Find-TestActivity -SharePoint $report -SiteId $Id -Url 'https://contoso.sharepoint.com/sites/a').HasRow | Should -BeFalse
        }

        It 'does not match an address when the report cannot say whose row it is' {
            $report = New-TestReport -Kind SharePoint -ByUrl @{ 'https://contoso.sharepoint.com/sites/a' = (Get-TestDate '2026-09-15') } -ByUrlId $null

            (Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a').HasRow | Should -BeFalse
        }

        It 'finds nothing for a site that is not in the report' {
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteB = (Get-TestDate '2026-09-15') }

            $activity = Find-TestActivity -SharePoint $report -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a'

            $activity.HasRow | Should -BeFalse
            $activity.SharePoint | Should -BeNullOrEmpty
        }
    }

    Context 'The Teams and the groups reports' {
        It 'finds a site by the ID of its group, in each report' -ForEach @(
            @{ Kind = 'Teams' }
            @{ Kind = 'Groups' }
        ) {
            $report = New-TestReport -Kind $Kind -ById @{ $script:GroupA = (Get-TestDate '2026-10-01') }
            $reports = @{ $Kind = $report }

            $activity = Find-TestActivity @reports -SiteId $script:SiteA -GroupId '{11111111-1111-1111-1111-111111111111}'

            $activity.HasRow | Should -BeTrue
            $activity.LastActivity | Should -Be (Get-TestDate '2026-10-01')
            $activity.LastActivitySource | Should -BeExactly $Kind
            $activity.$Kind | Should -Be (Get-TestDate '2026-10-01')
        }

        It 'finds nothing for a site that has no group, whatever the report holds' -ForEach @(
            @{ GroupId = '' }
            @{ GroupId = $null }
            @{ GroupId = '00000000-0000-0000-0000-000000000000' }
        ) {
            $report = New-TestReport -Kind Teams -ById @{ $script:GroupA = (Get-TestDate '2026-10-01') }

            (Find-TestActivity -Teams $report -SiteId $script:SiteA -GroupId $GroupId).HasRow | Should -BeFalse
        }

        It 'does not look for the site ID in the Teams and groups reports, which are keyed by group' {
            $report = New-TestReport -Kind Teams -ById @{ $script:SiteA = (Get-TestDate '2026-10-01') }

            (Find-TestActivity -Teams $report -SiteId $script:SiteA -GroupId $script:GroupA).HasRow | Should -BeFalse
        }
    }

    Context 'Several reports' {
        BeforeEach {
            $script:SharePointReport = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2026-03-01') }
            $script:TeamsReport = New-TestReport -Kind Teams -ById @{ $script:GroupA = (Get-TestDate '2026-09-01') }
            $script:GroupsReport = New-TestReport -Kind Groups -ById @{ $script:GroupA = (Get-TestDate '2026-06-01') }
        }

        It 'keeps the most recent date, names its report, and gives the date of each report' {
            $activity = Find-TestActivity -SharePoint $script:SharePointReport -Teams $script:TeamsReport -Groups $script:GroupsReport -SiteId $script:SiteA -GroupId $script:GroupA

            $activity.LastActivity | Should -Be (Get-TestDate '2026-09-01')
            $activity.LastActivitySource | Should -BeExactly 'Teams'
            $activity.SharePoint | Should -Be (Get-TestDate '2026-03-01')
            $activity.Teams | Should -Be (Get-TestDate '2026-09-01')
            $activity.Groups | Should -Be (Get-TestDate '2026-06-01')
        }

        It 'names the first report of the order SharePoint, Teams, Groups when dates are equal' -ForEach @(
            @{ Name = 'all three'; Use = 'SharePoint', 'Teams', 'Groups'; Expected = 'SharePoint' }
            @{ Name = 'Teams and Groups'; Use = 'Teams', 'Groups'; Expected = 'Teams' }
            @{ Name = 'SharePoint and Groups'; Use = 'SharePoint', 'Groups'; Expected = 'SharePoint' }
        ) {
            $same = Get-TestDate '2026-05-05'
            $reports = @{}
            foreach ($kind in $Use) {
                $key = if ($kind -eq 'SharePoint') { $script:SiteA } else { $script:GroupA }
                $reports[$kind] = New-TestReport -Kind $kind -ById @{ $key = $same }
            }

            $activity = Find-TestActivity @reports -SiteId $script:SiteA -GroupId $script:GroupA

            $activity.LastActivity | Should -Be $same
            $activity.LastActivitySource | Should -BeExactly $Expected
        }

        It 'knows the site from one report when the others do not have it' {
            $activity = Find-TestActivity -SharePoint $script:SharePointReport -Teams $script:TeamsReport -SiteId $script:SiteB -GroupId $script:GroupA

            $activity.HasRow | Should -BeTrue
            $activity.LastActivitySource | Should -BeExactly 'Teams'
            $activity.SharePoint | Should -BeNullOrEmpty
        }

        It 'takes the date of another report when one report knows the site and has no date' {
            $empty = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null }

            $activity = Find-TestActivity -SharePoint $empty -Teams $script:TeamsReport -SiteId $script:SiteA -GroupId $script:GroupA

            $activity.HasRow | Should -BeTrue
            $activity.LastActivity | Should -Be (Get-TestDate '2026-09-01')
            $activity.LastActivitySource | Should -BeExactly 'Teams'
        }

        It 'finds no row when no report was given' {
            $activity = Find-TestActivity -SiteId $script:SiteA -GroupId $script:GroupA

            $activity.HasRow | Should -BeFalse
            $activity.LastActivity | Should -BeNullOrEmpty
            $activity.LastActivitySource | Should -BeExactly ''
        }
    }
}

Describe 'Get-SPSLifecycleExclusionIndex' {
    BeforeAll {
        function script:Write-TestList {
            param([string]$Name, [string]$Text)
            $path = Join-Path -Path $TestDrive -ChildPath $Name
            [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($true))
            $path
        }

        function script:Get-TestExclusionIndex {
            param([string[]]$File)
            & $script:Module { param($f) Get-SPSLifecycleExclusionIndex -ExclusionFile $f } $File
        }
    }

    It 'is empty when no list is given: <Name>' -ForEach @(
        @{ Name = 'an empty list'; File = @() }
        @{ Name = 'null'; File = $null }
        @{ Name = 'an empty path'; File = @('') }
    ) {
        $index = Get-TestExclusionIndex -File $File

        $index.Keys.Count | Should -Be 0
        @($index.Imports) | Should -HaveCount 0
    }

    It 'merges the lists, and names the first file that holds an address' {
        $first = Write-TestList -Name 'first.csv' -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`nhttps://contoso.sharepoint.com/sites/b`r`n"
        $second = Write-TestList -Name 'second.csv' -Text "Url`r`nhttps://contoso.sharepoint.com/sites/b`r`nhttps://contoso.sharepoint.com/sites/c`r`n"

        $index = Get-TestExclusionIndex -File $first, $second

        $index.Keys.Count | Should -Be 3
        $index.Keys['https://contoso.sharepoint.com/sites/a'] | Should -BeExactly 'first.csv'
        $index.Keys['https://contoso.sharepoint.com/sites/b'] | Should -BeExactly 'first.csv'
        $index.Keys['https://contoso.sharepoint.com/sites/c'] | Should -BeExactly 'second.csv'
        @($index.Imports) | Should -HaveCount 2
    }

    It 'holds one key for two spellings of an address' {
        $first = Write-TestList -Name 'first.csv' -Text "Url`r`nhttps://Contoso.sharepoint.com/Sites/A/`r`n"
        $second = Write-TestList -Name 'second.csv' -Text "Url`r`nhttps://contoso.sharepoint.com:443/sites/%61`r`n"

        (Get-TestExclusionIndex -File $first, $second).Keys.Count | Should -Be 1
    }

    It 'stops, and names the file, when a list cannot be read: a row that is lost would protect nothing' {
        $good = Write-TestList -Name 'good.csv' -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n"
        $bad = Write-TestList -Name 'bad.csv' -Text "Url`r`nSales`r`n"

        { Get-TestExclusionIndex -File $good, $bad } | Should -Throw -ExpectedMessage '*bad.csv*'
    }

    It 'stops, and names the file, when a list does not exist' {
        { Get-TestExclusionIndex -File (Join-Path -Path $TestDrive -ChildPath 'nothing.csv') } | Should -Throw -ExpectedMessage '*nothing.csv*'
    }
}

Describe 'Initialize-SPSLifecycleScanSummary' {
    It 'starts with nothing counted' {
        $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }

        $summary.SitesRead | Should -Be 0
        $summary.SitesListed | Should -Be 0
        $summary.LeftOutOneDrive | Should -Be 0
        $summary.LeftOutLockState | Should -Be 0
        $summary.ByVerdict.Count | Should -Be 0
        $summary.ByAction.Count | Should -Be 0
    }

    It 'gives a new summary at each call, so that two runs never share their counts' {
        $first = & $script:Module { Initialize-SPSLifecycleScanSummary }
        $first.SitesRead = 5
        $first.ByVerdict['LOCK'] = 1
        $second = & $script:Module { Initialize-SPSLifecycleScanSummary }

        $second.SitesRead | Should -Be 0
        $second.ByVerdict.Count | Should -Be 0
    }
}

Describe 'ConvertTo-SPSLifecycleScanRow' {
    BeforeAll {
        $script:Now = [System.DateTime]::new(2026, 10, 29, 8, 0, 0, [System.DateTimeKind]::Utc)
        $script:Old = Get-TestDate '2025-01-01'

        function script:New-ScanSetting {
            param([string[]]$LockStates = @('ReadOnly'), [string[]]$Accepted = @('ReadOnly'))
            [PSCustomObject]@{
                TenantName         = 'contoso'
                TenantUrl          = 'https://contoso.sharepoint.com'
                AcceptedLockStates = $Accepted
                MinLockedDays      = 365
                DeleteMaxSizeGB    = 1.0
                Scan               = [PSCustomObject]@{ InactiveDays = 365; LockStates = $LockStates }
            }
        }

        # A site record, as the listing of the tenant gives it.
        function script:New-ScanSite {
            param(
                [string]$Name = 'a',
                $SiteId = $script:SiteA,
                [string]$Template = 'GROUP#0',
                [string]$LockState = 'ReadOnly',
                $GroupId = $script:GroupA,
                $Size = 100,
                [string]$Archive = 'NotArchived',
                [bool]$Hub = $false,
                [bool]$Channel = $false,
                $Modified = $null,
                $Title = 'Sales',
                [string]$Url = ''
            )

            [PSCustomObject]@{
                Url                     = if ($Url) { $Url } else { "https://contoso.sharepoint.com/sites/$Name" }
                SiteId                  = $SiteId
                Title                   = $Title
                Template                = $Template
                LockState               = $LockState
                GroupId                 = $GroupId
                IsHubSite               = $Hub
                IsTeamsConnected        = $false
                IsTeamsChannelConnected = $Channel
                ArchiveStatus           = $Archive
                StorageUsedMB           = $Size
                LastContentModified     = $Modified
            }
        }

        # The index of the lock dates, as Get-SPSLifecycleLockDateIndex gives it.
        function script:New-LockIndex {
            param([object[]]$Entry = @())
            $items = foreach ($e in $Entry) {
                $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $e.Url
                $source = if ($e.Source) { $e.Source } else { 'lot1.csv' }
                [PSCustomObject]@{ Url = $e.Url; UrlKey = $key; SiteId = $e.SiteId; LockedOn = $e.LockedOn; Source = $source }
            }

            $import = [PSCustomObject]@{ Name = 'lot1.csv'; RowCount = @($items).Count; Entries = @($items) }
            & $script:Module { param($i) Merge-SPSLifecycleLockDate -Import @($i) } $import
        }

        function script:New-ExclusionIndex {
            param([string[]]$Url = @())
            $keys = @{}
            foreach ($u in $Url) {
                $keys[(& $script:Module { param($x) ConvertTo-SPSLifecycleUrlKey -Url $x } $u)] = 'exclusions.csv'
            }

            [PSCustomObject]@{ Keys = $keys; Imports = @() }
        }

        $script:QuietReport = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null; $script:SiteB = $null }

        function script:Invoke-TestScan {
            param(
                $Site,
                $Setting = (New-ScanSetting),
                $Report = @($script:QuietReport),
                $LockIndex = (New-LockIndex),
                $ExclusionIndex = (New-ExclusionIndex),
                $Now = $script:Now,
                [string]$HomeSiteUrl = ''
            )

            $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }
            $parameters = @{ Setting = $Setting; ActivityReport = @($Report); LockDateIndex = $LockIndex; ExclusionIndex = $ExclusionIndex; Summary = $summary; Now = $Now; HomeSiteUrl = $HomeSiteUrl }
            $rows = @(& $script:Module { param($s, $p) $s | ConvertTo-SPSLifecycleScanRow @p } @($Site) $parameters)

            [PSCustomObject]@{ Rows = $rows; Summary = $summary }
        }

        function script:New-OldLock {
            param($Site, $SiteId = $script:SiteA, $At = $script:Old)
            New-LockIndex -Entry @(@{ Url = $Site.Url; SiteId = $SiteId; LockedOn = $At })
        }
    }

    Context 'The verdict of a site, from the listing, the reports, the lock dates and the exclusions' {
        It 'gives <Expected> to <Name>' -ForEach @(
            @{ Name = 'a quiet read-only site with a group'; Case = 'group'; Expected = 'DELETE-VIA-GROUP'; Action = 'Delete' }
            @{ Name = 'a quiet read-only site without a group'; Case = 'nogroup'; Expected = 'DELETE-SITE'; Action = 'Delete' }
            @{ Name = 'a large site'; Case = 'large'; Expected = 'ARCHIVE'; Action = 'Archive' }
            @{ Name = 'a large site that cannot be archived'; Case = 'largeunarchivable'; Expected = 'SKIP-NOT-ARCHIVABLE'; Action = '' }
            @{ Name = 'an unlocked site, when Unlock is listed'; Case = 'unlocked'; Expected = 'LOCK'; Action = 'Lock' }
            @{ Name = 'a read-only site that has no lock date'; Case = 'nodate'; Expected = 'SKIP-NO-LOCK-DATE'; Action = '' }
            @{ Name = 'a site locked 100 days ago'; Case = 'recentlock'; Expected = 'SKIP-TOO-RECENT-LOCK'; Action = '' }
            @{ Name = 'a site with a recent activity'; Case = 'activity'; Expected = 'SKIP-RECENT-ACTIVITY'; Action = '' }
            @{ Name = 'a site whose content changed recently'; Case = 'modified'; Expected = 'SKIP-RECENT-ACTIVITY'; Action = '' }
            @{ Name = 'a site that is in no report'; Case = 'norow'; Expected = 'REVIEW-NO-ACTIVITY-ROW'; Action = '' }
            @{ Name = 'a site whose size is unknown'; Case = 'nosize'; Expected = 'REVIEW-NO-SIZE'; Action = '' }
            @{ Name = 'a site in an exclusion list'; Case = 'excluded'; Expected = 'SKIP-EXCLUDED'; Action = '' }
            @{ Name = 'a channel site'; Case = 'channel'; Expected = 'SKIP-CHANNEL-SITE'; Action = '' }
            @{ Name = 'a hub site'; Case = 'hub'; Expected = 'SKIP-PROTECTED'; Action = '' }
            @{ Name = 'a system site'; Case = 'system'; Expected = 'SKIP-PROTECTED'; Action = '' }
            @{ Name = 'the home site'; Case = 'home'; Expected = 'SKIP-PROTECTED'; Action = '' }
            @{ Name = 'an archived site'; Case = 'archived'; Expected = 'SKIP-ALREADY-ARCHIVED'; Action = '' }
            @{ Name = 'a read-only site when only an unlocked one is accepted'; Case = 'lockstate'; Expected = 'SKIP-LOCK-STATE'; Action = '' }
        ) {
            $site = New-ScanSite
            $lock = New-OldLock -Site $site
            $setting = New-ScanSetting
            $report = @($script:QuietReport)
            $exclusion = New-ExclusionIndex
            $homeSite = ''
            switch ($Case) {
                'nogroup' { $site = New-ScanSite -GroupId ''; $lock = New-OldLock -Site $site }
                'large' { $site = New-ScanSite -Size 5000; $lock = New-OldLock -Site $site }
                'largeunarchivable' { $site = New-ScanSite -Size 5000 -Template 'BLANKINTERNET#0'; $lock = New-OldLock -Site $site }
                'unlocked' { $site = New-ScanSite -LockState 'Unlock'; $setting = New-ScanSetting -LockStates 'ReadOnly', 'Unlock'; $lock = New-LockIndex }
                'nodate' { $lock = New-LockIndex }
                'recentlock' { $lock = New-OldLock -Site $site -At $script:Now.AddDays(-100) }
                'activity' { $report = @(New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2026-10-01') }) }
                'modified' { $site = New-ScanSite -Modified $script:Now.AddDays(-10); $lock = New-OldLock -Site $site }
                'norow' { $report = @(New-TestReport -Kind SharePoint -ById @{ $script:SiteB = $null }) }
                'nosize' { $site = New-ScanSite -Size $null; $lock = New-OldLock -Site $site }
                'excluded' { $exclusion = New-ExclusionIndex -Url $site.Url }
                'channel' { $site = New-ScanSite -Template 'TEAMCHANNEL#1'; $lock = New-OldLock -Site $site }
                'hub' { $site = New-ScanSite -Hub $true; $lock = New-OldLock -Site $site }
                'system' { $site = New-ScanSite -Template 'APPCATALOG#0'; $lock = New-OldLock -Site $site }
                'home' { $homeSite = $site.Url }
                'archived' { $site = New-ScanSite -Archive 'RecentlyArchived'; $lock = New-OldLock -Site $site }
                'lockstate' { $setting = New-ScanSetting -Accepted 'Unlock' }
            }

            $result = Invoke-TestScan -Site $site -Setting $setting -Report $report -LockIndex $lock -ExclusionIndex $exclusion -HomeSiteUrl $homeSite

            $result.Rows | Should -HaveCount 1
            $result.Rows[0].Verdict | Should -BeExactly $Expected
            $result.Rows[0].SuggestedAction | Should -BeExactly $Action
        }

        It 'lists the other sites when a site gets no verdict from the engine because it is left out, and keeps the order of the listing' {
            $sites = @(
                (New-ScanSite -Name 'one' -SiteId $script:SiteA)
                (New-ScanSite -Name 'two' -SiteId $script:SiteB -GroupId '')
            )
            $lock = New-LockIndex -Entry @(
                @{ Url = $sites[0].Url; SiteId = $script:SiteA; LockedOn = $script:Old }
                @{ Url = $sites[1].Url; SiteId = $script:SiteB; LockedOn = $script:Old }
            )

            $result = Invoke-TestScan -Site $sites -LockIndex $lock

            @($result.Rows.Url) | Should -Be @('https://contoso.sharepoint.com/sites/one', 'https://contoso.sharepoint.com/sites/two')
            @($result.Rows.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-SITE')
        }
    }

    Context 'The address of the home site, when the listing is what reads it' {
        BeforeAll {
            # The source is called by the converter when the first record comes, because the pipeline binds the parameters before the
            # listing signs in and reads the home site.
            function script:Invoke-TestScanWithSource {
                param($Site, [scriptblock]$Source, [hashtable]$Extra = @{})

                $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }
                $site1 = New-ScanSite
                $parameters = @{
                    Setting = (New-ScanSetting); ActivityReport = @($script:QuietReport); LockDateIndex = (New-OldLock -Site $site1)
                    ExclusionIndex = (New-ExclusionIndex); Summary = $summary; Now = $script:Now; HomeSiteUrlSource = $Source
                }
                foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
                $rows = @(& $script:Module { param($s, $p) $s | ConvertTo-SPSLifecycleScanRow @p } @($Site) $parameters)
                [PSCustomObject]@{ Rows = $rows; Summary = $summary }
            }
        }

        It 'asks for it once, when the first record comes, and protects that site and no other' {
            $state = @{ Calls = 0 }
            $source = { $state.Calls++; 'https://contoso.sharepoint.com/sites/home' }.GetNewClosure()
            $sites = @(
                (New-ScanSite -Name 'home' -SiteId $script:SiteA)
                (New-ScanSite -Name 'other' -SiteId $script:SiteB -GroupId '')
                (New-ScanSite -Name 'third' -SiteId 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')
            )
            $lock = New-LockIndex -Entry @(foreach ($s in $sites) { @{ Url = $s.Url; SiteId = $s.SiteId; LockedOn = $script:Old } })
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null; $script:SiteB = $null; 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' = $null }

            $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }
            $parameters = @{
                Setting = (New-ScanSetting); ActivityReport = @($report); LockDateIndex = $lock; ExclusionIndex = (New-ExclusionIndex)
                Summary = $summary; Now = $script:Now; HomeSiteUrlSource = $source
            }
            $rows = @(& $script:Module { param($s, $p) $s | ConvertTo-SPSLifecycleScanRow @p } $sites $parameters)

            $state.Calls | Should -Be 1
            @($rows.Verdict) | Should -Be @('SKIP-PROTECTED', 'DELETE-SITE', 'DELETE-VIA-GROUP')
        }

        It 'reads the address that the source gives with the case and the slash of any spelling' {
            $source = { 'HTTPS://Contoso.SharePoint.com/Sites/A/' }
            $site = New-ScanSite

            (Invoke-TestScanWithSource -Site $site -Source $source).Rows[0].Verdict | Should -BeExactly 'SKIP-PROTECTED'
        }

        It 'does not ask for it when the listing gave no site' {
            $state = @{ Calls = 0 }
            $source = { $state.Calls++; 'https://contoso.sharepoint.com/sites/home' }.GetNewClosure()

            $result = Invoke-TestScanWithSource -Site @() -Source $source

            $result.Rows | Should -HaveCount 0
            $state.Calls | Should -Be 0
        }

        It 'protects nothing as the home site when the tenant has none: <Name>' -ForEach @(
            @{ Name = 'an empty text'; Value = '' }
            @{ Name = 'nothing'; Value = $null }
        ) {
            $state = @{ Value = $Value }
            $source = { $state.Value }.GetNewClosure()

            (Invoke-TestScanWithSource -Site (New-ScanSite) -Source $source).Rows[0].Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'stops with the message of the source, and gives no row, when the source fails: the home site could be suggested' {
            $source = { throw 'The home site of the tenant could not be read: Access denied.' }

            { Invoke-TestScanWithSource -Site (New-ScanSite) -Source $source } | Should -Throw -ExpectedMessage 'The home site of the tenant could not be read: Access denied.'
        }

        It 'stops when the source gives something that is not one address: <Name>' -ForEach @(
            @{ Name = 'an array of two addresses'; Value = @('https://contoso.sharepoint.com/sites/a', 'https://contoso.sharepoint.com/sites/b') }
            @{ Name = 'a number'; Value = 42 }
            @{ Name = 'an object'; Value = [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/a' } }
        ) {
            $state = @{ Value = $Value }
            $source = { , $state.Value }.GetNewClosure()

            { Invoke-TestScanWithSource -Site (New-ScanSite) -Source $source } | Should -Throw -ExpectedMessage '*home site*not a text*'
        }

        It 'stops when the source gives two answers, one after the other, since it cannot tell which is the home site: <Name>' -ForEach @(
            @{ Name = 'two addresses'; Source = { 'https://contoso.sharepoint.com/sites/a'; 'https://contoso.sharepoint.com/sites/b' } }
            @{ Name = 'three addresses'; Source = { 'https://contoso.sharepoint.com/sites/a'; 'https://contoso.sharepoint.com/sites/b'; 'https://contoso.sharepoint.com/sites/c' } }
            @{ Name = 'an empty text and an address'; Source = { ''; 'https://contoso.sharepoint.com/sites/a' } }
        ) {
            { Invoke-TestScanWithSource -Site (New-ScanSite) -Source $Source } | Should -Throw -ExpectedMessage '*home site*not a text*'
        }

        It 'cannot be given together with the address itself, which would leave it to the order of the two to decide' {
            $source = { 'https://contoso.sharepoint.com/sites/a' }

            { Invoke-TestScanWithSource -Site (New-ScanSite) -Source $source -Extra @{ HomeSiteUrl = 'https://contoso.sharepoint.com/sites/b' } } | Should -Throw
        }
    }

    Context 'What the row holds' {
        It 'has the columns of the report, in their order' {
            $site = New-ScanSite

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)).Rows[0]

            @($row.PSObject.Properties.Name) | Should -Be @(& $script:Module { Get-SPSLifecycleReportColumn } | ForEach-Object { $_.Name })
        }

        It 'fills each column from its source' {
            $site = New-ScanSite -Name 'Sales' -SiteId '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}' -GroupId '{11111111-1111-1111-1111-111111111111}' -Size 250 -Title 'Sales team' -Modified (Get-TestDate '2025-02-03')
            $site.IsTeamsConnected = $true
            $lock = New-LockIndex -Entry @(@{ Url = $site.Url; SiteId = $script:SiteA; LockedOn = (Get-TestDate '2025-03-04'); Source = 'lot2.csv' })
            $sharePoint = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2025-05-01') }
            $teams = New-TestReport -Kind Teams -ById @{ $script:GroupA = (Get-TestDate '2025-06-10') }
            $groups = New-TestReport -Kind Groups -ById @{ $script:GroupA = (Get-TestDate '2025-04-01') }

            $row = (Invoke-TestScan -Site $site -LockIndex $lock -Report @($sharePoint, $teams, $groups)).Rows[0]

            $row.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/Sales'
            $row.Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
            $row.SuggestedAction | Should -BeExactly 'Delete'
            $row.Decision | Should -BeExactly ''
            $row.SiteId | Should -BeExactly $script:SiteA
            $row.Title | Should -BeExactly 'Sales team'
            $row.Template | Should -BeExactly 'GROUP#0'
            $row.GroupId | Should -BeExactly $script:GroupA
            $row.IsTeamsConnected | Should -BeTrue
            $row.LockState | Should -BeExactly 'ReadOnly'
            $row.ArchiveStatus | Should -BeExactly 'NotArchived'
            $row.StorageUsedMB | Should -Be 250
            $row.LastActivity | Should -Be (Get-TestDate '2025-06-10')
            $row.LastActivitySource | Should -BeExactly 'Teams'
            $row.InactiveDays | Should -Be 506
            $row.SharePointActivity | Should -Be (Get-TestDate '2025-05-01')
            $row.TeamsActivity | Should -Be (Get-TestDate '2025-06-10')
            $row.GroupActivity | Should -Be (Get-TestDate '2025-04-01')
            $row.ContentModified | Should -Be (Get-TestDate '2025-02-03')
            $row.LockedOn | Should -Be (Get-TestDate '2025-03-04')
            $row.LockedOnSource | Should -BeExactly 'lot2.csv'
            $row.GeneratedOn | Should -Be $script:Now
        }

        It 'leaves the columns of what it does not know empty: <Name>' -ForEach @(
            @{ Name = 'no activity date'; Column = 'LastActivity' }
            @{ Name = 'no activity date, so no source'; Column = 'LastActivitySource' }
            @{ Name = 'no activity date, so no inactive days'; Column = 'InactiveDays' }
            @{ Name = 'no SharePoint date'; Column = 'SharePointActivity' }
            @{ Name = 'no Teams report'; Column = 'TeamsActivity' }
            @{ Name = 'no groups report'; Column = 'GroupActivity' }
            @{ Name = 'no content change'; Column = 'ContentModified' }
        ) {
            $site = New-ScanSite

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)).Rows[0]

            $row.$Column | Should -BeNullOrEmpty
            $row.Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'counts the inactive days as whole days, from the time of the run, and never below zero' -ForEach @(
            @{ Last = '2026-10-28'; Expected = 1 }
            @{ Last = '2026-10-29'; Expected = 0 }
            @{ Last = '2026-10-30'; Expected = 0 }
            @{ Last = '2025-10-29'; Expected = 365 }
        ) {
            $site = New-ScanSite
            $report = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate $Last) }

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Report @($report)).Rows[0]

            $row.InactiveDays | Should -Be $Expected
        }

        It 'shows the lock date of a site whose date is known, and nothing for the others' {
            $site = New-ScanSite
            $other = New-ScanSite -Name 'b' -SiteId $script:SiteB
            $lock = New-OldLock -Site $site

            $rows = (Invoke-TestScan -Site @($site, $other) -LockIndex $lock).Rows

            $rows[0].LockedOn | Should -Be $script:Old
            $rows[0].LockedOnSource | Should -BeExactly 'lot1.csv'
            $rows[1].LockedOn | Should -BeNullOrEmpty
            $rows[1].LockedOnSource | Should -BeNullOrEmpty
        }

        It 'keeps the address as the tenant gives it, and the group empty when the site has none' -ForEach @(
            @{ GroupId = '' }
            @{ GroupId = $null }
            @{ GroupId = '00000000-0000-0000-0000-000000000000' }
        ) {
            $site = New-ScanSite -GroupId $GroupId -Url ' https://Contoso.sharepoint.com/Sites/Mixed/ '
            $lock = New-LockIndex -Entry @(@{ Url = 'https://contoso.sharepoint.com/sites/mixed'; SiteId = $script:SiteA; LockedOn = $script:Old })

            $row = (Invoke-TestScan -Site $site -LockIndex $lock).Rows[0]

            $row.Url | Should -BeExactly 'https://Contoso.sharepoint.com/Sites/Mixed/'
            $row.GroupId | Should -BeExactly ''
            $row.Verdict | Should -BeExactly 'DELETE-SITE'
        }

        It 'does not change the record that it is given' {
            $site = New-ScanSite -Modified (Get-TestDate '2026-02-03')
            $before = $site | ConvertTo-Json -Depth 3

            $null = Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)

            ($site | ConvertTo-Json -Depth 3) | Should -BeExactly $before
        }
    }

    Context 'What it leaves out' {
        It 'leaves out a OneDrive site, however it is recognized, and counts it: <Name>' -ForEach @(
            @{ Name = 'by its template'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'SPSPERS#10' }
            @{ Name = 'by its address'; Url = 'https://contoso-my.sharepoint.com/personal/b_contoso_com'; Template = 'STS#3' }
            @{ Name = 'by its address with the dot of the DNS root'; Url = 'https://contoso-my.sharepoint.com./personal/c_contoso_com'; Template = 'STS#3' }
            @{ Name = 'by its address with a port'; Url = 'https://contoso-my.sharepoint.com:8443/personal/d_contoso_com'; Template = 'STS#3' }
        ) {
            $site = New-ScanSite -Url $Url -Template $Template
            $other = New-ScanSite -Name 'b' -SiteId $script:SiteB

            $result = Invoke-TestScan -Site @($site, $other) -LockIndex (New-OldLock -Site $other -SiteId $script:SiteB)

            $result.Rows | Should -HaveCount 1
            $result.Rows[0].SiteId | Should -BeExactly $script:SiteB
            $result.Summary.LeftOutOneDrive | Should -Be 1
            $result.Summary.SitesRead | Should -Be 2
            $result.Summary.SitesListed | Should -Be 1
        }

        It 'leaves out a site whose address cannot be read, and counts it with the OneDrive sites: <Name>' -ForEach @(
            @{ Name = 'user information and a bidirectional isolate in the OneDrive host'; Url = "https://someone@contoso-my.share$([char]0x2066)point.com/personal/e_contoso_com" }
            @{ Name = 'user information, a soft hyphen and a bidirectional isolate in the OneDrive host'; Url = "https://someone@contoso-my.share$([char]0xAD)$([char]0x2066)point.com/personal/e_contoso_com" }
            @{ Name = 'a host that DNS refuses, of another tenant'; Url = "https://fabrikam.share$([char]0x2066)point.com/sites/e" }
            @{ Name = 'an address that does not parse'; Url = 'https://someone@contoso-my.sharepoint.com../personal/f_contoso_com' }
            @{ Name = 'a text that is not an address'; Url = 'not an address' }
            @{ Name = 'another scheme'; Url = 'ftp://contoso.sharepoint.com/sites/e' }
            @{ Name = 'the root site with the dot of the DNS root'; Url = 'https://contoso.sharepoint.com./' }
            @{ Name = 'the root site in http'; Url = 'http://contoso.sharepoint.com/' }
            @{ Name = 'a team site with a port that is not the default one'; Url = 'https://contoso.sharepoint.com:8443/sites/e' }
        ) {
            $site = New-ScanSite -Url $Url -Template 'STS#3'
            $other = New-ScanSite -Name 'b' -SiteId $script:SiteB

            $result = Invoke-TestScan -Site @($site, $other) -LockIndex (New-OldLock -Site $other -SiteId $script:SiteB)

            $result.Rows | Should -HaveCount 1
            $result.Rows[0].SiteId | Should -BeExactly $script:SiteB
            $result.Summary.LeftOutOneDrive | Should -Be 1
            $result.Summary.ByVerdict.Keys | Should -Not -Contain 'DELETE-SITE' -Because 'the site whose address cannot be read must not reach an action'
        }

        It 'still lists a site whose address is plain, however the address is spelled: <Name>' -ForEach @(
            @{ Name = 'the default port written out'; Url = 'https://contoso.sharepoint.com:443/sites/e' }
            @{ Name = 'user information'; Url = 'https://someone@contoso.sharepoint.com/sites/e' }
            @{ Name = 'capitals and a path that is not ASCII'; Url = "HTTPS://CONTOSO.sharepoint.com/Sites/$([char]0xC9)quipe" }
        ) {
            $site = New-ScanSite -Url $Url -Template 'GROUP#0'

            $result = Invoke-TestScan -Site $site

            $result.Rows | Should -HaveCount 1
            $result.Summary.LeftOutOneDrive | Should -Be 0
        }

        It 'leaves out a OneDrive site that has no site ID, and does not stop on it' {
            $site = New-ScanSite -Url 'https://contoso-my.sharepoint.com/personal/a_contoso_com' -Template 'SPSPERS#10' -SiteId $null

            $result = Invoke-TestScan -Site $site

            $result.Rows | Should -HaveCount 0
            $result.Summary.LeftOutOneDrive | Should -Be 1
        }

        It 'lists only the lock states that the Scan asks for, and counts the others: <Name>' -ForEach @(
            @{ Name = 'ReadOnly only'; LockStates = @('ReadOnly'); Listed = 1; LeftOut = 2 }
            @{ Name = 'ReadOnly and Unlock'; LockStates = @('ReadOnly', 'Unlock'); Listed = 2; LeftOut = 1 }
            @{ Name = 'Unlock only'; LockStates = @('Unlock'); Listed = 1; LeftOut = 2 }
        ) {
            $sites = @(
                (New-ScanSite -Name 'ro' -LockState 'ReadOnly')
                (New-ScanSite -Name 'un' -LockState 'Unlock' -SiteId $script:SiteB)
                (New-ScanSite -Name 'na' -LockState 'NoAccess' -SiteId '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708')
            )
            $setting = New-ScanSetting -LockStates $LockStates

            $result = Invoke-TestScan -Site $sites -Setting $setting

            $result.Rows | Should -HaveCount $Listed
            $result.Summary.LeftOutLockState | Should -Be $LeftOut
            $result.Summary.SitesRead | Should -Be 3
        }

        It 'leaves out a site whose lock state is empty, like any lock state that the Scan does not ask for' {
            $site = New-ScanSite -LockState ''

            $result = Invoke-TestScan -Site $site

            $result.Rows | Should -HaveCount 0
            $result.Summary.LeftOutLockState | Should -Be 1
        }
    }

    Context 'The summary' {
        It 'counts the sites read, listed and left out, and the rows per verdict and per suggested action' {
            $sites = @(
                (New-ScanSite -Name 'g1' -SiteId '10000000-0000-0000-0000-000000000001')
                (New-ScanSite -Name 'g2' -SiteId '10000000-0000-0000-0000-000000000002')
                (New-ScanSite -Name 'n1' -SiteId '10000000-0000-0000-0000-000000000003' -GroupId '')
                (New-ScanSite -Name 'big' -SiteId '10000000-0000-0000-0000-000000000004' -Size 5000)
                (New-ScanSite -Name 'hub' -SiteId '10000000-0000-0000-0000-000000000005' -Hub $true)
                (New-ScanSite -Name 'od' -SiteId '10000000-0000-0000-0000-000000000006' -Template 'SPSPERS#10')
                (New-ScanSite -Name 'no' -SiteId '10000000-0000-0000-0000-000000000007' -LockState 'NoAccess')
            )
            $entries = foreach ($s in $sites) { @{ Url = $s.Url; SiteId = $s.SiteId; LockedOn = $script:Old } }
            $ids = @{}
            foreach ($s in $sites) { $ids[$s.SiteId] = $null }
            $report = New-TestReport -Kind SharePoint -ById $ids

            $result = Invoke-TestScan -Site $sites -LockIndex (New-LockIndex -Entry $entries) -Report @($report)

            $result.Summary.SitesRead | Should -Be 7
            $result.Summary.SitesListed | Should -Be 5
            $result.Summary.LeftOutOneDrive | Should -Be 1
            $result.Summary.LeftOutLockState | Should -Be 1
            $result.Summary.ByVerdict['DELETE-VIA-GROUP'] | Should -Be 2
            $result.Summary.ByVerdict['DELETE-SITE'] | Should -Be 1
            $result.Summary.ByVerdict['ARCHIVE'] | Should -Be 1
            $result.Summary.ByVerdict['SKIP-PROTECTED'] | Should -Be 1
            $result.Summary.ByAction['Delete'] | Should -Be 3
            $result.Summary.ByAction['Archive'] | Should -Be 1
            $result.Summary.ByAction['None'] | Should -Be 1
            ($result.Summary.ByVerdict.Values | Measure-Object -Sum).Sum | Should -Be $result.Summary.SitesListed
            ($result.Summary.ByAction.Values | Measure-Object -Sum).Sum | Should -Be $result.Summary.SitesListed
        }

        It 'counts a lock suggestion, per verdict and per action, as it counts the others' {
            $sites = @(
                (New-ScanSite -Name 'u1' -SiteId '10000000-0000-0000-0000-000000000001' -LockState 'Unlock')
                (New-ScanSite -Name 'u2' -SiteId '10000000-0000-0000-0000-000000000002' -LockState 'Unlock')
                (New-ScanSite -Name 'r1' -SiteId '10000000-0000-0000-0000-000000000003')
            )
            $ids = @{}
            foreach ($s in $sites) { $ids[$s.SiteId] = $null }
            $lock = New-LockIndex -Entry @(@{ Url = $sites[2].Url; SiteId = $sites[2].SiteId; LockedOn = $script:Old })

            $result = Invoke-TestScan -Site $sites -Setting (New-ScanSetting -LockStates 'ReadOnly', 'Unlock') -Report @((New-TestReport -Kind SharePoint -ById $ids)) -LockIndex $lock

            $result.Summary.ByVerdict['LOCK'] | Should -Be 2
            $result.Summary.ByVerdict['DELETE-VIA-GROUP'] | Should -Be 1
            $result.Summary.ByAction['Lock'] | Should -Be 2
            $result.Summary.ByAction['Delete'] | Should -Be 1
            $result.Summary.ByAction.ContainsKey('None') | Should -BeFalse
        }

        It 'always satisfies: read = listed + left out' {
            $sites = 1..30 | ForEach-Object {
                $template = if ($_ % 5 -eq 0) { 'SPSPERS#10' } else { 'GROUP#0' }
                $state = if ($_ % 7 -eq 0) { 'NoAccess' } else { 'ReadOnly' }
                New-ScanSite -Name "s$_" -SiteId ('10000000-0000-0000-0000-{0:D12}' -f $_) -Template $template -LockState $state
            }

            $summary = (Invoke-TestScan -Site $sites).Summary

            $summary.SitesRead | Should -Be 30
            $summary.SitesRead | Should -Be ($summary.SitesListed + $summary.LeftOutOneDrive + $summary.LeftOutLockState)
        }
    }

    Context 'The lock dates and the activity of a site, matched as the design says' {
        It 'keeps the lock date of a renamed site: the ID decides, not the address' {
            $site = New-ScanSite -Name 'new-name'
            $lock = New-LockIndex -Entry @(@{ Url = 'https://contoso.sharepoint.com/sites/old-name'; SiteId = $script:SiteA; LockedOn = $script:Old })

            (Invoke-TestScan -Site $site -LockIndex $lock).Rows[0].Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'does not give a site the lock date of the site that had its address before' {
            $site = New-ScanSite
            $lock = New-LockIndex -Entry @(@{ Url = $site.Url; SiteId = $script:SiteB; LockedOn = $script:Old })

            $row = (Invoke-TestScan -Site $site -LockIndex $lock).Rows[0]

            $row.Verdict | Should -BeExactly 'SKIP-NO-LOCK-DATE'
            $row.LockedOn | Should -BeNullOrEmpty
        }

        It 'finds a lock date that a list gives by the address only' {
            $site = New-ScanSite
            $lock = New-LockIndex -Entry @(@{ Url = 'https://CONTOSO.sharepoint.com/sites/a/'; SiteId = ''; LockedOn = $script:Old })

            (Invoke-TestScan -Site $site -LockIndex $lock).Rows[0].Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'does not take the activity of the site that had the address before: the site is then in no report' {
            $site = New-ScanSite
            $report = New-TestReport -Kind SharePoint -ByUrl @{ $site.Url.ToLowerInvariant() = (Get-TestDate '2020-01-01') } -ByUrlId @{ $site.Url.ToLowerInvariant() = $script:SiteB }

            (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Report @($report)).Rows[0].Verdict | Should -BeExactly 'REVIEW-NO-ACTIVITY-ROW'
        }

        It 'sees the activity that only Teams shows: a site that is quiet in SharePoint is not inactive' {
            $site = New-ScanSite
            $sharePoint = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = (Get-TestDate '2025-01-01') }
            $teams = New-TestReport -Kind Teams -ById @{ $script:GroupA = (Get-TestDate '2026-10-20') }

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Report @($sharePoint, $teams)).Rows[0]

            $row.Verdict | Should -BeExactly 'SKIP-RECENT-ACTIVITY'
            $row.LastActivitySource | Should -BeExactly 'Teams'
        }

        It 'finds the exclusion whatever the spelling of the address' {
            $site = New-ScanSite -Url 'https://contoso.sharepoint.com:443/sites/%C3%89quipe/'
            $exclusion = New-ExclusionIndex -Url 'https://contoso.sharepoint.com/sites/Équipe'

            (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -ExclusionIndex $exclusion).Rows[0].Verdict | Should -BeExactly 'SKIP-EXCLUDED'
        }

        It 'never suggests an action for a site whose group is unknown to every report that has groups' {
            $site = New-ScanSite
            $teams = New-TestReport -Kind Teams -ById @{ $script:GroupB = (Get-TestDate '2020-01-01') }

            (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Report @($teams)).Rows[0].Verdict | Should -BeExactly 'REVIEW-NO-ACTIVITY-ROW'
        }
    }

    Context 'What it refuses' {
        It 'stops on a record that is not usable, and names its number and its address: <Name>' -ForEach @(
            @{ Name = 'a record with no site ID'; Site = 'noid'; Message = '*record 2*sites/two*site ID*' }
            @{ Name = 'a site ID of zeros'; Site = 'zeros'; Message = '*record 2*sites/two*site ID*' }
            @{ Name = 'a site ID that is not a GUID'; Site = 'garbage'; Message = '*record 2*sites/two*site ID*' }
            @{ Name = 'a record with no address'; Site = 'nourl'; Message = '*record 2*address*' }
            @{ Name = 'a content change that is not a date'; Site = 'badmodified'; Message = '*record 2*sites/two*LastContentModified*' }
            @{ Name = 'a group ID that is not a GUID'; Site = 'badgroup'; Message = '*record 2*sites/two*group ID*GroupId*garbage*' }
            @{ Name = 'half of a group ID'; Site = 'halfgroup'; Message = '*record 2*sites/two*group ID*' }
            @{ Name = 'no answer to IsHubSite'; Site = 'nohub'; Message = '*record 2*sites/two*IsHubSite*' }
            @{ Name = 'IsHubSite written as text'; Site = 'texthub'; Message = '*record 2*sites/two*IsHubSite*' }
            @{ Name = 'no answer to IsTeamsChannelConnected'; Site = 'nochannel'; Message = '*record 2*sites/two*IsTeamsChannelConnected*' }
            @{ Name = 'no template'; Site = 'notemplate'; Message = '*record 2*sites/two*Template*' }
            @{ Name = 'a template that is a number'; Site = 'numbertemplate'; Message = '*record 2*sites/two*Template*' }
        ) {
            $first = New-ScanSite -Name 'one'
            $bad = switch ($Site) {
                'noid' { New-ScanSite -Name 'two' -SiteId $null }
                'zeros' { New-ScanSite -Name 'two' -SiteId '00000000-0000-0000-0000-000000000000' }
                'garbage' { New-ScanSite -Name 'two' -SiteId 'not a guid' }
                'nourl' { New-ScanSite -Name 'two' -Url ' ' }
                'badmodified' { New-ScanSite -Name 'two' -SiteId $script:SiteB -Modified 'last tuesday' }
                'badgroup' { New-ScanSite -Name 'two' -SiteId $script:SiteB -GroupId 'garbage' }
                'halfgroup' { New-ScanSite -Name 'two' -SiteId $script:SiteB -GroupId '11111111-1111' }
                'nohub' { $s = New-ScanSite -Name 'two' -SiteId $script:SiteB; $s.IsHubSite = $null; $s }
                'texthub' { $s = New-ScanSite -Name 'two' -SiteId $script:SiteB; $s.IsHubSite = 'False'; $s }
                'nochannel' { $s = New-ScanSite -Name 'two' -SiteId $script:SiteB; $s.PSObject.Properties.Remove('IsTeamsChannelConnected'); $s }
                'notemplate' { New-ScanSite -Name 'two' -SiteId $script:SiteB -Template ' ' }
                'numbertemplate' { $s = New-ScanSite -Name 'two' -SiteId $script:SiteB; $s.Template = 123; $s }
            }

            if ($Site -eq 'nourl') {
                $bad.Url = ''
            }

            { Invoke-TestScan -Site @($first, $bad) } | Should -Throw -ExpectedMessage $Message
        }

        It 'reads a group ID that says there is no group, or a group however it is written: <Name>' -ForEach @(
            @{ Name = 'null'; GroupId = $null; HasGroup = $false }
            @{ Name = 'empty'; GroupId = ''; HasGroup = $false }
            @{ Name = 'spaces'; GroupId = '   '; HasGroup = $false }
            @{ Name = 'zeros'; GroupId = '00000000-0000-0000-0000-000000000000'; HasGroup = $false }
            @{ Name = 'zeros in braces'; GroupId = '{00000000-0000-0000-0000-000000000000}'; HasGroup = $false }
            @{ Name = 'a GUID in capitals'; GroupId = '11111111-1111-1111-1111-111111111111'.ToUpperInvariant(); HasGroup = $true }
            @{ Name = 'a GUID in braces'; GroupId = '{11111111-1111-1111-1111-111111111111}'; HasGroup = $true }
            @{ Name = 'a GUID without hyphens'; GroupId = '11111111111111111111111111111111'; HasGroup = $true }
        ) {
            $site = New-ScanSite -GroupId $GroupId
            $teams = New-TestReport -Kind Teams -ById @{ $script:GroupA = (Get-TestDate '2026-10-20') }

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Report @($script:QuietReport, $teams)).Rows[0]

            if ($HasGroup) {
                $row.GroupId | Should -BeExactly $script:GroupA
                $row.Verdict | Should -BeExactly 'SKIP-RECENT-ACTIVITY'
            }
            else {
                $row.GroupId | Should -BeExactly ''
                $row.Verdict | Should -BeExactly 'DELETE-SITE'
            }
        }

        It 'reads the template without the spaces around it, so that a protected template with spaces is still protected' {
            $site = New-ScanSite -Template ' APPCATALOG#0 '

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)).Rows[0]

            $row.Verdict | Should -BeExactly 'SKIP-PROTECTED'
            $row.Template | Should -BeExactly 'APPCATALOG#0'
        }

        It 'stops on a record that is empty' {
            { Invoke-TestScan -Site @((New-ScanSite), $null) } | Should -Throw -ExpectedMessage '*record 2*empty*'
        }

        It 'stops on a content change that is neither a date nor a text: <Name>' -ForEach @(
            @{ Name = 'a number'; Value = 12345 }
            @{ Name = 'a boolean'; Value = $true }
        ) {
            $bad = New-ScanSite -Name 'two' -Modified $Value

            { Invoke-TestScan -Site @($bad) } | Should -Throw -ExpectedMessage '*sites/two*LastContentModified*is not a date*'
        }

        It 'reads a content change that is a blank text as no date' -ForEach @(
            @{ Value = '' }
            @{ Value = '   ' }
        ) {
            $site = New-ScanSite -Modified $Value

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)).Rows[0]

            $row.ContentModified | Should -BeNullOrEmpty
            $row.Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'accepts a content change as a date, with an offset, or as ISO text' -ForEach @(
            @{ Name = 'a UTC date'; Value = [System.DateTime]::new(2026, 10, 20, 0, 0, 0, [System.DateTimeKind]::Utc) }
            @{ Name = 'a date and offset'; Value = [System.DateTimeOffset]::new(2026, 10, 20, 2, 0, 0, [System.TimeSpan]::FromHours(2)) }
            @{ Name = 'ISO text'; Value = '2026-10-20T00:00:00Z' }
        ) {
            $site = New-ScanSite -Modified $Value

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site)).Rows[0]

            $row.ContentModified | Should -Be (Get-TestDate '2026-10-20')
            $row.Verdict | Should -BeExactly 'SKIP-RECENT-ACTIVITY'
        }

        It 'stops when the settings lack what the Scan needs: <Missing>' -ForEach @(
            @{ Missing = 'Scan.LockStates' }
            @{ Missing = 'Scan.InactiveDays' }
            @{ Missing = 'TenantName' }
            @{ Missing = 'AcceptedLockStates' }
            @{ Missing = 'MinLockedDays' }
            @{ Missing = 'DeleteMaxSizeGB' }
        ) {
            $setting = New-ScanSetting
            if ($Missing -like 'Scan.*') {
                $setting.Scan.PSObject.Properties.Remove($Missing.Substring(5))
            }
            else {
                $setting.PSObject.Properties.Remove($Missing)
            }

            { Invoke-TestScan -Site (New-ScanSite) -Setting $setting } | Should -Throw -ExpectedMessage "*$Missing*"
        }

        It 'stops when no activity report was given: nothing could say that a site is inactive' {
            { Invoke-TestScan -Site (New-ScanSite) -Report @() } | Should -Throw -ExpectedMessage '*activity report*'
        }

        It 'stops on a report of a kind that the Scan does not read' {
            $other = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null }
            $other.Kind = 'Exchange'

            { Invoke-TestScan -Site (New-ScanSite) -Report @($other) } | Should -Throw -ExpectedMessage '*Exchange*'
        }

        It 'stops when the Scan lists no lock state, because it would list no site' {
            { Invoke-TestScan -Site (New-ScanSite) -Setting (New-ScanSetting -LockStates @()) } | Should -Throw -ExpectedMessage '*Scan.LockStates*no lock state*'
        }

        It 'stops when two reports of the same kind were given' {
            $one = New-TestReport -Kind SharePoint -ById @{ $script:SiteA = $null }
            $two = New-TestReport -Kind SharePoint -ById @{ $script:SiteB = $null }

            { Invoke-TestScan -Site (New-ScanSite) -Report @($one, $two) } | Should -Throw -ExpectedMessage '*SharePoint*twice*'
        }
    }

    Context 'The time of the run' {
        It 'puts the time of the run, in UTC, on every row, whatever the kind of the date that it is given' {
            $local = [System.DateTime]::SpecifyKind([System.DateTime]::new(2026, 10, 29, 9, 0, 0), [System.DateTimeKind]::Local)
            $site = New-ScanSite

            $row = (Invoke-TestScan -Site $site -LockIndex (New-OldLock -Site $site) -Now $local).Rows[0]

            $row.GeneratedOn | Should -Be $local.ToUniversalTime()
            $row.GeneratedOn.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }
    }

    Context 'The report that it feeds' {
        It 'sends its rows straight to the report writer, and the file says what the rows say' {
            $sites = @(
                (New-ScanSite -Name 'one' -SiteId $script:SiteA)
                (New-ScanSite -Name 'two' -SiteId $script:SiteB -GroupId '' -Size 5000)
                (New-ScanSite -Name 'three' -SiteId '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708' -Title '=HYPERLINK("x")')
            )
            $entries = foreach ($s in $sites[0..1]) { @{ Url = $s.Url; SiteId = $s.SiteId; LockedOn = $script:Old } }
            $folder = Join-Path -Path $TestDrive -ChildPath 'reports'
            $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }
            $parameters = @{
                Setting = (New-ScanSetting); ActivityReport = @($script:QuietReport); LockDateIndex = (New-LockIndex -Entry $entries)
                ExclusionIndex = (New-ExclusionIndex); Summary = $summary; Now = $script:Now
            }

            $path = & $script:Module { param($s, $p, $f) $s | ConvertTo-SPSLifecycleScanRow @p | Export-SPSLifecycleReport -OutputFolder $f -Delimiter ',' -GeneratedOn $p.Now } $sites $parameters $folder
            $lines = @(Import-Csv -LiteralPath $path)

            $lines | Should -HaveCount 3
            @($lines.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'ARCHIVE', 'SKIP-NO-LOCK-DATE')
            @($lines.SuggestedAction) | Should -Be @('Delete', 'Archive', '')
            @($lines.Decision) | Should -Be @('', '', '')
            @($lines.GeneratedOn | Select-Object -Unique) | Should -Be @('20261029T080000Z')
            $lines[2].Title | Should -BeExactly "'=HYPERLINK(`"x`")"
            $summary.SitesListed | Should -Be 3
        }
    }

    Context 'With the settings and the files that a run reads' {
        It 'gives the verdicts that the files say, from the real settings, importers and indexes' {
            $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $folder -ItemType Directory
            $idA = $script:SiteA
            $idB = $script:SiteB
            $idC = '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708'
            $idD = '4d0a8b63-9c2f-4e7b-a01f-32d5e6f70819'
            $idE = '5e1b9c74-ad30-4f8c-b120-43e6f708192a'
            $idOther = '6f2cad85-be41-4a9d-c231-54f7091a2b3b'
            $usage = @(
                'Report Refresh Date,Site Id,Site URL,Owner Display Name,Is Deleted,Last Activity Date,Root Web Template,Report Period'
                "2026-10-27,$idA,https://contoso.sharepoint.com/sites/a,x,False,,Group,180"
                "2026-10-27,$idB,https://contoso.sharepoint.com/sites/b,x,False,,Group,180"
                "2026-10-27,$idOther,https://contoso.sharepoint.com/sites/c,x,False,2019-01-01,Group,180"
                "2026-10-27,$idD,https://contoso.sharepoint.com/sites/d,x,False,2025-01-01,Group,180"
                "2026-10-27,$idE,https://contoso.sharepoint.com/sites/e,x,False,,Group,180"
            ) -join "`r`n"
            $teams = "Report Refresh Date,Team Id,Last Activity Date,Report Period`r`n2026-10-27,$($script:GroupB),2026-10-20,180`r`n"
            $lots = "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$idA,2025-01-01`r`nhttps://contoso.sharepoint.com/sites/b,$idB,2025-01-01`r`nhttps://contoso.sharepoint.com/sites/c,$idC,2025-01-01`r`nhttps://contoso.sharepoint.com/sites/d,$idD,2025-01-01`r`n"
            $exclusions = "Url`r`nhttps://contoso.sharepoint.com/sites/B/`r`n"
            $files = @{ 'usage.csv' = $usage; 'teams.csv' = $teams; 'lots.csv' = $lots; 'exclusions.csv' = $exclusions }
            foreach ($name in $files.Keys) {
                [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath $name), $files[$name], [System.Text.UTF8Encoding]::new($true))
            }

            $configPath = Join-Path -Path $folder -ChildPath 'settings.psd1'
            Set-Content -LiteralPath $configPath -Encoding utf8 -Value @"
@{
    TenantName     = 'Contoso'
    ClientId       = '11111111-2222-3333-4444-555555555555'
    LockDateFiles  = @('lots.csv')
    ExclusionFiles = @('exclusions.csv')
    Scan           = @{ SharePointUsageReport = 'usage.csv'; TeamsActivityReport = 'teams.csv' }
}
"@
            $setting = Get-SPSLifecycleSetting -Path $configPath -Phase Scan
            $sites = @(
                (New-ScanSite -Name 'a' -SiteId $idA -GroupId '')
                (New-ScanSite -Name 'b' -SiteId $idB -GroupId '')
                (New-ScanSite -Name 'c' -SiteId $idC -GroupId '')
                (New-ScanSite -Name 'd' -SiteId $idD -GroupId $script:GroupB)
                (New-ScanSite -Name 'e' -SiteId $idE -GroupId '')
            )
            $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }

            $rows = @(& $script:Module {
                    param($sites, $setting, $summary, $now)
                    $reports = @(
                        (Import-SPSLifecycleActivityReport -Path $setting.Scan.SharePointUsageReport -Kind SharePoint)
                        (Import-SPSLifecycleActivityReport -Path $setting.Scan.TeamsActivityReport -Kind Teams)
                    )
                    $locks = Get-SPSLifecycleLockDateIndex -LockDateFile $setting.LockDateFiles -LockJournal $setting.LockJournal
                    $excluded = Get-SPSLifecycleExclusionIndex -ExclusionFile $setting.ExclusionFiles
                    $sites | ConvertTo-SPSLifecycleScanRow -Setting $setting -ActivityReport $reports -LockDateIndex $locks -ExclusionIndex $excluded -Summary $summary -Now $now
                } $sites $setting $summary $script:Now)

            @($rows.Verdict) | Should -Be @('DELETE-SITE', 'SKIP-EXCLUDED', 'REVIEW-NO-ACTIVITY-ROW', 'SKIP-RECENT-ACTIVITY', 'SKIP-NO-LOCK-DATE')
            $rows[0].LockedOnSource | Should -BeExactly 'lots.csv'
            $rows[3].LastActivitySource | Should -BeExactly 'Teams'
            $rows[3].SharePointActivity | Should -Be (Get-TestDate '2025-01-01')
            $summary.SitesListed | Should -Be 5
        }
    }

    Context 'Size' {
        BeforeAll {
            # A listing of made-up sites (fictitious addresses and GUIDs), with the reports and the lock dates that go with it.
            # What happens to each site follows from its number, so that the counts are known without running the code:
            # a lock date when the number is not a multiple of 7 (otherwise SKIP-NO-LOCK-DATE), a recent activity when it is a
            # multiple of 4 (SharePoint) or, for a site that has a group, of 5 (Teams), a group unless it is a multiple of 3,
            # and a large size when it is a multiple of 10.
            function script:New-SyntheticListing {
                param([int]$Count)

                $recentSharePoint = Get-TestDate '2026-10-01'
                $recentTeams = Get-TestDate '2026-09-01'
                $sites = [System.Collections.Generic.List[System.Object]]::new($Count)
                $sharePointById = @{}
                $teamsById = @{}
                $entries = [System.Collections.Generic.List[System.Object]]::new()
                $expected = @{}
                for ($i = 1; $i -le $Count; $i++) {
                    $id = '{0:x8}-0000-4000-8000-{1:x12}' -f $i, $i
                    $group = if ($i % 3 -eq 0) { '' } else { '{0:x8}-1111-4111-8111-{1:x12}' -f $i, $i }
                    $url = "https://contoso.sharepoint.com/sites/site$i"
                    $size = if ($i % 10 -eq 0) { 5000 } else { 100 }
                    $sharePointById[$id] = if ($i % 4 -eq 0) { $recentSharePoint } else { $null }
                    if ($group) {
                        $teamsById[$group] = if ($i % 5 -eq 0) { $recentTeams } else { $null }
                    }

                    if ($i % 7 -ne 0) {
                        $entries.Add([PSCustomObject]@{ Url = $url; UrlKey = $url; SiteId = $id; LockedOn = $script:Old; Source = 'lot1.csv' })
                    }

                    $verdict = if ($i % 7 -eq 0) { 'SKIP-NO-LOCK-DATE' }
                    elseif ($i % 4 -eq 0 -or ($group -and $i % 5 -eq 0)) { 'SKIP-RECENT-ACTIVITY' }
                    elseif ($i % 10 -eq 0) { 'ARCHIVE' }
                    elseif ($group) { 'DELETE-VIA-GROUP' }
                    else { 'DELETE-SITE' }
                    $expected[$verdict] = 1 + [int]$expected[$verdict]

                    $sites.Add((New-ScanSite -Name "site$i" -SiteId $id -GroupId $group -Size $size))
                }

                $import = [PSCustomObject]@{ Name = 'lot1.csv'; RowCount = $entries.Count; Entries = $entries.ToArray() }
                [PSCustomObject]@{
                    Sites     = $sites
                    Reports   = @((New-TestReport -Kind SharePoint -ById $sharePointById), (New-TestReport -Kind Teams -ById $teamsById))
                    LockIndex = & $script:Module { param($i) Merge-SPSLifecycleLockDate -Import @($i) } $import
                    Expected  = $expected
                }
            }

            function script:Measure-SyntheticScan {
                param([int]$Count)

                $listing = New-SyntheticListing -Count $Count
                $summary = & $script:Module { Initialize-SPSLifecycleScanSummary }
                $parameters = @{ Setting = (New-ScanSetting); ActivityReport = $listing.Reports; LockDateIndex = $listing.LockIndex; ExclusionIndex = (New-ExclusionIndex); Summary = $summary; Now = $script:Now }
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                & $script:Module { param($s, $p) $null = $s | ConvertTo-SPSLifecycleScanRow @p } $listing.Sites $parameters
                [PSCustomObject]@{ Seconds = $watch.Elapsed.TotalSeconds; Summary = $summary; Expected = $listing.Expected }
            }
        }

        # On Windows, PowerShell copies the string arguments of every .NET method call into a log message for AMSI (D9), so a
        # function that gives a whole file, or a whole index, to a method for each site would be quadratic there: this test
        # runs two sizes and compares the times, so that a time that grows with the square of the size is a failure after a
        # minute, on any system, whatever the speed of the machine.
        It 'gives each site of a large listing the verdict that the rules give, in a time that grows with the size of the listing' -Tag 'Slow' {
            # The first run pays for the compilation of the code and the first allocations: it is not timed, or the small run
            # would look slower than it is, and the ratio would hide a time that grows too fast.
            $null = Measure-SyntheticScan -Count 500
            $small = Measure-SyntheticScan -Count 5000
            $large = Measure-SyntheticScan -Count 20000

            $large.Summary.SitesRead | Should -Be 20000
            $large.Summary.SitesListed | Should -Be 20000
            foreach ($verdict in $large.Expected.Keys) {
                $large.Summary.ByVerdict[$verdict] | Should -Be $large.Expected[$verdict] -Because "the verdict $verdict"
            }

            $large.Summary.ByVerdict.Count | Should -Be $large.Expected.Count
            $large.Seconds | Should -BeLessThan 120
            ($large.Seconds / $small.Seconds) | Should -BeLessThan 10
        }
    }
}
