BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    function script:ConvertFrom-TestStrictCsv {
        param([string]$Text, [char]$Delimiter = ',', [int]$FirstLine = 1, [switch]$SkipBlank, [int]$First = 0, [switch]$ValidateOnly)
        & $script:Module {
            param($t, $d, $l, $s, $f, $v)
            ConvertFrom-SPSLifecycleStrictCsv -Text $t -Delimiter $d -FirstLine $l -Source 'test.csv' -SkipBlank:$s -First $f -ValidateOnly:$v
        } $Text $Delimiter $FirstLine ([bool]$SkipBlank) $First ([bool]$ValidateOnly)
    }

    function script:Join-TestFields {
        param([string[]]$Field)
        $Field -join '|'
    }
}

Describe 'ConvertFrom-SPSLifecycleStrictCsv' {
    Context 'What it reads' {
        It 'reads the records of a file separated by <Name>' -ForEach @(
            @{ Name = 'commas'; Delimiter = ','; Text = "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,x,2025-09-18`r`n" }
            @{ Name = 'semicolons'; Delimiter = ';'; Text = "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;x;2025-09-18`r`n" }
            @{ Name = 'tabs'; Delimiter = "`t"; Text = "Url`tSiteId`tLockedOn`r`nhttps://contoso.sharepoint.com/sites/a`tx`t2025-09-18`r`n" }
        ) {
            $records = @(ConvertFrom-TestStrictCsv -Text $Text -Delimiter $Delimiter)

            $records | Should -HaveCount 2
            Join-TestFields $records[0].Fields | Should -BeExactly 'Url|SiteId|LockedOn'
            Join-TestFields $records[1].Fields | Should -BeExactly 'https://contoso.sharepoint.com/sites/a|x|2025-09-18'
        }

        It 'reads quoted fields that hold a separator, a line break and doubled quotes' {
            $text = "a,`"b, c`",`"d`"`"e`"`"`",`"f`r`ng`"`r`n"

            $records = @(ConvertFrom-TestStrictCsv -Text $text)

            $records | Should -HaveCount 1
            $records[0].Fields | Should -HaveCount 4
            $records[0].Fields[1] | Should -BeExactly 'b, c'
            $records[0].Fields[2] | Should -BeExactly 'd"e"'
            $records[0].Fields[3] | Should -BeExactly "f`r`ng"
        }

        It 'reads the line ends <Name>' -ForEach @(
            @{ Name = 'CRLF'; End = "`r`n" }
            @{ Name = 'LF'; End = "`n" }
            @{ Name = 'CR'; End = "`r" }
        ) {
            $records = @(ConvertFrom-TestStrictCsv -Text "a,b${End}c,d${End}e,f")

            $records | Should -HaveCount 3
            Join-TestFields $records[2].Fields | Should -BeExactly 'e|f'
        }

        It 'reads a last record that has no line end, and a file that ends with one' {
            @(ConvertFrom-TestStrictCsv -Text "a,b`r`nc,d") | Should -HaveCount 2
            @(ConvertFrom-TestStrictCsv -Text "a,b`r`nc,d`r`n") | Should -HaveCount 2
        }

        It 'reads nothing from an empty text' {
            @(ConvertFrom-TestStrictCsv -Text '') | Should -HaveCount 0
        }

        It 'reads an empty field, a blank line and a field made of spaces' {
            $records = @(ConvertFrom-TestStrictCsv -Text "a,,c`r`n`r`n   ,b,`r`n")

            $records | Should -HaveCount 3
            Join-TestFields $records[0].Fields | Should -BeExactly 'a||c'
            @($records[1].Fields) | Should -HaveCount 1
            Join-TestFields $records[2].Fields | Should -BeExactly '   |b|'
        }

        It 'numbers the lines, a line break inside a quoted field counting as one' {
            $text = "h1,h2`r`n`"a`r`nb`",x`r`nc,d`r`n"

            $records = @(ConvertFrom-TestStrictCsv -Text $text)

            @($records.Line) | Should -Be @(1, 2, 4)
        }

        It 'numbers the lines from the line that it is given, for a file whose first line was removed' {
            $records = @(ConvertFrom-TestStrictCsv -Text "a,b`r`nc,d`r`n" -FirstLine 2)

            @($records.Line) | Should -Be @(2, 3)
        }

        It 'leaves out the blank records when it is asked to, and counts the lines that they take' {
            $text = "`r`nh1,h2`r`n,`r`n  ,  `r`nx,y`r`n"

            $records = @(ConvertFrom-TestStrictCsv -Text $text -SkipBlank)

            $records | Should -HaveCount 2
            @($records.Line) | Should -Be @(2, 5)
        }

        It 'stops after the first records when it is asked to' {
            $records = @(ConvertFrom-TestStrictCsv -Text "`r`nh1,h2`r`nx,y`r`nz,t`r`n" -SkipBlank -First 1)

            $records | Should -HaveCount 1
            Join-TestFields $records[0].Fields | Should -BeExactly 'h1|h2'
        }
    }

    Context 'What it refuses, and where' {
        It 'refuses <Name>, and names the file and the line' -ForEach @(
            @{ Name = 'a quote in the middle of an unquoted field'; Text = "a,b`r`nc,d`"e`r`n"; Line = 2 }
            @{ Name = 'a quote that is never closed at the end of the file'; Text = "a,b`r`nc,`"unfinished"; Line = 2 }
            @{ Name = 'a quote that is never closed in the middle of the file'; Text = "a,b`r`nc,`"open`r`nd,e`r`n"; Line = 2 }
            @{ Name = 'text after the closing quote'; Text = "a,b`r`n`"c`"d,e`r`n"; Line = 2 }
            @{ Name = 'a quote after a space'; Text = "a,b`r`nc, `"d`"`r`n"; Line = 2 }
            @{ Name = 'a stray quote, then a quote that is never closed (an even number of quotes)'; Text = "Url,Note`r`nU,stray`"quote`r`nU,`"unfinished"; Line = 2 }
        ) {
            { ConvertFrom-TestStrictCsv -Text $Text } | Should -Throw -ExpectedMessage "*test.csv*line $Line*"
        }

        It 'numbers the line of an error from the line that it is given' {
            { ConvertFrom-TestStrictCsv -Text "a,b`r`nc,d`"e`r`n" -FirstLine 2 } | Should -Throw -ExpectedMessage '*line 3*'
        }

        It 'says what is wrong with the quotes' {
            { ConvertFrom-TestStrictCsv -Text "a,`"b`"c`r`n" } | Should -Throw -ExpectedMessage '*double quote*'
        }
    }

    Context 'Validating only' {
        It 'gives true for a text that is well formed' {
            ConvertFrom-TestStrictCsv -Text "a,`"b`r`nc`"`"`",d`r`n" -ValidateOnly | Should -BeTrue
        }

        It 'stops on a text that is not, and names the line' {
            { ConvertFrom-TestStrictCsv -Text "a,b`r`nc,`"open`r`nd,e`r`n" -ValidateOnly } | Should -Throw -ExpectedMessage '*line 2*'
        }

        It 'agrees with the full reading on 4,000 random texts' {
            $random = [System.Random]::new(20261029)
            $alphabet = 'a', 'b', ' ', ',', '"', '"', "`r", "`n", "`r`n", ';'
            $disagreements = [System.Collections.Generic.List[string]]::new()
            foreach ($i in 1..4000) {
                $length = $random.Next(0, 14)
                $text = -join (1..$length | ForEach-Object { $alphabet[$random.Next(0, $alphabet.Count)] })

                $full = $true
                try { $null = @(ConvertFrom-TestStrictCsv -Text $text) } catch { $full = $false }
                $fast = $true
                try { $null = ConvertFrom-TestStrictCsv -Text $text -ValidateOnly } catch { $fast = $false }

                if ($full -ne $fast) {
                    $disagreements.Add(($text -replace "`r", '\r' -replace "`n", '\n') + " full=$full fast=$fast")
                }
            }

            @($disagreements) | Should -HaveCount 0
        }
    }

    Context 'A round trip with the writer' {
        It 'reads back the fields that the writer wrote, whatever they hold, with the delimiter <Name>' -ForEach @(
            @{ Name = 'comma'; Delimiter = ',' }
            @{ Name = 'semicolon'; Delimiter = ';' }
            @{ Name = 'tab'; Delimiter = "`t" }
        ) {
            $random = [System.Random]::new(7)
            $alphabet = 'a', 'b', 'é', '日', ' ', ',', ';', "`t", '"', '"', "`r", "`n", '=', '-'
            $lines = [System.Collections.Generic.List[string]]::new()
            $expected = [System.Collections.Generic.List[string]]::new()
            foreach ($i in 1..1500) {
                $fields = foreach ($j in 1..3) { -join (1..$random.Next(0, 8) | ForEach-Object { $alphabet[$random.Next(0, $alphabet.Count)] }) }
                $expected.Add(($fields -join [char]1))
                $cells = foreach ($field in $fields) { & $script:Module { param($t, $d) ConvertTo-SPSLifecycleCsvField -Text $t -Delimiter ([char]$d) } $field $Delimiter }
                $lines.Add($cells -join $Delimiter)
            }

            $records = @(ConvertFrom-TestStrictCsv -Text (($lines -join "`r`n") + "`r`n") -Delimiter $Delimiter)

            $records | Should -HaveCount 1500
            $wrong = 0
            for ($i = 0; $i -lt 1500; $i++) {
                if (($records[$i].Fields -join [char]1) -cne $expected[$i]) {
                    $wrong++
                }
            }

            $wrong | Should -Be 0
        }
    }

    Context 'Size' {
        It 'reads 260,000 records, and validates them, in a reasonable time' -Tag 'Slow' {
            $builder = [System.Text.StringBuilder]::new()
            foreach ($i in 1..260000) {
                $null = $builder.Append("https://contoso.sharepoint.com/sites/site$i,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2025-09-18T10:00:00Z`r`n")
            }

            $text = $builder.ToString()
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $valid = ConvertFrom-TestStrictCsv -Text $text -ValidateOnly
            $validateSeconds = $watch.Elapsed.TotalSeconds
            $watch.Restart()
            $records = @(ConvertFrom-TestStrictCsv -Text $text)
            $parseSeconds = $watch.Elapsed.TotalSeconds

            $valid | Should -BeTrue
            $records | Should -HaveCount 260000
            $validateSeconds | Should -BeLessThan 20
            $parseSeconds | Should -BeLessThan 90
        }

        It 'does not take a quadratic time on a quoted field of 5 MB with many quotes' -Tag 'Slow' {
            $text = '"' + (('ab""' * 1250000)) + '"' + "`r`n"
            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            $valid = ConvertFrom-TestStrictCsv -Text $text -ValidateOnly

            $valid | Should -BeTrue
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 20
        }

        It 'does not take an exponential time on a text that cannot match' -Tag 'Slow' {
            $text = ('"a' * 200000) + "`r`n"
            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            { ConvertFrom-TestStrictCsv -Text $text -ValidateOnly } | Should -Throw

            $watch.Elapsed.TotalSeconds | Should -BeLessThan 20
        }
    }
}
