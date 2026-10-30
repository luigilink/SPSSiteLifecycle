BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Run = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'

    function script:New-ActReportRow {
        param([hashtable]$Override = @{})

        $values = [ordered]@{
            Line        = 2
            Url         = 'https://contoso.sharepoint.com/sites/a'
            SiteId      = $script:SiteA
            Decision    = 'Delete'
            Verdict     = 'DELETE-VIA-GROUP'
            Outcome     = 'Done'
            Detail      = 'The group was deleted.'
            ProcessedOn = [System.DateTime]::new(2026, 10, 30, 9, 5, 7, [System.DateTimeKind]::Utc)
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    function script:New-TestActReport {
        param([string]$Delimiter = ',', [string]$Folder = (Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))))

        $path = & $script:Module { param($f, $d, $g) Initialize-SPSLifecycleActReport -OutputFolder $f -Delimiter $d -GeneratedOn $g } $Folder ([System.Char]$Delimiter) $script:Run
        [PSCustomObject]@{ Path = $path; Folder = $Folder; Delimiter = [System.Char]$Delimiter }
    }

    function script:Add-TestActRow {
        param($Report, $Row)
        & $script:Module { param($p, $r, $d) Add-SPSLifecycleActReportRow -Path $p -Row $r -Delimiter $d } $Report.Path $Row $Report.Delimiter
    }
}

Describe 'Get-SPSLifecycleActReportColumn' {
    It 'lists the columns of the Act report, in their order, with their kind' {
        $columns = @(& $script:Module { Get-SPSLifecycleActReportColumn })

        ($columns | ForEach-Object { "$($_.Name):$($_.Kind)" }) | Should -Be @(
            'Line:WholeNumber', 'Url:Text', 'SiteId:Guid', 'Decision:Text', 'Verdict:Text', 'Outcome:Text', 'Detail:Text', 'ProcessedOn:Run')
    }

    It 'gives a description to each column' {
        foreach ($column in @(& $script:Module { Get-SPSLifecycleActReportColumn })) {
            $column.Description | Should -Not -BeNullOrEmpty -Because $column.Name
        }
    }
}

Describe 'Initialize-SPSLifecycleActReport' {
    It 'creates the report in the output folder, which it creates, with a header, a byte order mark and Windows line endings' {
        $report = New-TestActReport

        $report.Path | Should -BeExactly (Join-Path -Path $report.Folder -ChildPath 'act-20261030T090000Z.csv')
        $bytes = [System.IO.File]::ReadAllBytes($report.Path)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) | Should -BeExactly "Line,Url,SiteId,Decision,Verdict,Outcome,Detail,ProcessedOn`r`n"
    }

    It 'writes the delimiter that it is given' {
        $report = New-TestActReport -Delimiter ';'

        (Get-Content -LiteralPath $report.Path -TotalCount 1).TrimStart([char]0xFEFF) | Should -BeExactly 'Line;Url;SiteId;Decision;Verdict;Outcome;Detail;ProcessedOn'
    }

    It 'never replaces a report that exists: it is the record of what was done' {
        $report = New-TestActReport
        Add-TestActRow -Report $report -Row (New-ActReportRow)

        { New-TestActReport -Folder $report.Folder } | Should -Throw -ExpectedMessage '*already exists*never overwritten*'

        @(Get-Content -LiteralPath $report.Path) | Should -HaveCount 2
    }
}

