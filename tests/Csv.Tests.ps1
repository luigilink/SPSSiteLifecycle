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
        param([string]$Path, [string[]]$Required = @(), [string[]]$Optional = @())
        & $script:Module { param($p, $r, $o) Read-SPSLifecycleCsv -Path $p -RequiredColumn $r -OptionalColumn $o } $Path $Required $Optional
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

    Context 'Header names' {
        It 'trims the spaces around a header name, <Name>, so that the column can be read' -ForEach @(
            @{ Name = 'quoted'; Header = 'Url;"LockedOn "' }
            @{ Name = 'unquoted'; Header = 'Url;LockedOn ' }
            @{ Name = 'at the start'; Header = 'Url; LockedOn' }
        ) {
            $path = Write-TestFile -Name 'spaces.csv' -Byte (Get-TestByte -Text "$Header`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url', 'LockedOn')

            @($rows[0].PSObject.Properties.Name) -join '|' | Should -BeExactly 'Url|LockedOn'
            $rows[0].LockedOn | Should -Be '2025-09-18'
        }

        It 'stops when two columns have the same name once trimmed' {
            $path = Write-TestFile -Name 'dup.csv' -Byte (Get-TestByte -Text "Url;url ;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;x;2025-09-18`r`n")

            { Read-TestCsv -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*more than once*Url*'
        }

        It 'stops when a column appears twice' {
            $path = Write-TestFile -Name 'dup2.csv' -Byte (Get-TestByte -Text "Url;LockedOn;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18;2026-01-01`r`n")

            { Read-TestCsv -Path $path -Required 'Url' } | Should -Throw -ExpectedMessage '*more than once*LockedOn*'
        }

        It 'finds the header after blank lines' {
            $path = Write-TestFile -Name 'blank-first.csv' -Byte (Get-TestByte -Text "`r`n  `r`nUrl;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url', 'LockedOn')

            $rows | Should -HaveCount 1
            $rows[0].LockedOn | Should -Be '2025-09-18'
        }

        It 'reads a header that has an empty name and a quote in a name' {
            $path = Write-TestFile -Name 'odd.csv' -Byte (Get-TestByte -Text "Url;`"Say `"`"hi`"`"`";`r`nhttps://contoso.sharepoint.com/sites/a;x;y`r`n")
            $rows = @(Read-TestCsv -Path $path -Required 'Url', 'Say "hi"')

            $rows[0].'Say "hi"' | Should -Be 'x'
        }

        It 'reads the rows of a large file as fast as before the header is rewritten' {
            $lines = foreach ($i in 1..20000) { "https://contoso.sharepoint.com/sites/site$i;2025-09-18" }
            $path = Write-TestFile -Name 'big.csv' -Byte (Get-TestByte -Text ("Url ;LockedOn`r`n" + ($lines -join "`r`n") + "`r`n"))
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $rows = @(Read-TestCsv -Path $path -Required 'Url')
            $watch.Stop()

            $rows | Should -HaveCount 20000
            $rows[19999].Url | Should -Be 'https://contoso.sharepoint.com/sites/site20000'
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 30
        }
    }

    Context 'Names that only look like the names that are required' {
        It 'does not take a name with a hidden character for a required column, and shows the character' {
            $path = Write-TestFile -Name 'hidden.csv' -Byte (Get-TestByte -Text "Url,Site$([char]0xAD)Id`r`nhttps://contoso.sharepoint.com/sites/a,x`r`n")

            { Read-TestCsv -Path $path -Required 'Url', 'SiteId' } | Should -Throw -ExpectedMessage "*Site\u00ADId*looks like 'SiteId'*"
        }

        It 'says that a required column is missing, and lists the columns that are there, when nothing looks like it' {
            $path = Write-TestFile -Name 'missing.csv' -Byte (Get-TestByte -Text "Url,Owner`r`nhttps://contoso.sharepoint.com/sites/a,x`r`n")

            { Read-TestCsv -Path $path -Required 'Url', 'SiteId' } | Should -Throw -ExpectedMessage '*not found*SiteId*Columns present: Url, Owner*'
        }

        It 'still finds a required column whatever its case and the spaces around its name' {
            $path = Write-TestFile -Name 'case.csv' -Byte (Get-TestByte -Text " URL ;siteid`r`nhttps://contoso.sharepoint.com/sites/a;x`r`n")

            @(Read-TestCsv -Path $path -Required 'Url', 'SiteId') | Should -HaveCount 1
        }
    }

    Context 'Optional columns that only look like the ones the tool knows' {
        It 'stops on <Name>, because the column would be read as absent and what it carries would be lost' -ForEach @(
            @{ Name = 'a name with a space'; Header = 'Site ID' }
            @{ Name = 'a name with an underscore'; Header = 'Site_Id' }
            @{ Name = 'a name with a soft hyphen'; Header = "Site$([char]0xAD)Id" }
            @{ Name = 'a name with a zero-width space'; Header = "Site$([char]0x200B)Id" }
            @{ Name = 'a name with a no-break space'; Header = "Site$([char]0xA0)Id" }
            @{ Name = 'a name with full-width letters'; Header = 'ＳｉｔｅＩｄ' }
            @{ Name = 'a name with an accent that is a separate character'; Header = "Site$([char]0x301)Id" }
            @{ Name = 'a name with a dot above that is a separate character'; Header = "SI$([char]0x307)TEID" }
            @{ Name = 'a name with a dotted capital I'; Header = "S$([char]0x130)TEID" }
        ) {
            $path = Write-TestFile -Name 'lookalike.csv' -Byte (Get-TestByte -Text "Url,$Header`r`nhttps://contoso.sharepoint.com/sites/a,x`r`n")

            { Read-TestCsv -Path $path -Required 'Url' -Optional 'SiteId' } | Should -Throw -ExpectedMessage "*looks like 'SiteId'*"
        }

        It 'reads a file that has the optional column, spelled as the tool expects, whatever its case' {
            $path = Write-TestFile -Name 'optional.csv' -Byte (Get-TestByte -Text "Url,SITEID`r`nhttps://contoso.sharepoint.com/sites/a,x`r`n")

            @(Read-TestCsv -Path $path -Required 'Url' -Optional 'SiteId') | Should -HaveCount 1
        }

        It 'reads a file that has no optional column at all, and columns that are not known' {
            $path = Write-TestFile -Name 'plain.csv' -Byte (Get-TestByte -Text "Url,Note,Owner Display Name`r`nhttps://contoso.sharepoint.com/sites/a,x,y`r`n")

            @(Read-TestCsv -Path $path -Required 'Url' -Optional 'SiteId') | Should -HaveCount 1
        }
    }

    Context 'Files' {
        It 'stops with a clear message when the file does not exist' {
            { Read-TestCsv -Path (Join-Path -Path $TestDrive -ChildPath 'nope.csv') } | Should -Throw -ExpectedMessage '*File not found*'
        }

        It 'says that the file is missing, and not that it is open, when it disappears after the check: <Name>' -ForEach @(
            @{ Name = 'the file'; Relative = 'vanished.csv' }
            @{ Name = 'its folder'; Relative = 'gone/vanished.csv' }
        ) {
            Mock -CommandName Test-Path -ModuleName $script:Module.Name -MockWith { $true }

            { Read-TestCsv -Path (Join-Path -Path $TestDrive -ChildPath $Relative) -Required 'Url' } | Should -Throw -ExpectedMessage '*File not found*'
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

Describe 'Test-SPSLifecycleColumnName' {
    It 'finds <Column> among the names, whatever the case' -ForEach @(
        @{ Column = 'SiteId' }
        @{ Column = 'siteid' }
        @{ Column = 'SITEID' }
    ) {
        (& $script:Module { param($c) Test-SPSLifecycleColumnName -Name 'Url', 'SiteId', 'LockedOn' -Column $c } $Column) | Should -BeTrue
    }

    It 'does not find a name that only looks like the column: <Name>' -ForEach @(
        @{ Name = 'a soft hyphen'; Text = "Site$([char]0xAD)Id" }
        @{ Name = 'a zero-width space'; Text = "Site$([char]0x200B)Id" }
        @{ Name = 'a no-break space'; Text = "Site$([char]0xA0)Id" }
        @{ Name = 'another name'; Text = 'SiteIds' }
    ) {
        (& $script:Module { param($t) Test-SPSLifecycleColumnName -Name 'Url', $t, 'LockedOn' -Column 'SiteId' } $Text) | Should -BeFalse
    }

    It 'finds nothing in an empty list of names' {
        (& $script:Module { Test-SPSLifecycleColumnName -Name @() -Column 'SiteId' }) | Should -BeFalse
    }

    It 'compares the same way whatever the culture: <Culture>' -ForEach @(
        @{ Culture = 'tr-TR' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            (& $script:Module { Test-SPSLifecycleColumnName -Name 'URL', 'SITEID' -Column 'Url' }) | Should -BeTrue
            (& $script:Module { Test-SPSLifecycleColumnName -Name "Site$([char]0xAD)Id" -Column 'SiteId' }) | Should -BeFalse
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }
}

Describe 'ConvertTo-SPSLifecycleVisibleText' {
    It 'writes <Name> as <Expected>' -ForEach @(
        @{ Name = 'a soft hyphen'; Text = "Site$([char]0xAD)Id"; Expected = 'Site\u00ADId' }
        @{ Name = 'a zero-width space'; Text = "a$([char]0x200B)b"; Expected = 'a\u200Bb' }
        @{ Name = 'a byte order mark'; Text = "$([char]0xFEFF)Url"; Expected = '\uFEFFUrl' }
        @{ Name = 'a control character'; Text = "a$([char]7)b"; Expected = 'a\u0007b' }
        @{ Name = 'a combining mark'; Text = "SI$([char]0x307)TEID"; Expected = 'SI\u0307TEID' }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleVisibleText -Text $t } $Text) | Should -BeExactly $Expected
    }

    It 'leaves a text that shows everything as it is: <Text>' -ForEach @(
        @{ Text = 'SiteId' }
        @{ Text = 'Équipe été' }
        @{ Text = 'a b' }
        @{ Text = '日本' }
        @{ Text = '' }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleVisibleText -Text $t } $Text) | Should -BeExactly $Text
    }

    It 'with AsciiOnly, writes <Name> as <Expected>, so that a letter that looks like another one can be told from it' -ForEach @(
        @{ Name = 'the Kelvin sign'; Text = "cont$([char]0x212A)so"; Expected = 'cont\u212Aso' }
        @{ Name = 'a capital I with a dot above'; Text = "cont$([char]0x0130)so"; Expected = 'cont\u0130so' }
        @{ Name = 'a dotless i'; Text = "cont$([char]0x0131)so"; Expected = 'cont\u0131so' }
        @{ Name = 'a full-width letter'; Text = "cont$([char]0xFF4F)so"; Expected = 'cont\uFF4Fso' }
        @{ Name = 'an accented letter'; Text = 'Équipe'; Expected = '\u00C9quipe' }
        @{ Name = 'a soft hyphen'; Text = "a$([char]0xAD)b"; Expected = 'a\u00ADb' }
        @{ Name = 'a control character'; Text = "a$([char]7)b"; Expected = 'a\u0007b' }
        @{ Name = 'a tab'; Text = "a`tb"; Expected = 'a\u0009b' }
        @{ Name = 'a character after the last printable one of ASCII'; Text = "a$([char]0x7F)b"; Expected = 'a\u007Fb' }
        @{ Name = 'a character outside the Basic Multilingual Plane, as its two halves'; Text = "a$([char]::ConvertFromUtf32(0x1F600))b"; Expected = 'a\uD83D\uDE00b' }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleVisibleText -Text $t -AsciiOnly } $Text) | Should -BeExactly $Expected
    }

    It 'with AsciiOnly, leaves the printable characters of ASCII and the spaces as they are: <Text>' -ForEach @(
        @{ Text = 'Contoso-1' }
        @{ Text = 'a b' }
        @{ Text = '~!@#$%^&*()_+{}|:"<>?`-=[]\;'',./' }
        @{ Text = '' }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleVisibleText -Text $t -AsciiOnly } $Text) | Should -BeExactly $Text
    }

    It 'with AsciiOnly, gives an empty text for a null' {
        (& $script:Module { ConvertTo-SPSLifecycleVisibleText -Text $null -AsciiOnly }) | Should -BeExactly ''
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

Describe 'ConvertTo-SPSLifecycleBoolean' {
    It 'reads <Text> as true' -ForEach @(
        @{ Text = 'True' }, @{ Text = 'TRUE' }, @{ Text = ' true ' }, @{ Text = '1' }, @{ Text = 'Yes' }
        @{ Text = 'VRAI' }, @{ Text = 'Oui' }, @{ Text = 'WAHR' }, @{ Text = 'Ja' }
        @{ Text = 'VERDADERO' }, @{ Text = 'VERDADEIRO' }, @{ Text = 'VERO' }, @{ Text = 'WAAR' }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleBoolean -Text $t } $Text) | Should -BeTrue
    }

    It 'reads <Text> as false' -ForEach @(
        @{ Text = 'False' }, @{ Text = 'FALSE' }, @{ Text = ' false ' }, @{ Text = '0' }, @{ Text = 'No' }
        @{ Text = 'FAUX' }, @{ Text = 'Non' }, @{ Text = 'FALSCH' }, @{ Text = 'Nein' }
        @{ Text = 'FALSO' }, @{ Text = 'ONWAAR' }
    ) {
        $result = & $script:Module { param($t) ConvertTo-SPSLifecycleBoolean -Text $t } $Text

        $result | Should -BeFalse
        $result | Should -Not -BeNullOrEmpty -Because 'false must not be confused with an empty value'
    }

    It 'gives $null for <Name>' -ForEach @(
        @{ Name = 'an empty text'; Text = '' }
        @{ Name = 'spaces'; Text = '   ' }
        @{ Name = 'a null'; Text = $null }
    ) {
        (& $script:Module { param($t) ConvertTo-SPSLifecycleBoolean -Text $t } $Text) | Should -BeNullOrEmpty
    }

    It 'refuses <Text>, which is neither true nor false, and names it' -ForEach @(
        @{ Text = 'maybe' }, @{ Text = '2' }, @{ Text = 'Tru' }, @{ Text = 'SANT' }
    ) {
        { & $script:Module { param($t) ConvertTo-SPSLifecycleBoolean -Text $t } $Text } | Should -Throw -ExpectedMessage "*'$Text'*True*False*"
    }

    It 'reads the same way under <Culture>' -ForEach @(
        @{ Culture = 'en-US' }, @{ Culture = 'fr-FR' }, @{ Culture = 'de-DE' }, @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            $values = & $script:Module { @((ConvertTo-SPSLifecycleBoolean -Text 'TRUE'), (ConvertTo-SPSLifecycleBoolean -Text 'FALSCH'), (ConvertTo-SPSLifecycleBoolean -Text 'VRAI'), (ConvertTo-SPSLifecycleBoolean -Text 'FAUX')) }
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }

        ($values -join ',') | Should -Be 'True,False,True,False'
    }
}

