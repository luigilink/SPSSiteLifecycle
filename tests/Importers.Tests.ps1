BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    function script:Write-TestCsv {
        param([string]$Name, [string]$Text, [string]$Encoding = 'utf8bom')
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        switch ($Encoding) {
            'utf8bom' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($true)) }
            'cp1252' { [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)) }
        }

        $path
    }

    function script:Import-TestLockDate {
        param([string]$Path, [string[]]$DateFormat = @())
        & $script:Module { param($p, $f) Import-SPSLifecycleLockDateList -Path $p -DateFormat $f } $Path $DateFormat
    }

    function script:Import-TestReport {
        param([string]$Path, [string]$Kind)
        & $script:Module { param($p, $k) Import-SPSLifecycleActivityReport -Path $p -Kind $k } $Path $Kind
    }

    $script:UsageHeader = 'Report Refresh Date,Site Id,Site URL,Owner Display Name,Is Deleted,Last Activity Date,Root Web Template,Report Period'
}

Describe 'Import-SPSLifecycleLockDateList' {
    It 'keeps the latest date when a site appears twice, whatever the spelling of the URL' {
        $path = Write-TestCsv -Name 'lock.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/Sales/,2025-03-01`r`nhttps://CONTOSO.sharepoint.com/sites/sales,2025-09-18`r`nhttps://contoso.sharepoint.com/sites/hr,2025-01-10`r`n"
        $list = Import-TestLockDate -Path $path

        $list.RowCount | Should -Be 3
        $list.Entries | Should -HaveCount 2
        $sales = $list.Entries | Where-Object { $_.UrlKey -eq 'https://contoso.sharepoint.com/sites/sales' }
        $sales.LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-09-18'
        $sales.Source | Should -Be 'lock.csv'
    }

    It 'keeps one entry for a site ID that has two URLs (a renamed site), with the latest date and the URL of that row' {
        $path = Write-TestCsv -Name 'renamed.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/old,A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64,2025-03-01`r`nhttps://contoso.sharepoint.com/sites/new,{a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64},2025-09-18`r`n"
        $list = Import-TestLockDate -Path $path

        $list.RowCount | Should -Be 2
        $list.Entries | Should -HaveCount 1
        $list.Entries[0].Url | Should -Be 'https://contoso.sharepoint.com/sites/new'
        $list.Entries[0].LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-09-18'
    }

    It 'keeps two entries for an address that two site IDs have used, because the second site is not the first' {
        $path = Write-TestCsv -Name 'reused.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/sales,A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64,2025-03-01`r`nhttps://contoso.sharepoint.com/sites/sales,0D7B4EBB-F68C-4F29-8529-5B46655D0C3C,2025-09-18`r`n"
        $list = Import-TestLockDate -Path $path

        $list.Entries | Should -HaveCount 2
        @($list.Entries.SiteId | Sort-Object) | Should -Be @('0d7b4ebb-f68c-4f29-8529-5b46655d0c3c', 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64')
    }

    It 'keeps a row that has a URL only next to a row that has a site ID, for the same address' {
        $path = Write-TestCsv -Name 'mixed.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/sales,,2025-03-01`r`nhttps://contoso.sharepoint.com/sites/sales,A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64,2025-09-18`r`n"
        $list = Import-TestLockDate -Path $path

        $list.Entries | Should -HaveCount 2
        @($list.Entries | Where-Object { -not $_.SiteId }).LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-03-01'
    }

    It 'ignores a row without a date' {
        $path = Write-TestCsv -Name 'nodate.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,`r`nhttps://contoso.sharepoint.com/sites/b,2025-09-18`r`n"
        $list = Import-TestLockDate -Path $path

        $list.Entries | Should -HaveCount 1
    }

    It 'reads the optional SiteId column' {
        $path = Write-TestCsv -Name 'siteid.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64},2025-09-18`r`n"
        $list = Import-TestLockDate -Path $path

        $list.Entries[0].SiteId | Should -Be 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    }

    It 'reads a French Excel file: semicolons, Windows-1252, dd/MM/yyyy' {
        $path = Write-TestCsv -Name 'fr.csv' -Encoding cp1252 -Text "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/équipe;18/09/2025`r`n"
        $list = Import-TestLockDate -Path $path -DateFormat 'dd/MM/yyyy'

        $list.Entries[0].LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-09-18'
        $list.Entries[0].Url | Should -Be 'https://contoso.sharepoint.com/sites/équipe'
    }

    It 'stops on a date that needs a format, and names the file and the column' {
        $path = Write-TestCsv -Name 'fr-dates.csv' -Text "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;18/09/2025`r`n"

        { Import-TestLockDate -Path $path } | Should -Throw -ExpectedMessage "*fr-dates.csv*LockedOn*'18/09/2025'*CsvDateFormats*"
    }

    It 'stops when the Url column does not hold URLs' {
        $path = Write-TestCsv -Name 'wrong.csv' -Text "Url,LockedOn`r`nSales team,2025-09-18`r`nHR team,2025-09-18`r`n"

        { Import-TestLockDate -Path $path } | Should -Throw -ExpectedMessage "*'Url' in wrong.csv*"
    }

    It 'stops when the LockedOn column is missing' {
        $path = Write-TestCsv -Name 'nolock.csv' -Text "Url,Title`r`nhttps://contoso.sharepoint.com/sites/a,x`r`n"

        { Import-TestLockDate -Path $path } | Should -Throw -ExpectedMessage '*LockedOn*'
    }
}

Describe 'Import-SPSLifecycleExclusionList' {
    It 'normalizes the URLs' {
        $path = Write-TestCsv -Name 'exclusions.csv' -Text "Url`r`nhttps://Contoso.sharepoint.com/sites/Keep/`r`nhttps://contoso.sharepoint.com/sites/other`r`n"
        $list = & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path

        $list.RowCount | Should -Be 2
        $list.Keys.ContainsKey('https://contoso.sharepoint.com/sites/keep') | Should -BeTrue
        $list.Keys.ContainsKey('https://contoso.sharepoint.com/sites/other') | Should -BeTrue
    }

    It 'stops when the Url column does not hold URLs' {
        $path = Write-TestCsv -Name 'badex.csv' -Text "Url`r`nSales`r`n"

        { & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path } | Should -Throw -ExpectedMessage '*badex.csv*not site URLs*'
    }

    It 'stops when a single row cannot be read, even among many good ones, and names it' {
        $good = 1..9 | ForEach-Object { "https://contoso.sharepoint.com/sites/keep$_" }
        $path = Write-TestCsv -Name 'one-bad.csv' -Text ("Url`r`n" + (($good + 'https:/contoso.sharepoint.com/sites/important') -join "`r`n") + "`r`n")

        { & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path } | Should -Throw -ExpectedMessage '*one-bad.csv*1 value*https:/contoso.sharepoint.com/sites/important*'
    }

    It 'stops on <Name>, which would leave sites unprotected' -ForEach @(
        @{ Name = 'an unterminated quote that swallows the next rows'; Text = "Url`r`n`"https://contoso.sharepoint.com/sites/keep1`r`nhttps://contoso.sharepoint.com/sites/keep2`r`n" }
        @{ Name = 'an address with a space in it'; Text = "Url`r`nhttps://contoso.sharepoint.com/sites/my team`r`n" }
        @{ Name = 'a file address'; Text = "Url`r`nfile:///etc/passwd`r`n" }
        @{ Name = 'an ftp address'; Text = "Url`r`nftp://contoso.sharepoint.com/sites/a`r`n" }
        @{ Name = 'an address without a host'; Text = "Url`r`nhttps:///sites/a`r`n" }
        @{ Name = 'two addresses in one cell'; Text = "Url`r`nhttps://contoso.sharepoint.com/sites/a https://contoso.sharepoint.com/sites/b`r`n" }
        @{ Name = 'a server-relative path'; Text = "Url`r`n/sites/keep`r`n" }
    ) {
        $path = Write-TestCsv -Name 'strict.csv' -Text $Text

        { & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path } | Should -Throw -ExpectedMessage '*strict.csv*not site URLs*'
    }

    It 'reads the addresses of an exclusion list, and ignores the blank cells' {
        $path = Write-TestCsv -Name 'blank.csv' -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n`"`"`r`n   `r`nhttp://contoso.sharepoint.com/sites/b`r`nhttps://contoso.sharepoint.com:443/sites/c/`r`n"
        $list = & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path

        $list.Keys.Count | Should -Be 3
        $list.Keys.ContainsKey('https://contoso.sharepoint.com/sites/c') | Should -BeTrue
    }

    It 'accepts a list that has no row' {
        $path = Write-TestCsv -Name 'norows.csv' -Text "Url`r`n"
        $list = & $script:Module { param($p) Import-SPSLifecycleExclusionList -Path $p } $path

        $list.Keys.Count | Should -Be 0
    }
}

Describe 'Import-SPSLifecycleActivityReport' {
    Context 'SharePoint site usage report' {
        It 'indexes the rows by site ID and by URL, and keeps the latest date' {
            $text = "$script:UsageHeader`r`n" +
            "2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,False,2026-08-01,Group,180`r`n" +
            "2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,False,2026-09-15,Group,180`r`n" +
            "2026-10-26,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,https://contoso.sharepoint.com/sites/b,Owner B,False,,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'usage.csv' -Text $text) -Kind SharePoint

            $report.RowCount | Should -Be 3
            $report.ById['a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'].ToString('yyyy-MM-dd') | Should -Be '2026-09-15'
            $report.ByUrl['https://contoso.sharepoint.com/sites/a'].ToString('yyyy-MM-dd') | Should -Be '2026-09-15'
            $report.ById.ContainsKey('0d7b4ebb-f68c-4f29-8529-5b46655d0c3c') | Should -BeTrue
            $report.ById['0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'] | Should -BeNullOrEmpty
            $report.ReportPeriod | Should -Be '180'
            $report.RefreshDate.ToString('yyyy-MM-dd') | Should -Be '2026-10-26'
        }

        It 'matches by site ID when the Site URL is empty (BYOK, Customer Lockbox)' {
            $text = "$script:UsageHeader`r`n2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,,Owner A,False,2026-09-15,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'nourl.csv' -Text $text) -Kind SharePoint

            $report.ById.Count | Should -Be 1
            $report.ByUrl.Count | Should -Be 0
        }

        It 'stops when the names are concealed, and says how to turn it off' {
            $text = "$script:UsageHeader`r`n2026-10-26,00000000-0000-0000-0000-000000000000,,Owner A,False,2026-09-15,Group,180`r`n"

            { Import-TestReport -Path (Write-TestCsv -Name 'concealed.csv' -Text $text) -Kind SharePoint } | Should -Throw -ExpectedMessage '*concealed*'
        }

        It 'ignores the rows of deleted sites' {
            $text = "$script:UsageHeader`r`n" +
            "2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,True,2026-09-15,Group,180`r`n" +
            "2026-10-26,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,https://contoso.sharepoint.com/sites/b,Owner B,False,2026-09-15,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'deleted.csv' -Text $text) -Kind SharePoint

            $report.DeletedRowCount | Should -Be 1
            $report.ById.Count | Should -Be 1
            $report.ById.ContainsKey('a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64') | Should -BeFalse
        }

        It 'reads a report saved by French Excel (semicolons, Windows-1252)' {
            $text = ($script:UsageHeader -replace ',', ';') + "`r`n2026-10-26;a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64;https://contoso.sharepoint.com/sites/équipe;Édith;FAUX;2026-09-15;Group;180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'fr-usage.csv' -Encoding cp1252 -Text $text) -Kind SharePoint

            $report.ByUrl['https://contoso.sharepoint.com/sites/équipe'].ToString('yyyy-MM-dd') | Should -Be '2026-09-15'
        }

        It 'stops when the Site URL column does not hold URLs' {
            $text = "$script:UsageHeader`r`n2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,Sales,Owner A,False,2026-09-15,Group,180`r`n"

            { Import-TestReport -Path (Write-TestCsv -Name 'wrongurl.csv' -Text $text) -Kind SharePoint } | Should -Throw -ExpectedMessage "*'Site URL' in wrongurl.csv*"
        }

        It 'reads the dates when the name of the column has a space around it: <Name>' -ForEach @(
            @{ Name = 'quoted'; Column = '"Last Activity Date "' }
            @{ Name = 'unquoted'; Column = 'Last Activity Date ' }
        ) {
            $header = $script:UsageHeader.Replace('Last Activity Date', $Column)
            $text = "$header`r`n2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,False,2026-10-28,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'spaces.csv' -Text $text) -Kind SharePoint

            $report.ById['a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'].ToString('yyyy-MM-dd') | Should -Be '2026-10-28'
        }

        It 'still ignores the deleted rows when the name of the Is Deleted column has a space around it' {
            $header = $script:UsageHeader.Replace('Is Deleted', '"Is Deleted "')
            $text = "$header`r`n" +
            "2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,True,2026-10-28,Group,180`r`n" +
            "2026-10-26,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,https://contoso.sharepoint.com/sites/b,Owner B,False,2026-10-28,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'spaces2.csv' -Text $text) -Kind SharePoint

            $report.DeletedRowCount | Should -Be 1
            $report.ById.Count | Should -Be 1
        }

        It 'ignores a deleted row written <Name>, and keeps a live one' -ForEach @(
            @{ Name = 'by a French spreadsheet'; Deleted = 'VRAI'; Live = 'FAUX' }
            @{ Name = 'by a German spreadsheet'; Deleted = 'WAHR'; Live = 'FALSCH' }
            @{ Name = 'by a Spanish spreadsheet'; Deleted = 'VERDADERO'; Live = 'FALSO' }
            @{ Name = 'in English'; Deleted = 'True'; Live = 'False' }
            @{ Name = 'as a number'; Deleted = '1'; Live = '0' }
        ) {
            $text = "$script:UsageHeader`r`n" +
            "2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,$Deleted,2026-10-28,Group,180`r`n" +
            "2026-10-26,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,https://contoso.sharepoint.com/sites/b,Owner B,$Live,2026-10-28,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'booleans.csv' -Text $text) -Kind SharePoint

            $report.DeletedRowCount | Should -Be 1
            $report.ById.Count | Should -Be 1
            $report.ById.ContainsKey('0d7b4ebb-f68c-4f29-8529-5b46655d0c3c') | Should -BeTrue
        }

        It 'ignores a deleted group written by a German spreadsheet' {
            $text = "Group Id,Last Activity Date,Is Deleted`r`n11111111-1111-1111-1111-111111111111,2025-01-01,WAHR`r`n22222222-2222-2222-2222-222222222222,2025-01-02,FALSCH`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'groups-de.csv' -Text $text) -Kind Groups

            $report.DeletedRowCount | Should -Be 1
            $report.ById.Count | Should -Be 1
        }

        It 'stops on an Is Deleted value that is neither true nor false, and names the file, the column and the value' {
            $text = "$script:UsageHeader`r`n2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,maybe,2026-10-28,Group,180`r`n"

            { Import-TestReport -Path (Write-TestCsv -Name 'maybe.csv' -Text $text) -Kind SharePoint } | Should -Throw -ExpectedMessage "*maybe.csv*Is Deleted*'maybe'*"
        }

        It 'reads a row whose Is Deleted cell is blank as a live row' {
            $text = "$script:UsageHeader`r`n2026-10-26,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,https://contoso.sharepoint.com/sites/a,Owner A,,2026-10-28,Group,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'blank-flag.csv' -Text $text) -Kind SharePoint

            $report.DeletedRowCount | Should -Be 0
            $report.ById.Count | Should -Be 1
        }

        It 'stops on an Is Deleted column that only looks like it, because the deleted rows would be read as live: <Name>' -ForEach @(
            @{ Name = 'a soft hyphen'; Header = "Is$([char]0xAD) Deleted" }
            @{ Name = 'no space'; Header = 'IsDeleted' }
            @{ Name = 'an underscore'; Header = 'Is_Deleted' }
        ) {
            $text = "Report Refresh Date,Site Id,Site URL,Owner Display Name,$Header,Last Activity Date,Root Web Template,Report Period`r`n2026-10-27,A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64,https://contoso.sharepoint.com/sites/a,x,True,2026-01-02,Team site,180`r`n"
            $path = Write-TestCsv -Name 'lookalike.csv' -Text $text

            { Import-TestReport -Path $path -Kind SharePoint } | Should -Throw -ExpectedMessage "*looks like 'Is Deleted'*"
        }

        It 'stops when a mandatory column is missing' {
            { Import-TestReport -Path (Write-TestCsv -Name 'nocol.csv' -Text "Site Id,Owner`r`na6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,x`r`n") -Kind SharePoint } | Should -Throw -ExpectedMessage '*Last Activity Date*'
        }

        It 'stops on a report without a row' {
            { Import-TestReport -Path (Write-TestCsv -Name 'norow.csv' -Text "$script:UsageHeader`r`n") -Kind SharePoint } | Should -Throw -ExpectedMessage '*has no row*'
        }
    }

    Context 'Teams and Microsoft 365 groups reports' {
        It 'indexes the Teams report by Team ID' {
            $text = "Report Refresh Date,Team Name,Team Id,Last Activity Date,Report Period`r`n2026-10-26,Sales,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2026-10-20,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'teams.csv' -Text $text) -Kind Teams

            $report.ById['a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'].ToString('yyyy-MM-dd') | Should -Be '2026-10-20'
            $report.ByUrl.Count | Should -Be 0
        }

        It 'indexes the groups report by Group ID and ignores the deleted groups' {
            $text = "Report Refresh Date,Group Display Name,Is Deleted,Last Activity Date,Group Id,Report Period`r`n" +
            "2026-10-26,Sales,False,2026-10-20,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,180`r`n" +
            "2026-10-26,Old,True,2026-10-21,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,180`r`n"
            $report = Import-TestReport -Path (Write-TestCsv -Name 'groups.csv' -Text $text) -Kind Groups

            $report.ById.Count | Should -Be 1
            $report.DeletedRowCount | Should -Be 1
        }

        It 'stops when the ID column holds no GUID' {
            $text = "Report Refresh Date,Team Name,Team Id,Last Activity Date,Report Period`r`n2026-10-26,Sales,,2026-10-20,180`r`n"

            { Import-TestReport -Path (Write-TestCsv -Name 'noid.csv' -Text $text) -Kind Teams } | Should -Throw -ExpectedMessage "*'Team Id'*"
        }
    }
}