Describe 'Add-SPSLifecycleActReportRow' {
    It 'writes one line for a row, with each value in the form of its column' {
        $report = New-TestActReport

        Add-TestActRow -Report $report -Row (New-ActReportRow)

        $lines = @(Get-Content -LiteralPath $report.Path)
        $lines | Should -HaveCount 2
        $lines[1] | Should -BeExactly "2,https://contoso.sharepoint.com/sites/a,$script:SiteA,Delete,DELETE-VIA-GROUP,Done,The group was deleted.,20261030T090507Z"
    }

    It 'adds each row at the end, in order, and the file is a CSV that a spreadsheet reads' {
        $report = New-TestActReport
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Line = 2; Outcome = 'Done' })
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Line = 3; Outcome = 'Failed'; Detail = 'Access denied.' })
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Line = 4; Decision = 'Lock'; Verdict = 'SKIP-LOCK-STATE'; Outcome = 'Skipped'; Detail = '' })

        $rows = @(Import-Csv -LiteralPath $report.Path)

        $rows | Should -HaveCount 3
        @($rows.Line) | Should -Be @('2', '3', '4')
        @($rows.Outcome) | Should -Be @('Done', 'Failed', 'Skipped')
        $rows[1].Detail | Should -BeExactly 'Access denied.'
        $rows[2].Detail | Should -BeExactly ''
    }

    It 'quotes a value that holds the delimiter, a quote or a line break, and keeps it whole' {
        $report = New-TestActReport
        $detail = "The site 'a', is gone; it said `"no`"`r`nand then stopped."
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Detail = $detail })

        @(Import-Csv -LiteralPath $report.Path)[0].Detail | Should -BeExactly $detail
    }

    It 'writes the delimiter that the report was made with' {
        $report = New-TestActReport -Delimiter ';'
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Detail = 'one, two; three' })

        $line = @(Get-Content -LiteralPath $report.Path)[1]

        $line | Should -BeExactly "2;https://contoso.sharepoint.com/sites/a;$script:SiteA;Delete;DELETE-VIA-GROUP;Done;`"one, two; three`";20261030T090507Z"
    }

    It 'neutralizes a text that a spreadsheet would read as a formula: <Name>' -ForEach @(
        @{ Name = 'in the detail'; Field = 'Detail'; Value = '=HYPERLINK("http://example.invalid","x")' }
        @{ Name = 'in the address'; Field = 'Url'; Value = '=1+1' }
        @{ Name = 'with a plus'; Field = 'Detail'; Value = '+cmd' }
        @{ Name = 'with an at sign'; Field = 'Detail'; Value = '@SUM(A1)' }
    ) {
        $report = New-TestActReport
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ $Field = $Value })

        $cell = @(Import-Csv -LiteralPath $report.Path)[0].$Field

        $cell | Should -Not -BeLike "$($Value.Substring(0, 1))*"
        $cell | Should -BeLike "*$($Value.Substring(1))"
    }

    It 'keeps the letters that are not ASCII' {
        $report = New-TestActReport
        Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Url = 'https://contoso.sharepoint.com/sites/%C3%A9quipe'; Detail = "Le site de l'équipe a été supprimé." })

        $bytes = [System.IO.File]::ReadAllBytes($report.Path)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        @(Import-Csv -LiteralPath $report.Path -Encoding utf8)[0].Detail | Should -BeExactly "Le site de l'équipe a été supprimé."
        $marks = 0
        for ($i = 0; $i -lt $bytes.Length - 2; $i++) {
            if ($bytes[$i] -eq 0xEF -and $bytes[$i + 1] -eq 0xBB -and $bytes[$i + 2] -eq 0xBF) { $marks++ }
        }

        $marks | Should -Be 1
    }

    It 'does not keep the file open: it can be moved right after a row' {
        $report = New-TestActReport
        Add-TestActRow -Report $report -Row (New-ActReportRow)

        { Move-Item -LiteralPath $report.Path -Destination "$($report.Path).moved" -ErrorAction Stop } | Should -Not -Throw
    }

    It 'accepts every outcome of a row: <Outcome>' -ForEach @(
        @{ Outcome = 'Done' }
        @{ Outcome = 'Failed' }
        @{ Outcome = 'WouldDo' }
        @{ Outcome = 'Skipped' }
        @{ Outcome = 'Review' }
        @{ Outcome = 'ReadError' }
        @{ Outcome = 'NotRun' }
    ) {
        $report = New-TestActReport

        { Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Outcome = $Outcome }) } | Should -Not -Throw
    }

    It 'refuses an outcome that is not one of the seven, and writes nothing: <Outcome>' -ForEach @(
        @{ Outcome = 'done' }
        @{ Outcome = 'Deleted' }
        @{ Outcome = '' }
        @{ Outcome = $null }
    ) {
        $report = New-TestActReport

        { Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ Outcome = $Outcome }) } | Should -Throw -ExpectedMessage '*Outcome*Done, Failed, WouldDo, Skipped, Review, ReadError or NotRun*'

        @(Get-Content -LiteralPath $report.Path) | Should -HaveCount 1
    }

    It 'refuses to add to a report that is not there, and does not create one without its header' {
        $path = Join-Path -Path $TestDrive -ChildPath 'no-such-folder/act.csv'

        { & $script:Module { param($p, $r) Add-SPSLifecycleActReportRow -Path $p -Row $r -Delimiter ',' } $path (New-ActReportRow) } | Should -Throw -ExpectedMessage '*report*not there*'

        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'says which row and which column cannot be written, and writes nothing of the row' {
        $report = New-TestActReport

        { Add-TestActRow -Report $report -Row (New-ActReportRow -Override @{ ProcessedOn = 'yesterday' }) } | Should -Throw -ExpectedMessage '*line 2*ProcessedOn*'

        @(Get-Content -LiteralPath $report.Path) | Should -HaveCount 1
    }
}
