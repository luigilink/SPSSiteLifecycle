BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:SiteC = '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708'
    $script:Generated = '20261029T090000Z'
    $script:Header = 'Url,Verdict,SuggestedAction,Decision,SiteId,Title,GeneratedOn'

    function script:Write-TestFile {
        param([string]$Name, [string]$Text, [string]$Encoding = 'utf8bom')
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        switch ($Encoding) {
            'utf8bom' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($true)) }
            'utf8' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($false)) }
            'cp1252' { [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)) }
            'utf16' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UnicodeEncoding]::new($false, $true)) }
        }

        $path
    }

    # One row of the reviewed report, with the columns of $script:Header, as the Scan writes them and a person edits them.
    function script:New-TestRow {
        param(
            [string]$Url = 'https://contoso.sharepoint.com/sites/a',
            [string]$SiteId = $script:SiteA,
            [string]$Decision = '',
            [string]$GeneratedOn = $script:Generated,
            [string]$Title = 'A title'
        )

        "$Url,OK-SUGGEST-DELETE,Delete,$Decision,$SiteId,$Title,$GeneratedOn"
    }

    function script:Write-TestReport {
        param([string[]]$Row, [string]$Header = $script:Header, [string]$Name = 'sites.csv', [string]$Encoding = 'utf8bom')
        $text = ((@($Header) + @($Row)) -join "`r`n") + "`r`n"
        Write-TestFile -Name $Name -Text $text -Encoding $Encoding
    }

    function script:New-TestSetting {
        param([string]$Path, [int]$MaxCsvAgeDays = 30, [string[]]$CsvDateFormats = @(), [string[]]$RefusedTenants = @('microsoft', 'microsoftonline'))
        [PSCustomObject]@{
            TenantName     = 'contoso'
            RefusedTenants = $RefusedTenants
            CsvDateFormats = $CsvDateFormats
            Act            = [PSCustomObject]@{ InputFile = $Path; MaxCsvAgeDays = $MaxCsvAgeDays }
        }
    }

    function script:Import-TestReviewed {
        param($Setting, [datetime]$Now = $script:Now)
        & $script:Module { param($s, $n) Import-SPSLifecycleReviewedReport -Setting $s -Now $n } $Setting $Now
    }

    # Reads the report that the rows make, with the settings that the parameters give.
    function script:Read-TestRows {
        param([string[]]$Row, [string]$Header = $script:Header, [int]$MaxCsvAgeDays = 30, [string[]]$CsvDateFormats = @(), [string]$Encoding = 'utf8bom')
        $path = Write-TestReport -Row $Row -Header $Header -Encoding $Encoding
        Import-TestReviewed -Setting (New-TestSetting -Path $path -MaxCsvAgeDays $MaxCsvAgeDays -CsvDateFormats $CsvDateFormats)
    }
}

