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
          save it, is UTF-8 too), and it must follow the CSV rules from its first line to its last: a quote in
          the middle of an unquoted field, or a quote that is never closed, would make the row that is added
          part of another field, and it would be lost (see ConvertFrom-SPSLifecycleStrictCsv). A file in another
          encoding, that breaks the rules, or that is not a journal is refused and left as it is, because adding
          to it would damage it. Save it as CSV UTF-8, fix the line that the message names, or move it away.
        - The names of the columns are compared one character at a time, whatever the case and the culture, as
          a row finds its properties: a column named Site<U+00AD>Id, or Site ID, is not SiteId, and the message
          shows the hidden character.
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
    if (-not (Test-SPSLifecycleWebAddress -Text $address)) {
        throw "The lock journal takes the full web address of a site, on one line, with no space and no hidden character: '$(ConvertTo-SPSLifecycleVisibleText -Text $Url)' is not one."
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

            $bytes = [System.Byte[]]::new([System.Int32]$stream.Length)
            $total = 0
            while ($total -lt $bytes.Length) {
                $count = $stream.Read($bytes, $total, $bytes.Length - $total)
                if ($count -le 0) {
                    break
                }

                $total += $count
            }

            # The whole file is checked, because one byte of another encoding, or one quote that is never closed, anywhere
            # in it, would make the row that is added unreadable or part of another field.
            try {
                $decoded = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes, 0, $total)
            }
            catch [System.Text.DecoderFallbackException] {
                throw $notUtf8
            }

            $detected = Get-SPSLifecycleCsvDelimiter -Text $decoded
            $separator = $detected.Delimiter
            $leaf = Split-Path -Path $fullPath -Leaf
            try {
                $null = ConvertFrom-SPSLifecycleStrictCsv -Text $detected.Text -Delimiter $separator -FirstLine $detected.FirstLine -Source $leaf -ValidateOnly
                $first = @(ConvertFrom-SPSLifecycleStrictCsv -Text $detected.Text -Delimiter $separator -FirstLine $detected.FirstLine -Source $leaf -SkipBlank -First 1)
            }
            catch {
                throw "The lock journal cannot be added to, because it does not follow the CSV rules, and the row would be lost or would damage the file. It is left as it is. $($_.Exception.Message)"
            }

            $names = if ($first.Count -gt 0) { @($first[0].Fields | ForEach-Object { "$_".Trim() }) } else { @() }
            try {
                Assert-SPSLifecycleCsvHeader -Name $names -RequiredColumn $columns -Source $fullPath
            }
            catch {
                throw "'$fullPath' is not a lock journal: $($_.Exception.Message) It is left as it is."
            }

            $last = $bytes[$total - 1]
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
