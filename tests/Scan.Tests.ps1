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
