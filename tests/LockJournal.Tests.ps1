BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:SiteC = '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708'
    $script:LockedOn = [System.DateTime]::new(2026, 10, 29, 14, 37, 39, [System.DateTimeKind]::Utc)

    function script:New-TestFolder {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $folder
    }

    function script:Write-TestFile {
        param([string]$Folder, [string]$Name, [string]$Text, [string]$Encoding = 'utf8bom')
        $path = Join-Path -Path $Folder -ChildPath $Name
        switch ($Encoding) {
            'utf8bom' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($true)) }
            'utf8' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($false)) }
            'cp1252' { [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)) }
            'utf16' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UnicodeEncoding]::new($false, $true)) }
        }

        $path
    }

    function script:Read-TestText {
        param([string]$Path)
        [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    }

    function script:Import-TestJournal {
        param([string]$Path, [string[]]$DateFormat = @())
        & $script:Module { param($p, $f) Import-SPSLifecycleLockJournal -Path $p -DateFormat $f } $Path $DateFormat
    }

    function script:Add-TestEntry {
        param(
            [string]$Path,
            [string]$Url = 'https://contoso.sharepoint.com/sites/a',
            [string]$SiteId = $script:SiteA,
            $At = $script:LockedOn,
            [string]$Delimiter = ','
        )
        & $script:Module { param($p, $u, $s, $l, $d) Add-SPSLifecycleLockJournalEntry -Path $p -Url $u -SiteId $s -LockedOn $l -Delimiter ([char]$d) } $Path $Url $SiteId $At $Delimiter
    }

    # What a user gets after Set-Location: the location of the PowerShell session moves, the working directory of
    # the process does not. Both are put back afterwards.
    function script:Invoke-InDivergedLocation {
        param([string]$Location, [string]$ProcessDirectory, [scriptblock]$Script)
        $previousLocation = (Get-Location).Path
        $previousDirectory = [System.IO.Directory]::GetCurrentDirectory()
        try {
            [System.IO.Directory]::SetCurrentDirectory($ProcessDirectory)
            Set-Location -LiteralPath $Location
            & $Script
        }
        finally {
            Set-Location -LiteralPath $previousLocation
            [System.IO.Directory]::SetCurrentDirectory($previousDirectory)
        }
    }
}