Describe 'ConvertFrom-SPSLifecycleCsvByte' {
    BeforeAll {
        function script:ConvertFrom-TestByte {
            param([byte[]]$Byte, [switch]$Strict, [switch]$StrictAfterMark)
            if ($StrictAfterMark) {
                return & $script:Module { param($b) ConvertFrom-SPSLifecycleCsvByte -Bytes $b -StrictAfterMark } $Byte
            }

            & $script:Module { param($b, $s) ConvertFrom-SPSLifecycleCsvByte -Bytes $b -Strict:$s } $Byte ([bool]$Strict)
        }

        function script:ConvertTo-TestCode {
            param([string]$Text)
            # -BeExactly compares with the rules of the culture, which ignore a byte order mark: the code units are compared instead.
            (($Text.ToCharArray() | ForEach-Object { '{0:X4}' -f [System.Int32]$_ }) -join ' ')
        }

        function script:Test-DecoderRefusal {
            param([byte[]]$Byte, [switch]$StrictAfterMark)
            $thrown = $null
            try {
                $null = if ($StrictAfterMark) { ConvertFrom-TestByte -Byte $Byte -StrictAfterMark } else { ConvertFrom-TestByte -Byte $Byte -Strict }
            }
            catch {
                $thrown = $_.Exception
            }

            ($thrown -is [System.Text.DecoderFallbackException]) -or ($thrown.InnerException -is [System.Text.DecoderFallbackException])
        }
    }

    Context 'Without Strict, as a file that a person gives is read' {
        It 'replaces a byte that is not UTF-8 after a UTF-8 byte order mark' {
            ConvertTo-TestCode (ConvertFrom-TestByte -Byte ([byte[]]@(0xEF, 0xBB, 0xBF, 0x61, 0xFF, 0x62))) | Should -BeExactly '0061 FFFD 0062'
        }

        It 'reads a file without a mark that is not UTF-8 as Windows-1252' {
            ConvertTo-TestCode (ConvertFrom-TestByte -Byte ([byte[]]@(0x61, 0xE9))) | Should -BeExactly '0061 00E9'
        }

        It 'reads UTF-16 with a byte order mark' {
            (ConvertFrom-TestByte -Byte ([System.Text.UnicodeEncoding]::new($false, $true).GetPreamble() + [System.Text.UnicodeEncoding]::new($false, $false).GetBytes('ab'))) | Should -BeExactly 'ab'
        }
    }

    Context 'With Strict, as a file in which a character must not change is read' {
        It 'reads UTF-8 with a byte order mark, and drops the mark' {
            $text = ConvertFrom-TestByte -Strict -Byte ([byte[]]@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("Url,é$([char]0x65E5)"))

            ConvertTo-TestCode $text | Should -BeExactly (ConvertTo-TestCode "Url,é$([char]0x65E5)")
        }

        It 'reads UTF-8 without a byte order mark, ASCII, and nothing' {
            ConvertTo-TestCode (ConvertFrom-TestByte -Strict -Byte ([System.Text.Encoding]::UTF8.GetBytes('Équipe'))) | Should -BeExactly (ConvertTo-TestCode 'Équipe')
            ConvertTo-TestCode (ConvertFrom-TestByte -Strict -Byte ([System.Text.Encoding]::ASCII.GetBytes('Url'))) | Should -BeExactly (ConvertTo-TestCode 'Url')
            ConvertTo-TestCode (ConvertFrom-TestByte -Strict -Byte ([byte[]]@())) | Should -BeExactly ''
        }

        It 'reads a file that is only a byte order mark as an empty text' {
            ConvertTo-TestCode (ConvertFrom-TestByte -Strict -Byte ([byte[]]@(0xEF, 0xBB, 0xBF))) | Should -BeExactly ''
        }

        It 'keeps a second byte order mark, which is a character of the text' {
            ConvertTo-TestCode (ConvertFrom-TestByte -Strict -Byte ([byte[]]@(0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x55))) | Should -BeExactly 'FEFF 0055'
        }

        It 'refuses <Name>' -ForEach @(
            @{ Name = 'a byte that is not UTF-8 after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0x61, 0xFF, 0x62) }
            @{ Name = 'a byte that is not UTF-8 without a byte order mark'; Byte = [byte[]]@(0x61, 0xFF, 0x62) }
            @{ Name = 'Windows-1252 with an accented letter'; Byte = [byte[]]@(0x61, 0xE9) }
            @{ Name = 'a sequence cut short at the end'; Byte = [byte[]]@(0x61, 0xC3) }
            @{ Name = 'an overlong sequence'; Byte = [byte[]]@(0xC0, 0xAF) }
            @{ Name = 'half of a surrogate pair'; Byte = [byte[]]@(0xED, 0xA0, 0x80) }
            @{ Name = 'UTF-16 with a byte order mark'; Byte = [byte[]]@(0xFF, 0xFE, 0x61, 0x00) }
            @{ Name = 'UTF-16 big endian with a byte order mark'; Byte = [byte[]]@(0xFE, 0xFF, 0x00, 0x61) }
            @{ Name = 'a byte order mark that is cut short'; Byte = [byte[]]@(0xEF, 0xBB) }
            @{ Name = 'two bytes of a byte order mark and a letter'; Byte = [byte[]]@(0xEF, 0xBB, 0x41, 0x42) }
            @{ Name = 'the last two bytes of a byte order mark after a letter'; Byte = [byte[]]@(0x41, 0xBB, 0xBF) }
            @{ Name = 'the last byte of a byte order mark after two letters'; Byte = [byte[]]@(0x41, 0x42, 0xBF) }
        ) {
            (Test-DecoderRefusal -Byte $Byte) | Should -BeTrue
        }
    }

    Context 'A byte order mark is the whole mark, whatever the way that the file is read' {
        It 'does not take <Name> for a mark: <Mode>' -ForEach @(
            foreach ($mode in 'tolerant', 'marked') {
                @{ Mode = $mode; Name = 'the first two bytes of the UTF-8 mark'; Byte = [byte[]]@(0xEF, 0xBB); Expected = '00EF 00BB' }
                @{ Mode = $mode; Name = 'the first two bytes of the UTF-8 mark and two letters'; Byte = [byte[]]@(0xEF, 0xBB, 0x41, 0x42); Expected = '00EF 00BB 0041 0042' }
                @{ Mode = $mode; Name = 'the first byte of the UTF-8 mark and two letters'; Byte = [byte[]]@(0xEF, 0x41, 0x42); Expected = '00EF 0041 0042' }
                @{ Mode = $mode; Name = 'the last two bytes of the UTF-8 mark after a letter'; Byte = [byte[]]@(0x41, 0xBB, 0xBF); Expected = '0041 00BB 00BF' }
                @{ Mode = $mode; Name = 'a letter between the first and the last bytes of the UTF-8 mark'; Byte = [byte[]]@(0xEF, 0x41, 0xBF); Expected = '00EF 0041 00BF' }
                @{ Mode = $mode; Name = 'one byte of the UTF-16 little endian mark'; Byte = [byte[]]@(0xFF); Expected = '00FF' }
                @{ Mode = $mode; Name = 'the first byte of the UTF-16 little endian mark and a letter'; Byte = [byte[]]@(0xFF, 0x41); Expected = '00FF 0041' }
                @{ Mode = $mode; Name = 'the last byte of the UTF-16 little endian mark after a letter'; Byte = [byte[]]@(0x41, 0xFE); Expected = '0041 00FE' }
                @{ Mode = $mode; Name = 'the first byte of the UTF-16 little endian mark twice'; Byte = [byte[]]@(0xFF, 0xFF); Expected = '00FF 00FF' }
                @{ Mode = $mode; Name = 'one byte of the UTF-16 big endian mark'; Byte = [byte[]]@(0xFE); Expected = '00FE' }
                @{ Mode = $mode; Name = 'the first byte of the UTF-16 big endian mark and a letter'; Byte = [byte[]]@(0xFE, 0x41); Expected = '00FE 0041' }
                @{ Mode = $mode; Name = 'the last byte of the UTF-16 big endian mark after a letter'; Byte = [byte[]]@(0x41, 0xFF); Expected = '0041 00FF' }
                @{ Mode = $mode; Name = 'the first byte of the UTF-16 big endian mark twice'; Byte = [byte[]]@(0xFE, 0xFE); Expected = '00FE 00FE' }
            }
        ) {
            $text = if ($Mode -eq 'marked') { ConvertFrom-TestByte -StrictAfterMark -Byte $Byte } else { ConvertFrom-TestByte -Byte $Byte }

            ConvertTo-TestCode $text | Should -BeExactly $Expected
        }

        It 'reads a file that is only a byte order mark as an empty text, for each mark: <Mode>' -ForEach @(
            foreach ($mode in 'tolerant', 'marked') {
                @{ Mode = $mode; Byte = [byte[]]@(0xEF, 0xBB, 0xBF) }
                @{ Mode = $mode; Byte = [byte[]]@(0xFF, 0xFE) }
                @{ Mode = $mode; Byte = [byte[]]@(0xFE, 0xFF) }
            }
        ) {
            $text = if ($Mode -eq 'marked') { ConvertFrom-TestByte -StrictAfterMark -Byte $Byte } else { ConvertFrom-TestByte -Byte $Byte }

            ConvertTo-TestCode $text | Should -BeExactly ''
        }
    }

    Context 'With StrictAfterMark, as a list that a person gives is read, where a byte order mark is a declaration' {
        It 'reads UTF-8 with a byte order mark, and drops the mark' {
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte ([byte[]]@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("Url,é$([char]0x65E5)"))) | Should -BeExactly (ConvertTo-TestCode "Url,é$([char]0x65E5)")
        }

        It 'reads UTF-16 with a byte order mark, little endian and big endian, and drops the mark' {
            $little = [System.Text.UnicodeEncoding]::new($false, $true).GetPreamble() + [System.Text.UnicodeEncoding]::new($false, $false).GetBytes("a$([char]0x00E9)b")
            $big = [System.Text.UnicodeEncoding]::new($true, $true).GetPreamble() + [System.Text.UnicodeEncoding]::new($true, $false).GetBytes("a$([char]0x00E9)b")

            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte $little) | Should -BeExactly (ConvertTo-TestCode "a$([char]0x00E9)b")
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte $big) | Should -BeExactly (ConvertTo-TestCode "a$([char]0x00E9)b")
        }

        It 'reads a surrogate pair that is whole, in UTF-16' {
            $bytes = [System.Text.UnicodeEncoding]::new($false, $true).GetPreamble() + [System.Text.UnicodeEncoding]::new($false, $false).GetBytes("a$([char]::ConvertFromUtf32(0x1F600))")

            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte $bytes) | Should -BeExactly (ConvertTo-TestCode "a$([char]::ConvertFromUtf32(0x1F600))")
        }

        It 'keeps the guess of a file that has no mark: UTF-8, and Windows-1252 when it is not UTF-8' {
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte ([System.Text.Encoding]::UTF8.GetBytes('Équipe'))) | Should -BeExactly (ConvertTo-TestCode 'Équipe')
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte ([byte[]]@(0x61, 0xE9))) | Should -BeExactly '0061 00E9'
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte ([byte[]]@(0x61, 0xFF, 0x62))) | Should -BeExactly '0061 00FF 0062'
            ConvertTo-TestCode (ConvertFrom-TestByte -StrictAfterMark -Byte ([byte[]]@())) | Should -BeExactly ''
        }

        It 'refuses, instead of replacing it by U+FFFD, <Name>, because the mark says what the file is and a byte that does not fit is a damage' -ForEach @(
            @{ Name = 'a byte that is not UTF-8 after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0x61, 0xFF, 0x62) }
            @{ Name = 'a sequence cut short after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0x61, 0xC3) }
            @{ Name = 'an overlong sequence after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0xC0, 0xAF) }
            @{ Name = 'half of a surrogate pair after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0xED, 0xA0, 0x80) }
            @{ Name = 'Windows-1252 with an accented letter after a UTF-8 byte order mark'; Byte = [byte[]]@(0xEF, 0xBB, 0xBF, 0x61, 0xE9) }
            @{ Name = 'a lone high surrogate in UTF-16 little endian'; Byte = [byte[]]@(0xFF, 0xFE, 0x61, 0x00, 0x00, 0xD8, 0x62, 0x00) }
            @{ Name = 'a lone low surrogate in UTF-16 little endian'; Byte = [byte[]]@(0xFF, 0xFE, 0x61, 0x00, 0x00, 0xDC, 0x62, 0x00) }
            @{ Name = 'a byte that is left over at the end of UTF-16 little endian'; Byte = [byte[]]@(0xFF, 0xFE, 0x61, 0x00, 0x62) }
            @{ Name = 'a lone high surrogate in UTF-16 big endian'; Byte = [byte[]]@(0xFE, 0xFF, 0x00, 0x61, 0xD8, 0x00, 0x00, 0x62) }
            @{ Name = 'a byte that is left over at the end of UTF-16 big endian'; Byte = [byte[]]@(0xFE, 0xFF, 0x00, 0x61, 0x00) }
        ) {
            (Test-DecoderRefusal -Byte $Byte -StrictAfterMark) | Should -BeTrue
        }

        It 'cannot be given with Strict: one says UTF-8 only, the other reads a list' {
            { & $script:Module { ConvertFrom-SPSLifecycleCsvByte -Bytes ([byte[]]@(0x61)) -Strict -StrictAfterMark } } | Should -Throw
        }
    }
}
