function Add-SPSLifecycleLockJournalEntry {
    <#
        .SYNOPSIS
        Adds one row to the lock journal: the site that the tool has just locked, and the date.

        .DESCRIPTION
        The tenant does not give the date a site was locked, so the Act phase calls this function after each
        lock, and the journal is how a later run knows when to delete the site (MinLockedDays). Nothing is
        written in the tenant: the journal is a local file.

        A journal that does not exist yet, or that is empty, is created with a UTF-8 byte order mark and a
        header, with the separator that the settings ask for. A journal that exists gets the row at its end, and
        nothing else changes:

        - The separator of the file is kept, and the values go under their columns, whatever the order of the
          columns and the columns that a person added (the names are read the way Read-SPSLifecycleCsv does).
        - The file must be UTF-8 (a byte order mark or not; a file that holds only ASCII, as French Excel can
          save it, is UTF-8 too), and it must not end inside a quoted field (an odd number of double quotes):
          the row would become part of that field and be lost. A file in another encoding, or that is not a
          journal, is refused and left as it is, because adding to it would damage it. Save it as CSV UTF-8,
          fix the end of the file, or move it away.
        - The names of the columns are compared one character at a time, whatever the case and the culture, as
          a row finds its properties: a column named Site<U+00AD>Id is not SiteId, and the message shows the
          hidden character.
        - A file that does not end with a line break gets one first.

        The row is written with one call and flushed to the disk, because the lock date must survive a crash
        right after the lock. The date is written in ISO 8601 in UTC whatever the culture. The file is opened
        so that another program cannot write in it at the same time, and a program that has it open (Excel)
        stops the call with a clear message. Returns the full path of the journal.

        .PARAMETER Path
        Path of the journal. A relative path is relative to the location of the PowerShell session.

        .PARAMETER Url
        The address of the site, on one line and without a space.

        .PARAMETER SiteId
        The ID of the site, as a GUID that is not all zeros: it is what ties the date to the site when the
        address is reused.

        .PARAMETER LockedOn
        The date and time the site was locked.

        .PARAMETER Delimiter
        The separator of a new journal: a comma, a semicolon or a tab. An existing journal keeps its own.

        .EXAMPLE
        Add-SPSLifecycleLockJournalEntry -Path .\Reports\lock-journal.csv -Url $site.Url -SiteId $site.SiteId -LockedOn ([datetime]::UtcNow)
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SiteId,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $LockedOn,

        [Parameter()]
        [ValidateSet(',', ';', "`t")]
        [System.Char]
        $Delimiter = ','
    )

    $address = $Url.Trim()
    if ($address -notmatch '^https?://\S+$') {
        throw "The lock journal takes the web address of a site on one line, without a space: '$Url' is not one."
    }

    $id = ConvertTo-SPSLifecycleId -Value $SiteId
    if (-not $id) {
        throw "The lock journal takes the site ID as a GUID that is not all zeros: '$SiteId' is not one."
    }

    $date = ConvertTo-SPSLifecycleReportCell -Kind Date -Value $LockedOn
    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Path $fullPath -Parent))

    try {
        $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    }
    catch [System.IO.IOException] {
        throw "Cannot write the lock journal '$fullPath': the file is probably open in another program (Excel?). Close it, then run again. ($($_.Exception.Message))"
    }

    try {
        $columns = @('Url', 'SiteId', 'LockedOn')
        $names = $columns
        $separator = $Delimiter
        $prefix = ''
        $isNew = $stream.Length -eq 0

        if (-not $isNew) {
            $notUtf8 = "The lock journal '$fullPath' is not UTF-8 (Excel may have saved it in another encoding), and adding to it would damage it. It is left as it is. Save it as 'CSV UTF-8', or move it away and let the tool write a new one."
            $unclosed = "The lock journal '$fullPath' ends inside a quoted field: a double quote is never closed (the number of quotes is odd), so a row added now would become part of that field and be lost. It is left as it is. Fix the end of the file, or move it away and let the tool write a new one."

            $head = [System.Byte[]]::new([System.Math]::Min(65536, [System.Int32]$stream.Length))
            $headCount = 0
            while ($headCount -lt $head.Length) {
                $count = $stream.Read($head, $headCount, $head.Length - $headCount)
                if ($count -le 0) {
                    break
                }

                $headCount += $count
            }

            # The whole file must be valid UTF-8, read in pieces, because one byte of another encoding in the middle
            # would make the new row (and the file) unreadable by a reader that expects UTF-8. UTF-16 fails at its
            # first byte, which UTF-8 never uses.
            $decoder = [System.Text.UTF8Encoding]::new($false, $true).GetDecoder()
            $buffer = [System.Byte[]]::new(65536)
            $chars = [System.Char[]]::new(65536 + 8)
            $quotes = 0
            $countQuotes = {
                param([System.Byte[]]$Bytes, [System.Int32]$Length)
                $found = 0
                $position = 0
                while ($position -lt $Length) {
                    $index = [System.Array]::IndexOf($Bytes, [System.Byte]0x22, $position, $Length - $position)
                    if ($index -lt 0) {
                        break
                    }

                    $found++
                    $position = $index + 1
                }

                $found
            }

            try {
                $null = $decoder.GetChars($head, 0, $headCount, $chars, 0, $false)
                $quotes += & $countQuotes $head $headCount
                while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $null = $decoder.GetChars($buffer, 0, $count, $chars, 0, $false)
                    $quotes += & $countQuotes $buffer $count
                }

                $null = $decoder.GetChars($buffer, 0, 0, $chars, 0, $true)
            }
            catch [System.Text.DecoderFallbackException] {
                throw $notUtf8
            }

            if (($quotes % 2) -ne 0) {
                throw $unclosed
            }

            $detected = Get-SPSLifecycleCsvDelimiter -Text ([System.Text.UTF8Encoding]::new($false).GetString($head, 0, $headCount))
            $separator = $detected.Delimiter
            $first = [System.Text.RegularExpressions.Regex]::Match($detected.Text, '\A(?:[ \t]*(?:\r\n|\n|\r))*([^\r\n]*)')
            $names = @(Split-SPSLifecycleCsvLine -Line $first.Groups[1].Value -Delimiter $separator | ForEach-Object { $_.Trim() })

            $missing = @($columns | Where-Object { -not (Test-SPSLifecycleColumnName -Name $names -Column $_) })
            if ($missing.Count -gt 0) {
                $present = if (@($names | Where-Object { $_ }).Count -gt 0) { @($names | ForEach-Object { ConvertTo-SPSLifecycleVisibleText -Text $_ }) -join ', ' } else { '(none)' }
                throw "'$fullPath' is not a lock journal: the column(s) $($missing -join ', ') are missing. Columns present: $present. It is left as it is."
            }

            $repeated = @($columns | Where-Object { $column = $_; @($names | Where-Object { [System.String]::Equals($_, $column, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 1 })
            if ($repeated.Count -gt 0) {
                throw "Column(s) that appear more than once in '$fullPath': $($repeated -join ', '). It is left as it is."
            }

            $null = $stream.Seek(-1, [System.IO.SeekOrigin]::End)
            $last = $stream.ReadByte()
            if ($last -ne 10 -and $last -ne 13) {
                $prefix = "`r`n"
            }
        }

        $values = [System.Collections.Generic.Dictionary[System.String, System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $values.Add('Url', $address)
        $values.Add('SiteId', $id)
        $values.Add('LockedOn', $date)
        $cells = foreach ($name in $names) {
            if ($values.ContainsKey($name)) {
                ConvertTo-SPSLifecycleCsvField -Text $values[$name] -Delimiter $separator
            }
            else {
                ''
            }
        }

        $text = $prefix + ($cells -join $separator) + "`r`n"
        if ($isNew) {
            $utf8 = [System.Text.UTF8Encoding]::new($true)
            $preamble = $utf8.GetPreamble()
            $body = $utf8.GetBytes((($columns -join $separator) + "`r`n") + $text)
            $bytes = [System.Byte[]]::new($preamble.Length + $body.Length)
            [System.Buffer]::BlockCopy($preamble, 0, $bytes, 0, $preamble.Length)
            [System.Buffer]::BlockCopy($body, 0, $bytes, $preamble.Length, $body.Length)
        }
        else {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
        }

        $null = $stream.Seek(0, [System.IO.SeekOrigin]::End)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }

    $fullPath
}
