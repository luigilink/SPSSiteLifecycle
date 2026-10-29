BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    function script:Write-TestFile {
        param([string]$Name, [byte[]]$Byte)
        $path = Join-Path -Path $TestDrive -ChildPath $Name
        [System.IO.File]::WriteAllBytes($path, $Byte)
        $path
    }

    function script:Get-TestByte {
        param([string]$Text, [string]$Encoding = 'utf8', [switch]$Preamble)
        $encodingObject = switch ($Encoding) {
            'utf8' { [System.Text.UTF8Encoding]::new($false) }
            'utf16le' { [System.Text.UnicodeEncoding]::new($false, $false) }
            'cp1252' { [System.Text.Encoding]::GetEncoding(1252) }
        }

        $bytes = $encodingObject.GetBytes($Text)
        if ($Preamble) {
            $bytes = [byte[]]($(if ($Encoding -eq 'utf16le') { 0xFF, 0xFE } else { 0xEF, 0xBB, 0xBF }) + $bytes)
        }

        , $bytes
    }

    function script:Read-TestCsv {
        param([string]$Path, [string[]]$Required = @())
        & $script:Module { param($p, $r) Read-SPSLifecycleCsv -Path $p -RequiredColumn $r } $Path $Required
    }
}

Describe 'Read-SPSLifecycleCsv' {
    Context 'Separators' {
        It 'reads a file separated by <Name>' -ForEach @(
            @{ Name = 'commas'; Text = "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,2025-09-18`r`n" }
            @{ Name = 'semicolons'; Text = "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n" }
            @{ Name = 'tabs'; Text = "Url`tLockedOn`r`nhttps://contoso.sharepoint.com/sites/a`t2025-09-18`r`n" }
        ) {
            $path = Write-TestFile -Name 'a.csv' -Byte (Get-TestByte -Text $Text)
            $rows = @(Read-TestCsv -Path $path -Required 'Url', 'LockedOn')

            $rows | Should -HaveCount 1
            $rows[0].Url | Should -Be 'https://contoso.sharepoint.com/sites/a'
            $rows[0].LockedOn | Should -Be '2025-09-18'
        }

        It 'reads the sep= line that Excel can add, and skips it' {
            $path = Write-TestFile -Name 'sep.csv' -Byte (Get-TestByte -Text "sep=;`r`nUrl;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows | Should -HaveCount 1
            $rows[0].LockedOn | Should -Be '2025-09-18'
        }

        It 'does not split on a separator inside quotes' {
            $path = Write-TestFile -Name 'q.csv' -Byte (Get-TestByte -Text "Url,Title`r`nhttps://contoso.sharepoint.com/sites/a,`"Sales; EMEA, 2026`"`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url', 'Title')

            $rows[0].Title | Should -Be 'Sales; EMEA, 2026'
        }

        It 'chooses the comma when the header has a single column' {
            $path = Write-TestFile -Name 'one.csv' -Byte (Get-TestByte -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows | Should -HaveCount 1
        }
    }

    Context 'Encodings' {
        It 'reads UTF-8 <Name>' -ForEach @(
            @{ Name = 'with a byte order mark'; WithMark = $true }
            @{ Name = 'without a byte order mark'; WithMark = $false }
        ) {
            $bytes = Get-TestByte -Text "Url;Title`r`nhttps://contoso.sharepoint.com/sites/a;Équipe été`r`n" -Preamble:$WithMark
            $path = Write-TestFile -Name 'utf8.csv' -Byte $bytes
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows[0].Title | Should -Be 'Équipe été'
            @($rows[0].PSObject.Properties.Name)[0] | Should -Be 'Url'
        }

        It 'reads UTF-16 with a byte order mark' {
            $bytes = Get-TestByte -Text "Url;Title`r`nhttps://contoso.sharepoint.com/sites/a;Équipe`r`n" -Encoding utf16le -Preamble
            $path = Write-TestFile -Name 'utf16.csv' -Byte $bytes
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows[0].Title | Should -Be 'Équipe'
        }

        It 'falls back to Windows-1252, the first CSV format of French Excel' {
            $bytes = Get-TestByte -Text "Url;Title`r`nhttps://contoso.sharepoint.com/sites/a;Équipe été`r`n" -Encoding cp1252
            $path = Write-TestFile -Name 'cp1252.csv' -Byte $bytes
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows[0].Title | Should -Be 'Équipe été'
        }
    }

    Context 'Rows and columns' {
        It 'ignores the empty rows that a spreadsheet adds' {
            $path = Write-TestFile -Name 'empty.csv' -Byte (Get-TestByte -Text "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n;`r`n;`r`n`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url')

            $rows | Should -HaveCount 1
        }

        It 'returns no row for a file that has only a header' {
            $path = Write-TestFile -Name 'header.csv' -Byte (Get-TestByte -Text "Url;LockedOn`r`n")

            @(Read-TestCsv -Path $path -Required 'Url', 'LockedOn') | Should -HaveCount 0
        }

        It 'ignores the case of the column names' {
            $path = Write-TestFile -Name 'case.csv' -Byte (Get-TestByte -Text "URL;lockedon`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n")

            { Read-TestCsv -Path $path -Required 'Url', 'LockedOn' } | Should -Not -Throw
        }

        It 'names the missing column and the columns present' {
            $path = Write-TestFile -Name 'missing.csv' -Byte (Get-TestByte -Text "Url;Title`r`nhttps://contoso.sharepoint.com/sites/a;x`r`n")

            { Read-TestCsv -Path $path -Required 'Url', 'LockedOn' } | Should -Throw -ExpectedMessage '*LockedOn*Columns present: Url, Title*'
        }

        It 'checks the columns of a file that has no row' {
            $path = Write-TestFile -Name 'missing-empty.csv' -Byte (Get-TestByte -Text "Url;Title`r`n")

            { Read-TestCsv -Path $path -Required 'LockedOn' } | Should -Throw -ExpectedMessage '*LockedOn*'
        }

        It 'says that an empty file has no column' {
            $path = Write-TestFile -Name 'zero.csv' -Byte ([byte[]]@())

            { Read-TestCsv -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*the file is empty*'
        }
    }

    Context 'Files' {
        It 'stops with a clear message when the file does not exist' {
            { Read-TestCsv -Path (Join-Path -Path $TestDrive -ChildPath 'nope.csv') } | Should -Throw -ExpectedMessage '*File not found*'
        }

        It 'reads a file that another program still has open for reading and writing' {
            $path = Write-TestFile -Name 'shared.csv' -Byte (Get-TestByte -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n")
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
            try {
                @(Read-TestCsv -Path $path -Required 'Url') | Should -HaveCount 1
            }
            finally {
                $stream.Dispose()
            }
        }

        It 'says that the file is probably open in Excel when it is locked' {
            $path = Write-TestFile -Name 'locked.csv' -Byte (Get-TestByte -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n")
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                { Read-TestCsv -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*open in another program*'
            }
            finally {
                $stream.Dispose()
            }
        }
    }
}

Describe 'Split-SPSLifecycleCsvLine' {
    It 'splits <Line> into <Count> fields' -ForEach @(
        @{ Line = 'a;b;c'; Delimiter = ';'; Count = 3; Joined = 'a|b|c' }
        @{ Line = 'a;"b;c";d'; Delimiter = ';'; Count = 3; Joined = 'a|b;c|d' }
        @{ Line = 'a,"say ""hi""",c'; Delimiter = ','; Count = 3; Joined = 'a|say "hi"|c' }
        @{ Line = ''; Delimiter = ','; Count = 1; Joined = '' }
        @{ Line = 'a,,c'; Delimiter = ','; Count = 3; Joined = 'a||c' }
    ) {
        $fields = @(& $script:Module { param($l, $d) Split-SPSLifecycleCsvLine -Line $l -Delimiter ([char]$d) } $Line $Delimiter)

        $fields | Should -HaveCount $Count
        ($fields -join '|') | Should -Be $Joined
    }
}