Describe 'Add-SPSLifecycleLockJournalEntry' {
    BeforeEach {
        $script:Folder = New-TestFolder
        $script:Journal = Join-Path -Path $script:Folder -ChildPath 'lock-journal.csv'
    }

    Context 'A journal that does not exist yet' {
        It 'creates it with a byte order mark, a header and the row, in the columns that the reader needs' {
            $path = Add-TestEntry -Path $script:Journal

            $path | Should -BeExactly $script:Journal
            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29T14:37:39Z`r`n"
        }

        It 'uses the separator that it is given' -ForEach @(
            @{ Name = 'a semicolon'; Delimiter = ';' }
            @{ Name = 'a tab'; Delimiter = "`t" }
        ) {
            $null = Add-TestEntry -Path $script:Journal -Delimiter $Delimiter

            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}Url${Delimiter}SiteId${Delimiter}LockedOn`r`nhttps://contoso.sharepoint.com/sites/a${Delimiter}$($script:SiteA)${Delimiter}2026-10-29T14:37:39Z`r`n"
        }

        It 'creates the folder, and its parents, when they are missing' {
            $deep = Join-Path -Path $script:Folder -ChildPath 'a/b/lock-journal.csv'

            $null = Add-TestEntry -Path $deep

            Test-Path -LiteralPath $deep | Should -BeTrue
        }

        It 'writes the header into a file that exists and is empty' {
            [System.IO.File]::WriteAllBytes($script:Journal, [byte[]]@())

            $null = Add-TestEntry -Path $script:Journal

            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29T14:37:39Z`r`n"
        }
    }

    Context 'A journal that exists' {
        It 'adds a row and keeps one header and one byte order mark, however many rows it adds' {
            $null = Add-TestEntry -Path $script:Journal
            $null = Add-TestEntry -Path $script:Journal -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -At $script:LockedOn.AddDays(1)
            $null = Add-TestEntry -Path $script:Journal -Url 'https://contoso.sharepoint.com/sites/c' -SiteId $script:SiteC -At $script:LockedOn.AddDays(2)

            $text = Read-TestText -Path $script:Journal
            @($text.ToCharArray() | Where-Object { $_ -eq [char]0xFEFF }) | Should -HaveCount 1
            @([regex]::Matches($text, 'Url,SiteId,LockedOn')) | Should -HaveCount 1
            @($text -split "`r`n" | Where-Object { $_ }) | Should -HaveCount 4
        }

        It 'follows the separator of the file, not the one it is given' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/z;$($script:SiteC);2026-01-01`r`n"

            $null = Add-TestEntry -Path $script:Journal -Delimiter ','

            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/z;$($script:SiteC);2026-01-01`r`nhttps://contoso.sharepoint.com/sites/a;$($script:SiteA);2026-10-29T14:37:39Z`r`n"
        }

        It 'starts a new line when the file does not end with one' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/z,$($script:SiteC),2026-01-01"

            $null = Add-TestEntry -Path $script:Journal

            $rows = @(Import-TestJournal -Path $script:Journal).Entries
            $rows | Should -HaveCount 2
        }

        It 'finds the header after the blank lines that a spreadsheet leaves before it, as the reader does' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "`r`n`r`nUrl,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/z,$($script:SiteC),2026-01-01`r`n"

            $null = Add-TestEntry -Path $script:Journal

            @(Import-TestJournal -Path $script:Journal).Entries | Should -HaveCount 2
        }

        It 'does not add a byte order mark to a file that has none' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Encoding utf8 -Text "Url,SiteId,LockedOn`r`n"

            $null = Add-TestEntry -Path $script:Journal

            $bytes = [System.IO.File]::ReadAllBytes($script:Journal)
            $bytes[0] | Should -Be ([byte][char]'U')
            @($bytes | Where-Object { $_ -eq 0xEF }) | Should -HaveCount 0
        }

        It 'puts each value under its own column when a person moved the columns and added one' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Note;LockedOn;Url;SiteId`r`nlot 1;2026-01-01;https://contoso.sharepoint.com/sites/z;$($script:SiteC)`r`n"

            $null = Add-TestEntry -Path $script:Journal

            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}Note;LockedOn;Url;SiteId`r`nlot 1;2026-01-01;https://contoso.sharepoint.com/sites/z;$($script:SiteC)`r`n;2026-10-29T14:37:39Z;https://contoso.sharepoint.com/sites/a;$($script:SiteA)`r`n"
        }

        It 'reads the names of the columns the way the reader does: spaces and case do not count' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "url ; SITEID ; lockedon`r`n"

            $null = Add-TestEntry -Path $script:Journal

            @(Import-TestJournal -Path $script:Journal).Entries | Should -HaveCount 1
        }

        It 'follows a first line sep= that Excel may add' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "sep=;`r`nUrl;SiteId;LockedOn`r`n"

            $null = Add-TestEntry -Path $script:Journal -Delimiter ','

            Read-TestText -Path $script:Journal | Should -BeExactly "`u{FEFF}sep=;`r`nUrl;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;$($script:SiteA);2026-10-29T14:37:39Z`r`n"
        }

        It 'adds to a file that French Excel saved as Windows-1252 when the file holds only ASCII' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Encoding cp1252 -Text "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/z;$($script:SiteC);01/01/2026`r`n"

            $null = Add-TestEntry -Path $script:Journal

            $entries = @(Import-TestJournal -Path $script:Journal -DateFormat 'dd/MM/yyyy').Entries
            $entries | Should -HaveCount 2
        }

        It 'adds to a file whose quoted fields hold a separator, a line break and doubled quotes' {
            $null = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/z,$($script:SiteC),2026-01-01,`"a, `"`"b`"`"`r`nc`"`r`n"

            $null = Add-TestEntry -Path $script:Journal

            @(Import-TestJournal -Path $script:Journal).Entries | Should -HaveCount 2
        }

        It 'adds to a file in which a quoted field straddles the pieces that the tool reads it in' {
            $note = '"' + ('n' * 70000) + '"'
            $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/z,$($script:SiteC),2026-01-01,$note`r`n"

            $null = Add-TestEntry -Path $path

            @(Import-TestJournal -Path $path).Entries | Should -HaveCount 2
        }

        It 'quotes a URL that holds the separator' {
            $null = Add-TestEntry -Path $script:Journal -Url 'https://contoso.sharepoint.com/sites/a,b'

            @(Import-TestJournal -Path $script:Journal).Entries[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a,b'
        }
    }

    Context 'A file that it must not touch' {
        It 'refuses <Name>, says so, and leaves the file as it was' -ForEach @(
            @{ Name = 'UTF-16'; Encoding = 'utf16'; Text = "Url,SiteId,LockedOn`r`n"; Message = '*not UTF-8*' }
            @{ Name = 'Windows-1252 with an accented letter'; Encoding = 'cp1252'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/équipe;3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708;2026-01-01`r`n"; Message = '*not UTF-8*' }
            @{ Name = 'a file with another header'; Encoding = 'utf8bom'; Text = "Name,Size`r`nSales,12`r`n"; Message = '*not a lock journal*' }
            @{ Name = 'a header that lacks the site ID'; Encoding = 'utf8bom'; Text = "Url,LockedOn`r`n"; Message = '*SiteId*' }
            @{ Name = 'a header with a column twice'; Encoding = 'utf8bom'; Text = "Url,SiteId,LockedOn,Url`r`n"; Message = '*more than once*' }
            @{ Name = 'a header whose name only looks like SiteId'; Encoding = 'utf8bom'; Text = "Url,Site$([char]0xAD)Id,LockedOn`r`n"; Message = "*Site\u00ADId*looks like 'SiteId'*" }
            @{ Name = 'a file that ends inside a quoted field'; Encoding = 'utf8bom'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2024-02-01,`"unfinished"; Message = '*CSV rules*' }
            @{ Name = 'a stray quote, then a quote that is never closed (an even number of quotes)'; Encoding = 'utf8bom'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2024-01-01,stray`"quote`r`nhttps://contoso.sharepoint.com/sites/a,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2024-02-01,`"unfinished"; Message = '*line 2*CSV rules*' }
            @{ Name = 'a column named Site ID'; Encoding = 'utf8bom'; Text = "Url,Site ID,LockedOn`r`n"; Message = "*looks like 'SiteId'*" }
            @{ Name = 'a quote that swallows the rows after it'; Encoding = 'utf8bom'; Text = "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2024-02-01,`"open`r`nhttps://contoso.sharepoint.com/sites/b,0d7b4ebb-f68c-4f29-8529-5b46655d0c3c,2024-03-01,x`r`n"; Message = '*CSV rules*' }
        ) {
            $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text $Text -Encoding $Encoding
            $before = [System.IO.File]::ReadAllBytes($path)

            { Add-TestEntry -Path $path } | Should -Throw -ExpectedMessage $Message

            [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        }

        It 'refuses a file that was cut in the middle of a letter, and leaves it as it was' {
            $path = Join-Path -Path $script:Folder -ChildPath 'lock-journal.csv'
            [System.IO.File]::WriteAllBytes($path, [byte[]]@([System.Text.Encoding]::ASCII.GetBytes("Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/") + [byte]0xC3))
            $before = [System.IO.File]::ReadAllBytes($path)

            { Add-TestEntry -Path $path } | Should -Throw -ExpectedMessage '*not UTF-8*'

            [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        }

        It 'accepts a UTF-8 file in which a letter straddles the pieces that the tool reads it in' {
            $header = "Url,SiteId,LockedOn`r`n"
            $start = 'https://contoso.sharepoint.com/sites/'
            $padding = 'x' * (65535 - $header.Length - $start.Length)
            $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Encoding utf8 -Text "$header$start${padding}é,$($script:SiteC),2026-01-01`r`n"
            [System.IO.File]::ReadAllBytes($path)[65535] | Should -Be 0xC3 -Because 'the first byte of the letter must be the last byte of the first piece'

            $null = Add-TestEntry -Path $path

            @(Import-TestJournal -Path $path).Entries | Should -HaveCount 2
        }

        It 'says that the file is probably open in another program, and writes nothing, when it is locked' {
            $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`n"
            $before = [System.IO.File]::ReadAllBytes($path)
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                { Add-TestEntry -Path $path } | Should -Throw -ExpectedMessage '*open in another program*'
            }
            finally {
                $stream.Dispose()
            }

            [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        }
    }

    Context 'What it refuses to write' {
        It 'refuses <Name>, and creates no file' -ForEach @(
            @{ Name = 'a URL that is not a web address'; Url = 'sites/a'; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*web address*' }
            @{ Name = 'a URL with a zero-width space'; Url = "https://contoso.sharepoint.com/sites/a$([char]0x200B)"; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*web address*\u200B*' }
            @{ Name = 'a URL that is only a zero-width space'; Url = [string][char]0x200B; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*web address*' }
            @{ Name = 'a URL on two lines'; Url = "https://contoso.sharepoint.com/sites/a`r`nhttps://contoso.sharepoint.com/sites/b"; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*web address*' }
            @{ Name = 'a URL with a space'; Url = 'https://contoso.sharepoint.com/sites/a b'; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; Message = '*web address*' }
            @{ Name = 'a site ID that is not a GUID'; Url = 'https://contoso.sharepoint.com/sites/a'; SiteId = 'not a guid'; Message = '*site ID*' }
            @{ Name = 'a site ID of zeros'; Url = 'https://contoso.sharepoint.com/sites/a'; SiteId = '00000000-0000-0000-0000-000000000000'; Message = '*site ID*' }
        ) {
            { Add-TestEntry -Path $script:Journal -Url $Url -SiteId $SiteId } | Should -Throw -ExpectedMessage $Message

            Test-Path -LiteralPath $script:Journal | Should -BeFalse
        }
    }

    Context 'What it writes' {
        It 'writes the date in ISO 8601 in UTC, whatever the kind of the date' -ForEach @(
            @{ Name = 'UTC'; At = [System.DateTime]::new(2026, 10, 29, 14, 37, 39, [System.DateTimeKind]::Utc); Expected = '2026-10-29T14:37:39Z' }
            @{ Name = 'unspecified'; At = [System.DateTime]::new(2026, 10, 29, 14, 37, 39); Expected = '2026-10-29T14:37:39Z' }
            @{ Name = 'midnight'; At = [System.DateTime]::new(2026, 10, 29, 0, 0, 0, [System.DateTimeKind]::Utc); Expected = '2026-10-29' }
            @{ Name = 'an offset date'; At = [System.DateTimeOffset]::new(2026, 10, 29, 16, 37, 39, [System.TimeSpan]::FromHours(2)).UtcDateTime; Expected = '2026-10-29T14:37:39Z' }
        ) {
            $null = Add-TestEntry -Path $script:Journal -At $At

            (Read-TestText -Path $script:Journal) | Should -Match ([regex]::Escape(",$Expected`r`n"))
        }

        It 'converts a local date to UTC' {
            $local = [System.DateTime]::SpecifyKind([System.DateTime]::new(2026, 10, 29, 16, 37, 39), [System.DateTimeKind]::Local)

            $null = Add-TestEntry -Path $script:Journal -At $local

            $expected = $local.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) + 'Z'
            (Read-TestText -Path $script:Journal) | Should -Match ([regex]::Escape(",$expected`r`n"))
        }

        It 'writes a site ID in the form that the reader normalizes to' {
            $null = Add-TestEntry -Path $script:Journal -SiteId '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}'

            (Read-TestText -Path $script:Journal) | Should -Match ([regex]::Escape(",$($script:SiteA),"))
        }
    }

    Context 'A round trip through the reader, whatever the culture' -ForEach @(
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

        It 'reads back what it wrote, with the separator <Name>' -ForEach @(
            @{ Name = 'comma'; Delimiter = ',' }
            @{ Name = 'semicolon'; Delimiter = ';' }
            @{ Name = 'tab'; Delimiter = "`t" }
        ) {
            $null = Add-TestEntry -Path $script:Journal -Delimiter $Delimiter
            $null = Add-TestEntry -Path $script:Journal -Url 'https://contoso.sharepoint.com/sites/b' -SiteId $script:SiteB -At $script:LockedOn.AddDays(1) -Delimiter $Delimiter

            $journal = Import-TestJournal -Path $script:Journal
            $a = $journal.Entries | Where-Object { $_.SiteId -eq $script:SiteA }
            $b = $journal.Entries | Where-Object { $_.SiteId -eq $script:SiteB }

            $journal.Entries | Should -HaveCount 2
            $a.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $a.LockedOn.ToString('o') | Should -Be '2026-10-29T14:37:39.0000000Z'
            $b.LockedOn.ToString('o') | Should -Be '2026-10-30T14:37:39.0000000Z'
        }
    }

    Context 'Where it writes' {
        It 'writes in the folder of the session location, not in the working directory of the process' {
            $location = New-TestFolder
            $processDirectory = New-TestFolder

            $path = Invoke-InDivergedLocation -Location $location -ProcessDirectory $processDirectory -Script {
                Add-TestEntry -Path 'lock-journal.csv'
            }

            $path | Should -BeExactly ([System.IO.Path]::GetFullPath((Join-Path -Path $location -ChildPath 'lock-journal.csv')))
            @(Get-ChildItem -LiteralPath $processDirectory -Force) | Should -HaveCount 0
        }

        It 'refuses a path of another provider' {
            { Add-TestEntry -Path 'Variable:/lock-journal.csv' } | Should -Throw -ExpectedMessage '*not a path of the file system*'
        }
    }
}
