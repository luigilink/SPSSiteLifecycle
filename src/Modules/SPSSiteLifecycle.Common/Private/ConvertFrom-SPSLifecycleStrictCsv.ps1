function ConvertFrom-SPSLifecycleStrictCsv {
    <#
        .SYNOPSIS
        Reads a CSV text with the strict rules of RFC 4180, and stops at the first line that breaks them.

        .DESCRIPTION
        ConvertFrom-Csv is tolerant: a quote in the middle of an unquoted field is a letter, a quote that is never
        closed swallows the rest of the file, and a field beyond the width of the header is dropped. A tolerant
        reader is right for a file that a person gives, and wrong for a file in which a lost row is dangerous:
        the lock journal. A row that is swallowed, or dropped, can leave an older lock date in force.

        The grammar here has no tolerance:

        - A field is quoted or unquoted. An unquoted field holds no double quote at all, no separator and no
          line break. A quoted field starts with a double quote and ends with the first double quote that is not
          doubled (a doubled quote is one quote), and holds any character, a line break included.
        - After a quoted field comes the separator, a line end (CRLF, LF or CR) or the end of the text: nothing
          else, not even a space.
        - A blank line is a record with one empty field.

        The text is matched by one regular expression whose groups are atomic, so that a text that cannot
        match is refused in a time that is linear in its size, and a text that is well formed is validated
        natively (ValidateOnly). The error names the file, and the line where the record that breaks the rules
        starts (a line break inside a quoted field counts as a line).

        Returns objects with Line (the line where the record starts) and Fields (the values, unquoted).

        .PARAMETER Text
        The decoded text, without the byte order mark and without a first line sep=.

        .PARAMETER Delimiter
        The separator: a comma, a semicolon or a tab.

        .PARAMETER FirstLine
        The number of the first line of the text, 2 when a first line sep= was removed.

        .PARAMETER Source
        What the messages call the file.

        .PARAMETER SkipBlank
        Leaves out the records in which every field is empty or white space (the lines that a spreadsheet adds). The
        lines that they take are still counted.

        .PARAMETER First
        Stops after this many records. 0, the default, reads them all.

        .PARAMETER ValidateOnly
        Reads nothing: gives $true when the whole text follows the rules, and stops otherwise.

        .EXAMPLE
        ConvertFrom-SPSLifecycleStrictCsv -Text $text -Delimiter ',' -Source 'lock-journal.csv'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject], [System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Text,

        [Parameter(Mandatory = $true)]
        [System.Char]
        $Delimiter,

        [Parameter()]
        [System.Int32]
        $FirstLine = 1,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Source,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipBlank,

        [Parameter()]
        [System.Int32]
        $First = 0,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ValidateOnly
    )

    $separator = [System.Text.RegularExpressions.Regex]::Escape([System.String]$Delimiter)
    $quoted = '"(?>[^"]+|"")*"'
    $plain = '[^"' + $separator + '\r\n]*'
    $field = "(?>$quoted|$plain)"
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $timeout = [System.TimeSpan]::FromSeconds(120)
    $lineEnd = '(?:\r\n|\n|\r)'

    try {
        if ($ValidateOnly) {
            $whole = [System.Text.RegularExpressions.Regex]::new("\A(?>$field(?:$separator$field)*$lineEnd)*(?>$field(?:$separator$field)*)?\z", $options, $timeout)
            if ($whole.IsMatch($Text)) {
                return $true
            }
        }

        # The text does not follow the rules (or it is being read): the records are read one at a time, to say where.

        $record = [System.Text.RegularExpressions.Regex]::new("\G(?<f>$quoted|$plain)(?:$separator(?<f>$quoted|$plain))*(?:$lineEnd|\z)", $options, $timeout)
        $position = 0
        $line = $FirstLine
        $emitted = 0
        $lineEndChars = [System.Char[]]@("`r", "`n")
        $match = $null

        while ($position -lt $Text.Length) {
            # NextMatch() starts where the previous match ended, which is where the anchor \G of the pattern holds, and it takes
            # no argument. $record.Match($Text, $position) would pass the whole file at every record, and on Windows PowerShell
            # copies the string arguments of every .NET method call into a log message (AMSI): a file of 26 MB would be
            # copied 260,000 times, and the reading would last hours.
            $match = if ($null -eq $match) { $record.Match($Text) } else { $match.NextMatch() }
            if (-not $match.Success) {
                $excerpt = ConvertTo-SPSLifecycleVisibleText -Text $Text.Substring($position, [System.Math]::Min(30, $Text.Length - $position)).Split("`r`n".ToCharArray())[0]
                throw "File '$Source', line ${line}: the text does not follow the CSV rules here (near '$excerpt'). A double quote must open a field and be closed, a double quote inside a field must be doubled, and only a separator or the end of the line may follow the closing quote. The file may have been cut short, or edited by hand."
            }

            $position = $match.Index + $match.Length
            $value = $match.Value
            $startLine = $line
            if ($value.IndexOf('"') -lt 0) {
                $line++
            }
            else {
                $index = 0
                while (($index = $value.IndexOfAny($lineEndChars, $index)) -ge 0) {
                    if ($value[$index] -eq "`r" -and ($index + 1) -lt $value.Length -and $value[$index + 1] -eq "`n") {
                        $index++
                    }

                    $line++
                    $index++
                }
            }

            if ($ValidateOnly) {
                continue
            }

            $captures = $match.Groups['f'].Captures
            $fields = [System.String[]]::new($captures.Count)
            $blank = $true
            for ($i = 0; $i -lt $captures.Count; $i++) {
                $cell = $captures[$i].Value
                if ($cell.Length -ge 2 -and $cell[0] -eq '"') {
                    $cell = $cell.Substring(1, $cell.Length - 2).Replace('""', '"')
                }

                $fields[$i] = $cell
                if ($blank -and -not [System.String]::IsNullOrWhiteSpace($cell)) {
                    $blank = $false
                }
            }

            if ($SkipBlank -and $blank) {
                continue
            }

            [PSCustomObject]@{
                Line   = $startLine
                Fields = $fields
            }

            $emitted++
            if ($First -gt 0 -and $emitted -ge $First) {
                return
            }
        }

        if ($ValidateOnly) {
            throw "File '$Source' does not follow the CSV rules (no record could be pointed at)."
        }
    }
    catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        throw "File '$Source' could not be checked in two minutes, which a file that follows the CSV rules never needs. It may have been damaged."
    }
}
