BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

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

    function script:Write-TestBytes {
        param([string]$Name, [byte[]]$Byte)
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        [System.IO.File]::WriteAllBytes($path, $Byte)
        $path
    }

    function script:Read-TestStrict {
        param([string]$Path, [string[]]$Required = @(), [string[]]$Optional = @())
        & $script:Module { param($p, $r, $o) Read-SPSLifecycleStrictCsv -Path $p -RequiredColumn $r -OptionalColumn $o } $Path $Required $Optional
    }
}

Describe 'Read-SPSLifecycleStrictCsv' {
    Context 'What it reads' {
        It 'reads the rows, with a property for each column and the line of each row' {
            $path = Write-TestFile -Name 'journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2026-10-29`r`nhttps://contoso.sharepoint.com/sites/b,0D7B,2026-10-30`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url', 'SiteId', 'LockedOn'

            $table.Name | Should -BeExactly 'journal.csv'
            $table.Header | Should -Be @('Url', 'SiteId', 'LockedOn')
            $table.Rows | Should -HaveCount 2
            $table.Rows[1].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/b'
            $table.Rows[1].LockedOn | Should -BeExactly '2026-10-30'
            @($table.Line) | Should -Be @(2, 3)
        }

        It 'reads a header only, and no row' {
            $path = Write-TestFile -Name 'header.csv' -Text "Url,SiteId,LockedOn`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url'

            @($table.Rows) | Should -HaveCount 0
        }

        It 'reads a file saved by Excel as <Name>' -ForEach @(
            @{ Name = 'UTF-8 with a byte order mark'; Encoding = 'utf8bom'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;A6E2;29/10/2026`r`n" }
            @{ Name = 'UTF-8 without a byte order mark'; Encoding = 'utf8'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/équipe;A6E2;29/10/2026`r`n" }
            @{ Name = 'Windows-1252 (French), which holds only ASCII and is UTF-8 too'; Encoding = 'cp1252'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/equipe;A6E2;29/10/2026`r`n" }
        ) {
            $path = Write-TestFile -Name 'excel.csv' -Text $Text -Encoding $Encoding

            $table = Read-TestStrict -Path $path -Required 'Url', 'SiteId', 'LockedOn'

            $table.Rows | Should -HaveCount 1
            $table.Rows[0].SiteId | Should -BeExactly 'A6E2'
            $table.Rows[0].LockedOn | Should -BeExactly '29/10/2026'
        }

        It 'stops on a file that is not UTF-8, as a lock journal always is, and says to save it as CSV UTF-8: <Name>' -ForEach @(
            @{ Name = 'Windows-1252 with an accented letter'; Encoding = 'cp1252'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/équipe;A6E2;29/10/2026`r`n" }
            @{ Name = 'UTF-16 with a byte order mark'; Encoding = 'utf16'; Text = "Url`tSiteId`tLockedOn`r`nhttps://contoso.sharepoint.com/sites/a`tA6E2`t29/10/2026`r`n" }
        ) {
            $path = Write-TestFile -Name 'excel.csv' -Text $Text -Encoding $Encoding

            { Read-TestStrict -Path $path -Required 'Url', 'SiteId', 'LockedOn' } | Should -Throw -ExpectedMessage "*excel.csv*not UTF-8*CSV UTF-8*"
        }

        It 'stops on <Name> instead of replacing it, because a character that is replaced changes a web address and the row would no longer match its site' -ForEach @(
            @{ Name = 'a byte that is not UTF-8 after a UTF-8 byte order mark'; Bom = $true; Tail = [byte[]]@(0xFF) }
            @{ Name = 'a sequence cut short after a UTF-8 byte order mark'; Bom = $true; Tail = [byte[]]@(0xC3) }
            @{ Name = 'an overlong sequence after a UTF-8 byte order mark'; Bom = $true; Tail = [byte[]]@(0xC0, 0xAF) }
            @{ Name = 'half of a surrogate pair after a UTF-8 byte order mark'; Bom = $true; Tail = [byte[]]@(0xED, 0xA0, 0x80) }
            @{ Name = 'a byte that is not UTF-8 without a byte order mark'; Bom = $false; Tail = [byte[]]@(0xFF) }
            @{ Name = 'a sequence cut short without a byte order mark'; Bom = $false; Tail = [byte[]]@(0xC3) }
        ) {
            $mark = if ($Bom) { [byte[]]@(0xEF, 0xBB, 0xBF) } else { [byte[]]@() }
            $head = [System.Text.Encoding]::ASCII.GetBytes("Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a")
            $rest = [System.Text.Encoding]::ASCII.GetBytes(",,2026-10-29`r`n")
            $path = Write-TestBytes -Name 'damaged.csv' -Byte ([byte[]]($mark + $head + $Tail + $rest))

            { Read-TestStrict -Path $path -Required 'Url', 'SiteId', 'LockedOn' } | Should -Throw -ExpectedMessage '*damaged.csv*not UTF-8*'
        }

        It 'reads quoted values that hold a separator, a line break and doubled quotes' {
            $path = Write-TestFile -Name 'quoted.csv' -Text "Url,Note`r`nhttps://contoso.sharepoint.com/sites/a,`"a, `"`"b`"`"`r`nc`"`r`nhttps://contoso.sharepoint.com/sites/b,x`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url'

            $table.Rows | Should -HaveCount 2
            $table.Rows[0].Note | Should -Be "a, `"b`"`r`nc"
            @($table.Line) | Should -Be @(2, 4)
        }

        It 'ignores the blank lines before the header, between the rows and at the end, and counts them' {
            $path = Write-TestFile -Name 'blank.csv' -Text "`r`n`r`nUrl,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2026-10-29`r`n,,`r`n   ,  ,`r`nhttps://contoso.sharepoint.com/sites/b,0D7B,2026-10-30`r`n`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url'

            $table.Rows | Should -HaveCount 2
            @($table.Line) | Should -Be @(4, 7)
        }

        It 'follows a first line sep= that Excel may add, and counts it' {
            $path = Write-TestFile -Name 'sep.csv' -Text "sep=;`r`nUrl;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;A6E2;2026-10-29`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url', 'SiteId'

            $table.Rows | Should -HaveCount 1
            @($table.Line) | Should -Be @(3)
        }

        It 'trims the names of the columns, and finds them whatever their case' {
            $path = Write-TestFile -Name 'names.csv' -Text " URL ; siteid ;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;A6E2;2026-10-29`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url', 'SiteId'

            $table.Rows[0].URL | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $table.Rows[0].siteid | Should -BeExactly 'A6E2'
        }

        It 'ignores the empty names that a spreadsheet adds after the last column, and their empty cells' {
            $path = Write-TestFile -Name 'trailing.csv' -Text "Url,SiteId,`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,`r`n"

            $table = Read-TestStrict -Path $path -Required 'Url'

            $table.Rows | Should -HaveCount 1
            @($table.Rows[0].PSObject.Properties.Name) | Should -Be @('Url', 'SiteId')
        }

        It 'reads the file of the session location, not a file of the working directory of the process' {
            $location = Join-Path -Path $TestDrive -ChildPath 'here'
            $processDirectory = Join-Path -Path $TestDrive -ChildPath 'there'
            $null = New-Item -Path $location, $processDirectory -ItemType Directory
            [System.IO.File]::WriteAllText((Join-Path -Path $location -ChildPath 'j.csv'), "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/right,A6E2,2026-10-29`r`n")
            [System.IO.File]::WriteAllText((Join-Path -Path $processDirectory -ChildPath 'j.csv'), "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/decoy,A6E2,2026-10-29`r`n")
            $previousLocation = (Get-Location).Path
            $previousDirectory = [System.IO.Directory]::GetCurrentDirectory()
            try {
                [System.IO.Directory]::SetCurrentDirectory($processDirectory)
                Set-Location -LiteralPath $location

                $table = Read-TestStrict -Path 'j.csv' -Required 'Url'
            }
            finally {
                Set-Location -LiteralPath $previousLocation
                [System.IO.Directory]::SetCurrentDirectory($previousDirectory)
            }

            $table.Rows[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/right'
        }
    }

    Context 'What it refuses' {
        It 'stops on a row that has a value too many, even when the first values are empty, and names the line' {
            $path = Write-TestFile -Name 'overflow.csv' -Text "Url,SiteId,LockedOn`r`n,,,https://contoso.sharepoint.com/sites/a,A6E2,2026-10-29T14:37:39Z`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*overflow.csv*line 2*6 value(s)*3 column(s)*'
        }

        It 'stops on a row that is cut short, and names the line' {
            $path = Write-TestFile -Name 'short.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2026-10-29`r`nhttps://contoso.sharepoint.com/sites/b,0D7B`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*short.csv*line 3*2 value(s)*3 column(s)*'
        }

        It 'stops on a row of non-breaking spaces that has a value too many' {
            $path = Write-TestFile -Name 'nbsp.csv' -Text "Url,SiteId,LockedOn`r`n$([char]0xA0),$([char]0xA0),$([char]0xA0),https://contoso.sharepoint.com/sites/a`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*nbsp.csv*line 2*4 value(s)*'
        }

        It 'stops on a value under a column that has no name' {
            $path = Write-TestFile -Name 'unnamed.csv' -Text "Url,SiteId,LockedOn,`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-01-01,2026-10-29`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*unnamed.csv*line 2*column 4*no name*'
        }

        It 'stops on a text that breaks the CSV rules: <Name>' -ForEach @(
            @{ Name = 'a quote that is never closed at the end'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-02-01,`"unfinished"; Line = 2 }
            @{ Name = 'a stray quote, then a quote that is never closed (an even number of quotes)'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-01-01,stray`"quote`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-02-01,`"unfinished"; Line = 2 }
            @{ Name = 'a quote that swallows the rows after it'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-01-01,ok`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2024-02-01,`"open`r`nhttps://contoso.sharepoint.com/sites/b,0D7B,2024-03-01,x`r`n"; Line = 3 }
        ) {
            $path = Write-TestFile -Name 'rules.csv' -Text $Text

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage "*rules.csv*line $Line*"
        }

        It 'stops on a header that lacks a required column, and on one that only looks like it' {
            $missing = Write-TestFile -Name 'missing.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,2026-10-29`r`n"
            $lookalike = Write-TestFile -Name 'lookalike.csv' -Text "Url,Site$([char]0xAD)Id,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,2026-10-29`r`n"

            { Read-TestStrict -Path $missing -Required 'Url', 'SiteId', 'LockedOn' } | Should -Throw -ExpectedMessage '*missing.csv*SiteId*'
            { Read-TestStrict -Path $lookalike -Required 'Url', 'SiteId', 'LockedOn' } | Should -Throw -ExpectedMessage '*lookalike.csv*Site\u00ADId*'
        }

        It 'stops on a column that appears twice' {
            $path = Write-TestFile -Name 'twice.csv' -Text "Url,SiteId,url`r`nhttps://contoso.sharepoint.com/sites/a,A6E2,x`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage "*more than once in 'twice.csv'*"
        }

        It 'stops on a file with no header at all when a column is required, and says that it is empty' {
            $path = Write-TestFile -Name 'empty.csv' -Text "`r`n`r`n"

            { Read-TestStrict -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*empty.csv*the file is empty*'
        }

        It 'stops when the file does not exist' {
            { Read-TestStrict -Path (Join-Path -Path $TestDrive -ChildPath 'nope.csv') -Required 'Url' } | Should -Throw -ExpectedMessage '*File not found*'
        }
    }
}