Describe 'Import-SPSLifecycleReviewedReport' {
    Context 'What it gives back' {
        It 'gives the rows that have a decision, with their line, and counts each action' {
            $report = Read-TestRows -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision 'Delete')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -Decision '')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/c' -SiteId $script:SiteC -Decision 'Archive')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/d' -SiteId '11111111-2222-4333-8444-555555555555' -Decision 'Lock')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/e' -SiteId '22222222-2222-4333-8444-555555555555' -Decision 'Delete')
            )

            $report.Name | Should -BeExactly 'sites.csv'
            $report.RowCount | Should -Be 5
            $report.NothingToDo | Should -BeFalse
            $report.ActionCount | Should -Be 4
            $report.Counts.Delete | Should -Be 2
            $report.Counts.Archive | Should -Be 1
            $report.Counts.Lock | Should -Be 1
            @($report.Rows) | Should -HaveCount 4
            @($report.Rows | ForEach-Object { $_.Line }) | Should -Be @(2, 4, 5, 6)
            @($report.Rows | ForEach-Object { $_.Decision }) | Should -Be @('Delete', 'Archive', 'Lock', 'Delete')
            $report.Rows[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $report.Rows[0].UrlKey | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $report.Rows[0].SiteId | Should -BeExactly $script:SiteA
            $report.Rows[0].GeneratedOn | Should -Be $script:Now.AddDays(-1)
            $report.Rows[0].GeneratedOn.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'gives the date of the file, which is the oldest of its rows, and its age' {
            $report = Read-TestRows -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision 'Delete' -GeneratedOn '20261029T090000Z')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -Decision 'Delete' -GeneratedOn '20261020T090000Z')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/c' -SiteId $script:SiteC -Decision '' -GeneratedOn '20261025T090000Z')
            )

            $report.GeneratedOn | Should -Be ([System.DateTime]::new(2026, 10, 20, 9, 0, 0, [System.DateTimeKind]::Utc))
            $report.AgeDays | Should -Be 10
            $report.Rows[0].GeneratedOn | Should -Be ([System.DateTime]::new(2026, 10, 29, 9, 0, 0, [System.DateTimeKind]::Utc))
            $report.Rows[1].GeneratedOn | Should -Be ([System.DateTime]::new(2026, 10, 20, 9, 0, 0, [System.DateTimeKind]::Utc))
        }

        It 'says that there is nothing to do, and does not fail, when no row has a decision' {
            $report = Read-TestRows -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA)
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -Decision '   ')
            )

            $report.NothingToDo | Should -BeTrue
            $report.RowCount | Should -Be 2
            $report.ActionCount | Should -Be 0
            @($report.Rows) | Should -HaveCount 0
            $report.Counts.Delete | Should -Be 0
            $report.Counts.Archive | Should -Be 0
            $report.Counts.Lock | Should -Be 0
        }

        It 'says that there is nothing to do for a file that has a header and no row' {
            $report = Read-TestRows -Row @()

            $report.NothingToDo | Should -BeTrue
            $report.RowCount | Should -Be 0
            $report.GeneratedOn | Should -BeNullOrEmpty
        }

        It 'reads the decision whatever its case and the spaces around it, and gives it in the spelling of the tool: <Written>' -ForEach @(
            @{ Written = 'delete'; Expected = 'Delete' }
            @{ Written = 'DELETE'; Expected = 'Delete' }
            @{ Written = '  Delete  '; Expected = 'Delete' }
            @{ Written = 'archive'; Expected = 'Archive' }
            @{ Written = 'ARCHIVE'; Expected = 'Archive' }
            @{ Written = 'lock'; Expected = 'Lock' }
            @{ Written = 'LOCK '; Expected = 'Lock' }
        ) {
            $report = Read-TestRows -Row @((New-TestRow -Decision "`"$Written`""))

            $report.Rows[0].Decision | Should -BeExactly $Expected
        }

        It 'reads a file as Excel saves it: <Name>' -ForEach @(
            @{ Name = 'semicolons and Windows-1252 (French)'; Encoding = 'cp1252'; Separator = ';' }
            @{ Name = 'semicolons and UTF-8 with a byte order mark'; Encoding = 'utf8bom'; Separator = ';' }
            @{ Name = 'tabs and UTF-16 (Unicode text)'; Encoding = 'utf16'; Separator = "`t" }
            @{ Name = 'commas and UTF-8 without a byte order mark'; Encoding = 'utf8'; Separator = ',' }
        ) {
            $header = $script:Header -replace ',', $Separator
            $row = (New-TestRow -Url 'https://contoso.sharepoint.com/sites/équipe' -SiteId $script:SiteA -Decision ' delete ' -Title 'Équipe été') -replace ',', $Separator

            $report = Read-TestRows -Row @($row) -Header $header -Encoding $Encoding

            $report.Rows | Should -HaveCount 1
            $report.Rows[0].Decision | Should -BeExactly 'Delete'
            $report.Rows[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/équipe'
        }

        It 'ignores the empty rows that Excel adds at the end, a first line sep=, and the columns that it does not read' {
            $path = Write-TestFile -Name 'excel.csv' -Text "sep=;`r`nUrl;Decision;SiteId;GeneratedOn;Notes;`r`nhttps://contoso.sharepoint.com/sites/a;Delete;$($script:SiteA);$($script:Generated);remember this;`r`n;;;;;`r`n;;;;;`r`n"

            $report = Import-TestReviewed -Setting (New-TestSetting -Path $path)

            $report.RowCount | Should -Be 1
            $report.Rows | Should -HaveCount 1
            $report.Rows[0].Line | Should -Be 3
        }

        It 'accepts a site address in the spellings that name the same site: <Name>' -ForEach @(
            @{ Name = 'a trailing slash'; Url = 'https://contoso.sharepoint.com/sites/a/' }
            @{ Name = 'a host in capitals'; Url = 'https://CONTOSO.sharepoint.com/sites/A' }
            @{ Name = 'the root site'; Url = 'https://contoso.sharepoint.com' }
            @{ Name = 'percent-encoding'; Url = 'https://contoso.sharepoint.com/sites/%C3%A9quipe' }
            @{ Name = 'spaces around it'; Url = ' https://contoso.sharepoint.com/sites/a ' }
        ) {
            $report = Read-TestRows -Row @((New-TestRow -Url "`"$Url`"" -Decision 'Delete'))

            $report.Rows | Should -HaveCount 1
        }

        It 'gives the same key for the spellings of an address, so that the next steps find the site' {
            $report = Read-TestRows -Row @((New-TestRow -Url 'https://CONTOSO.sharepoint.com/sites/%C3%89quipe/' -Decision 'Delete'))

            $report.Rows[0].UrlKey | Should -BeExactly 'https://contoso.sharepoint.com/sites/équipe'
        }

        It 'gives the site ID in lowercase, without braces' {
            $report = Read-TestRows -Row @((New-TestRow -SiteId '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}' -Decision 'Delete'))

            $report.Rows[0].SiteId | Should -BeExactly $script:SiteA
        }
    }

    Context 'What stops the tool, and what the message names' {
        It 'stops on a missing column, and names the file and the column: <Column>' -ForEach @(
            @{ Column = 'Url' }
            @{ Column = 'SiteId' }
            @{ Column = 'GeneratedOn' }
            @{ Column = 'Decision' }
        ) {
            $header = (($script:Header -split ',') | Where-Object { $_ -ne $Column }) -join ','
            $path = Write-TestFile -Name 'sites.csv' -Text "$header`r`nx`r`n"

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage "*sites.csv*$Column*"
        }

        It 'stops on a column that only looks like a required one, because its rows would be read as empty' {
            $header = $script:Header -replace 'SiteId', "Site$([char]0xAD)Id"
            $path = Write-TestFile -Name 'sites.csv' -Text "$header`r`n$(New-TestRow -Decision 'Delete')`r`n"

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*Site\u00ADId*'
        }

        It 'stops on a file whose structure is broken, as the lists are read: <Name>' -ForEach @(
            @{ Name = 'a row cut short'; Row = 'https://contoso.sharepoint.com/sites/a,OK,Delete'; Message = '*sites.csv*line 2*3 value(s)*7 column(s)*' }
            @{ Name = 'a stray quote'; Row = "https://contoso.sharepoint.com/sites/a,OK,Delete,Delete,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,stray`"quote,20261029T090000Z"; Message = '*sites.csv*line 2*CSV rules*' }
            @{ Name = 'a quote that is never closed'; Row = "https://contoso.sharepoint.com/sites/a,OK,Delete,Delete,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,`"open,20261029T090000Z`r`nhttps://contoso.sharepoint.com/sites/b,OK,Delete,Delete,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,x,20261029T090000Z"; Message = '*sites.csv*line 2*' }
        ) {
            $path = Write-TestFile -Name 'sites.csv' -Text "$($script:Header)`r`n$Row`r`n"

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'stops on an address that is not one of the tenant, and names the line and the address: <Name>' -ForEach @(
            @{ Name = 'no address'; Url = ''; Message = "*sites.csv*line 2*Url*empty*" }
            @{ Name = 'a name'; Url = 'Sales team'; Message = "*sites.csv*line 2*'Sales team'*not a full web address*" }
            @{ Name = 'a server-relative path'; Url = '/sites/a'; Message = "*sites.csv*line 2*'/sites/a'*not a full web address*" }
            @{ Name = 'another tenant'; Url = 'https://fabrikam.sharepoint.com/sites/a'; Message = "*sites.csv*line 2*'https://fabrikam.sharepoint.com/sites/a'*not an address of the tenant 'contoso': its host is 'fabrikam.sharepoint.com'.*" }
            @{ Name = 'the admin site of the tenant'; Url = 'https://contoso-admin.sharepoint.com/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': its host is 'contoso-admin.sharepoint.com'.*" }
            @{ Name = 'a host that only starts like the tenant'; Url = 'https://contoso.sharepoint.com.example.org/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': its host is 'contoso.sharepoint.com.example.org'.*" }
            @{ Name = 'a site of another domain'; Url = 'https://contoso.example.org/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': its host is 'contoso.example.org'.*" }
            @{ Name = 'a OneDrive address, which the tool never touches'; Url = 'https://contoso-my.sharepoint.com/personal/jane_contoso_com'; Message = "*sites.csv*line 2*OneDrive*never*" }
            @{ Name = 'http'; Url = 'http://contoso.sharepoint.com/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': it is not https.*" }
            @{ Name = 'a port'; Url = 'https://contoso.sharepoint.com:8443/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': it has a port.*" }
            @{ Name = 'user information'; Url = 'https://someone@contoso.sharepoint.com/sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': it has user information.*" }
            @{ Name = 'the dot of the DNS root'; Url = 'https://contoso.sharepoint.com./sites/a'; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': its host ends with the dot of the DNS root.*" }
            @{ Name = 'a letter that looks like another one in the host'; Url = "https://cont$([char]0x043E)so.sharepoint.com/sites/a"; Message = "*sites.csv*line 2*not an address of the tenant 'contoso': its host is 'cont\u043Eso.sharepoint.com', which DNS does not read as it is written.*" }
            @{ Name = 'a hidden character in the host'; Url = "https://conto$([char]0xAD)so.sharepoint.com/sites/a"; Message = "*sites.csv*line 2*not a full web address*" }
            @{ Name = 'a file address'; Url = 'file:///etc/passwd'; Message = "*sites.csv*line 2*not a full web address*" }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Url "`"$Url`"" -Decision 'Delete'))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'stops on a refused tenant, says so, and names the tenant: <Tenant>' -ForEach @(
            @{ Tenant = 'microsoft'; Refused = @('microsoft', 'microsoftonline') }
            @{ Tenant = 'MICROSOFT'; Refused = @('microsoft', 'microsoftonline') }
            @{ Tenant = 'microsoftonline'; Refused = @('microsoft', 'microsoftonline') }
            @{ Tenant = 'fabrikam'; Refused = @('microsoft', 'microsoftonline', 'fabrikam') }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Url "https://$Tenant.sharepoint.com/sites/a" -Decision 'Delete'))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path -RefusedTenants $Refused) } | Should -Throw -ExpectedMessage "*sites.csv*line 2*'$($Tenant.ToLowerInvariant())'*refused*"
        }

        It 'stops on a refused tenant at its OneDrive host and at its admin site too' -ForEach @(
            @{ Url = 'https://microsoft-my.sharepoint.com/personal/x' }
            @{ Url = 'https://microsoft-admin.sharepoint.com/sites/x' }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Url $Url -Decision 'Delete'))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*line 2*refused*'
        }

        It 'stops on a site ID that is not usable, and names the line and the value: <Name>' -ForEach @(
            @{ Name = 'an empty cell'; SiteId = ''; Message = "*sites.csv*line 2*SiteId*empty*" }
            @{ Name = 'a text'; SiteId = 'not-a-guid'; Message = "*sites.csv*line 2*SiteId 'not-a-guid'*not a GUID*" }
            @{ Name = 'a GUID that is cut short'; SiteId = 'a6e20079-2d1a-4e9d-bc9f'; Message = "*sites.csv*line 2*not a GUID*" }
            @{ Name = 'the GUID of zeros that a concealed report gives'; SiteId = '00000000-0000-0000-0000-000000000000'; Message = "*sites.csv*line 2*all zeros*" }
            @{ Name = 'a hidden character'; SiteId = "a6e20079-2d1a-4e9d-bc9f-94e3f2efeb6$([char]0x200B)4"; Message = "*sites.csv*line 2*a6e20079-2d1a-4e9d-bc9f-94e3f2efeb6\u200B4*not a GUID*" }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -SiteId $SiteId -Decision 'Delete'))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'stops on a site that appears twice, and names both lines: <Name>' -ForEach @(
            @{ Name = 'the same address'; Second = 'https://contoso.sharepoint.com/sites/a'; SecondId = '11111111-2222-4333-8444-555555555555'; Message = '*sites.csv*line 3*line 2*address*' }
            @{ Name = 'the same address with a trailing slash and another case'; Second = 'https://CONTOSO.sharepoint.com/Sites/A/'; SecondId = '11111111-2222-4333-8444-555555555555'; Message = '*sites.csv*line 3*line 2*address*' }
            @{ Name = 'the same address written with percent-encoding'; Second = 'https://contoso.sharepoint.com/sites/%61'; SecondId = '11111111-2222-4333-8444-555555555555'; Message = '*sites.csv*line 3*line 2*address*' }
            @{ Name = 'the same address with its default port'; Second = 'https://contoso.sharepoint.com:443/sites/a'; SecondId = '11111111-2222-4333-8444-555555555555'; Message = '*sites.csv*line 3*line 2*address*' }
            @{ Name = 'the same site ID'; Second = 'https://contoso.sharepoint.com/sites/other'; SecondId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*sites.csv*line 3*line 2*site ID*' }
            @{ Name = 'the same site ID in capitals, with braces'; Second = 'https://contoso.sharepoint.com/sites/other'; SecondId = '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}'; Message = '*sites.csv*line 3*line 2*site ID*' }
        ) {
            $path = Write-TestReport -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision 'Delete')
                (New-TestRow -Url $Second -SiteId $SecondId -Decision 'Delete')
            )

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'stops on a site that appears twice even when only one of the rows has a decision, or none does' -ForEach @(
            @{ First = 'Delete'; Second = '' }
            @{ First = ''; Second = 'Delete' }
            @{ First = ''; Second = '' }
            @{ First = 'Delete'; Second = 'Archive' }
        ) {
            $path = Write-TestReport -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision $First)
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteB -Decision $Second)
            )

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*line 3*line 2*'
        }

        It 'does not take two different sites for one: the same address under two IDs is refused, two addresses are two sites' {
            $path = Write-TestReport -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision 'Delete')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/ab' -SiteId $script:SiteB -Decision 'Delete')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a/sub' -SiteId $script:SiteC -Decision 'Delete')
            )

            (Import-TestReviewed -Setting (New-TestSetting -Path $path)).Rows | Should -HaveCount 3
        }

        It 'stops on a decision that is not one, and shows it: <Name>' -ForEach @(
            @{ Name = 'a word that is not an action'; Decision = 'Remove'; Shown = 'Remove' }
            @{ Name = 'a past tense'; Decision = 'Deleted'; Shown = 'Deleted' }
            @{ Name = 'two words'; Decision = 'Delete it'; Shown = 'Delete it' }
            @{ Name = 'a cross'; Decision = 'x'; Shown = 'x' }
            @{ Name = 'the French word'; Decision = 'Supprimer'; Shown = 'Supprimer' }
            @{ Name = 'a hidden character inside the word'; Decision = "Del$([char]0x200B)ete"; Shown = 'Del\u200Bete' }
            @{ Name = 'a soft hyphen inside the word'; Decision = "Arch$([char]0xAD)ive"; Shown = 'Arch\u00ADive' }
            @{ Name = 'a letter that looks like another one'; Decision = "Delet$([char]0x0435)"; Shown = 'Delet\u0435' }
            @{ Name = 'a dotless i in Archive'; Decision = "Arch$([char]0x0131)ve"; Shown = 'Arch\u0131ve' }
            @{ Name = 'a Kelvin sign in Lock'; Decision = "Loc$([char]0x212A)"; Shown = 'Loc\u212A' }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision "`"$Decision`""))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage "*sites.csv*line 2*Decision '$Shown'*Delete, Archive or Lock*empty*"
        }

        It 'stops on a decision that is not one, wherever the row is, even among many good ones' {
            $good = 1..9 | ForEach-Object { New-TestRow -Url "https://contoso.sharepoint.com/sites/a$_" -SiteId ('{0:x8}-2222-4333-8444-555555555555' -f $_) -Decision 'Delete' }
            $path = Write-TestReport -Row ($good + (New-TestRow -Url 'https://contoso.sharepoint.com/sites/z' -SiteId $script:SiteB -Decision 'Remove'))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*line 11*Remove*'
        }

        It 'stops on a date that cannot be read, and names the line, the column and the value: <Name>' -ForEach @(
            @{ Name = 'a word'; Value = 'yesterday'; Message = "*sites.csv*line 2*GeneratedOn*'yesterday'*" }
            @{ Name = 'a date that Excel rewrote'; Value = '29/10/2026 09:00'; Message = "*sites.csv*line 2*GeneratedOn*'29/10/2026 09:00'*CsvDateFormats*" }
            @{ Name = 'a date that Excel rewrote, with seconds'; Value = '29/10/2026 09:00:00'; Message = "*sites.csv*line 2*GeneratedOn*CsvDateFormats*" }
            @{ Name = 'a month that does not exist'; Value = '20261329T090000Z'; Message = "*sites.csv*line 2*GeneratedOn*" }
            @{ Name = 'no date'; Value = ''; Message = "*sites.csv*line 2*GeneratedOn*empty*" }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete' -GeneratedOn $Value))

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'reads a date that Excel rewrote when the setting names its format' {
            $report = Read-TestRows -Row @((New-TestRow -Decision 'Delete' -GeneratedOn '29/10/2026 09:00')) -CsvDateFormats @('dd/MM/yyyy HH:mm')

            $report.Rows[0].GeneratedOn | Should -Be ([System.DateTime]::new(2026, 10, 29, 9, 0, 0, [System.DateTimeKind]::Utc))
        }

        It 'stops on a file that was generated in the future, with a margin for the clocks of two machines: <Name>' -ForEach @(
            @{ Name = 'an hour ahead'; Generated = '20261030T100000Z'; Stops = $true }
            @{ Name = 'a day ahead'; Generated = '20261031T090000Z'; Stops = $true }
            @{ Name = 'six minutes ahead'; Generated = '20261030T090600Z'; Stops = $true }
            @{ Name = 'four minutes ahead'; Generated = '20261030T090400Z'; Stops = $false }
            @{ Name = 'exactly the margin ahead'; Generated = '20261030T090500Z'; Stops = $false }
            @{ Name = 'now'; Generated = '20261030T090000Z'; Stops = $false }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete' -GeneratedOn $Generated))

            if ($Stops) {
                { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*line 2*GeneratedOn*in the future*'
            }
            else {
                { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Not -Throw
            }
        }

        It 'writes the dates of its messages the same way whatever the culture: <Culture>' -ForEach @(
            @{ Culture = 'en-US' }
            @{ Culture = 'fr-FR' }
            @{ Culture = 'th-TH' }
        ) {
            $future = Write-TestReport -Row @((New-TestRow -Decision 'Delete' -GeneratedOn '20261030T100000Z')) -Name 'future.csv'
            $old = Write-TestReport -Row @((New-TestRow -Decision 'Delete' -GeneratedOn '20260929T090000Z')) -Name 'old.csv'
            $previous = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

                { Import-TestReviewed -Setting (New-TestSetting -Path $future) } | Should -Throw -ExpectedMessage "*future.csv*2026-10-30T10:00:00Z is in the future (now: 2026-10-30T09:00:00Z)*"
                { Import-TestReviewed -Setting (New-TestSetting -Path $old) } | Should -Throw -ExpectedMessage "*old.csv*generated on 2026-09-29T09:00:00Z, 31 days ago, which is older than MaxCsvAgeDays (30 days)*"
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }
        }

        It 'stops on a file that is older than MaxCsvAgeDays, names its age and the setting, and says to run the Scan again: <Name>' -ForEach @(
            @{ Name = 'a month and a day'; Generated = '20260929T090000Z'; Max = 30; Stops = $true; Days = 31 }
            @{ Name = 'a year'; Generated = '20251030T090000Z'; Max = 30; Stops = $true; Days = 365 }
            @{ Name = 'a minute over the limit'; Generated = '20260930T085900Z'; Max = 30; Stops = $true; Days = 30 }
            @{ Name = 'exactly the limit'; Generated = '20260930T090000Z'; Max = 30; Stops = $false; Days = 30 }
            @{ Name = 'a day under the limit'; Generated = '20261001T090000Z'; Max = 30; Stops = $false; Days = 29 }
            @{ Name = 'two days with a limit of one day'; Generated = '20261028T090000Z'; Max = 1; Stops = $true; Days = 2 }
            @{ Name = 'a year with the largest limit'; Generated = '20251101T090000Z'; Max = 365; Stops = $false; Days = 363 }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete' -GeneratedOn $Generated))
            $setting = New-TestSetting -Path $path -MaxCsvAgeDays $Max

            if ($Stops) {
                { Import-TestReviewed -Setting $setting } | Should -Throw -ExpectedMessage "*sites.csv*line 2*GeneratedOn*older than MaxCsvAgeDays ($Max*Scan*again*"
            }
            else {
                { Import-TestReviewed -Setting $setting } | Should -Not -Throw
            }
        }

        It 'stops on one old row among rows that are recent, because the file is one document' {
            $path = Write-TestReport -Row @(
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/a' -SiteId $script:SiteA -Decision 'Delete')
                (New-TestRow -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -Decision '' -GeneratedOn '20250101T000000Z')
            )

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage '*sites.csv*line 3*older than MaxCsvAgeDays*'
        }

        It 'checks the rows in order, and each row in the order of the checks: <Name>' -ForEach @(
            @{ Name = 'the first row that has a problem, whatever the problem'; Rows = @('https://contoso.sharepoint.com/sites/a|x|Remove|20261029T090000Z', 'Sales|x|Delete|yesterday'); Message = '*line 2*Decision*' }
            @{ Name = 'the address before the site ID'; Rows = @('Sales team|not-a-guid|Remove|yesterday'); Message = '*line 2*not a full web address*' }
            @{ Name = 'the site ID before the decision'; Rows = @('https://contoso.sharepoint.com/sites/a|not-a-guid|Remove|yesterday'); Message = '*line 2*not a GUID*' }
            @{ Name = 'the decision before the date'; Rows = @('https://contoso.sharepoint.com/sites/a|A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64|Remove|yesterday'); Message = '*line 2*Decision*' }
            @{ Name = 'the date last'; Rows = @('https://contoso.sharepoint.com/sites/a|A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64|Delete|yesterday'); Message = '*line 2*GeneratedOn*' }
        ) {
            $rows = foreach ($spec in $Rows) {
                $part = $spec -split '\|'
                $siteId = if ($part[1] -eq 'x') { $script:SiteA } else { $part[1] }
                New-TestRow -Url $part[0] -SiteId $siteId -Decision $part[2] -GeneratedOn $part[3]
            }
            $path = Write-TestReport -Row @($rows)

            { Import-TestReviewed -Setting (New-TestSetting -Path $path) } | Should -Throw -ExpectedMessage $Message
        }

        It 'does not read the settings of another phase, and says what is missing' -ForEach @(
            @{ Missing = 'TenantName' }
            @{ Missing = 'Act.InputFile' }
            @{ Missing = 'Act.MaxCsvAgeDays' }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete'))
            $setting = New-TestSetting -Path $path
            switch ($Missing) {
                'TenantName' { $setting.PSObject.Properties.Remove('TenantName') }
                'Act.InputFile' { $setting.Act.PSObject.Properties.Remove('InputFile') }
                'Act.MaxCsvAgeDays' { $setting.Act.PSObject.Properties.Remove('MaxCsvAgeDays') }
            }

            { Import-TestReviewed -Setting $setting } | Should -Throw -ExpectedMessage "*The settings lack*$Missing*Get-SPSLifecycleSetting*"
        }

        It 'does not take a setting that is there and empty for one that is given: <Name>' -ForEach @(
            @{ Name = 'an empty tenant name'; Message = '*The settings lack TenantName*' }
            @{ Name = 'a tenant name of spaces'; Message = '*The settings lack TenantName*' }
            @{ Name = 'no Act section'; Message = '*The settings lack Act.*' }
            @{ Name = 'no input file'; Message = '*The settings lack Act.InputFile*' }
            @{ Name = 'no limit of age'; Message = '*The settings lack Act.MaxCsvAgeDays*' }
        ) {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete'))
            $setting = New-TestSetting -Path $path
            switch ($Name) {
                'an empty tenant name' { $setting.TenantName = '' }
                'a tenant name of spaces' { $setting.TenantName = '   ' }
                'no Act section' { $setting.Act = $null }
                'no input file' { $setting.Act.InputFile = $null }
                'no limit of age' { $setting.Act.MaxCsvAgeDays = $null }
            }

            { Import-TestReviewed -Setting $setting } | Should -Throw -ExpectedMessage $Message
        }

        It 'stops when the file does not exist' {
            $setting = New-TestSetting -Path (Join-Path -Path $TestDrive -ChildPath 'nope.csv')

            { Import-TestReviewed -Setting $setting } | Should -Throw -ExpectedMessage '*File not found*'
        }
    }

    Context 'It changes nothing and reaches nothing' {
        It 'does not write anything, and leaves the file as it was' {
            $path = Write-TestReport -Row @((New-TestRow -Decision 'Delete'))
            $before = (Get-FileHash -LiteralPath $path).Hash
            $files = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -File).Count

            $null = Import-TestReviewed -Setting (New-TestSetting -Path $path)

            (Get-FileHash -LiteralPath $path).Hash | Should -BeExactly $before
            @(Get-ChildItem -LiteralPath $TestDrive -Recurse -File).Count | Should -Be $files
        }
    }

    Context 'How long it takes' {
        It 'reads 4,000 and 16,000 rows in a time that does not grow with the square of the size' -Tag 'Slow' {
            function script:New-TestRowText {
                param([int]$Count)
                $builder = [System.Text.StringBuilder]::new()
                $null = $builder.Append($script:Header).Append("`r`n")
                for ($i = 1; $i -le $Count; $i++) {
                    $null = $builder.Append((New-TestRow -Url "https://contoso.sharepoint.com/sites/site$i" -SiteId ('{0:x8}-2222-4333-8444-555555555555' -f $i) -Decision $(if ($i % 100 -eq 0) { 'Delete' } else { '' }))).Append("`r`n")
                }

                $builder.ToString()
            }

            $small = Write-TestFile -Name 'small.csv' -Text (New-TestRowText -Count 4000)
            $large = Write-TestFile -Name 'large.csv' -Text (New-TestRowText -Count 16000)
            $null = Import-TestReviewed -Setting (New-TestSetting -Path $small)

            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Import-TestReviewed -Setting (New-TestSetting -Path $small)
            $smallSeconds = $watch.Elapsed.TotalSeconds
            $watch.Restart()
            $report = Import-TestReviewed -Setting (New-TestSetting -Path $large)
            $largeSeconds = $watch.Elapsed.TotalSeconds

            $report.RowCount | Should -Be 16000
            $report.ActionCount | Should -Be 160
            $largeSeconds | Should -BeLessThan 30
            $largeSeconds | Should -BeLessThan ([System.Math]::Max(0.5, $smallSeconds) * 10)
        }
    }
}
