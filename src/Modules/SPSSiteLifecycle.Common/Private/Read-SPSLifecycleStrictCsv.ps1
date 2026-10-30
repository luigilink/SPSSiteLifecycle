function Read-SPSLifecycleStrictCsv {
    <#
        .SYNOPSIS
        Reads a CSV file in which nothing may be lost: every line is read, or the tool stops and says where.

        .DESCRIPTION
        Read-SPSLifecycleCsv is tolerant: it reads what it can of a file that a person gives. This reader is for the
        file that the tool writes and that decides whether a site can be deleted, the lock journal, where a row that
        is swallowed or dropped can leave an older lock date in force. It stops on:

        - a text that breaks the CSV rules (a quote in the middle of an unquoted field, a quote that is never
          closed, text after a closing quote): see ConvertFrom-SPSLifecycleStrictCsv;
        - a row that does not have the width of the header: a value too many, or a row cut short (a row whose
          cells are all empty is the line that a spreadsheet adds, and is ignored);
        - a value under a column that has no name;
        - a column that appears twice, a required column that is missing, and a header that looks like a column
          the tool knows without being spelled like it (see Assert-SPSLifecycleCsvHeader).

        The file must be UTF-8, with a byte order mark or not (a file that holds only ASCII, as French Excel can
        save it, is UTF-8 too), which is what Add-SPSLifecycleLockJournalEntry requires to add to it: a byte that is
        not valid UTF-8 is never replaced or guessed, because a character that is read wrong changes a web address,
        and the row would no longer match its site. A file in UTF-16 or in Windows-1252 with an accented letter, and
        a UTF-8 file that is damaged, are refused with a message that says to save it as CSV UTF-8.

        With TolerantEncoding, for the lists that a person gives (the lock dates and the exclusions), the structure is
        as strict and the encoding is read as Excel writes it: UTF-8, UTF-16, and Windows-1252 for a file that has no
        byte order mark and is not UTF-8 (see ConvertFrom-SPSLifecycleCsvByte, StrictAfterMark). A byte order mark
        is a declaration, so a byte that does not fit it is a damage and stops the tool, whatever the encoding. The separator (a
        comma, a semicolon or a tab, and a first line sep=) and the blank lines before the header are read as
        Read-SPSLifecycleCsv reads them, because Excel changes them when it saves a file. The messages name the line of
        the file, which a person can find in Excel (the header is line 1 unless lines come before it).

        Returns an object with Name, Header (the names of the columns), Rows (one object per row, with a property
        for each named column) and Line (the number of the line of each row).

        .PARAMETER Path
        Path of the CSV file. A relative path is relative to the location of the PowerShell session.

        .PARAMETER RequiredColumn
        Names of the columns that must exist (the case is ignored).

        .PARAMETER OptionalColumn
        Names of the columns that the file may have and that the tool reads if it does.

        .PARAMETER TolerantEncoding
        Reads the encoding as Excel writes it (UTF-8, UTF-16, Windows-1252), as a list that a person gives, instead of UTF-8
        only. The structure stays strict, and a byte that does not fit the byte order mark stops the tool.

        .EXAMPLE
        Read-SPSLifecycleStrictCsv -Path .\lock-journal.csv -RequiredColumn 'Url', 'SiteId', 'LockedOn'

        .EXAMPLE
        Read-SPSLifecycleStrictCsv -Path .\exclusions.csv -RequiredColumn 'Url' -TolerantEncoding
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.String[]]
        $RequiredColumn = @(),

        [Parameter()]
        [System.String[]]
        $OptionalColumn = @(),

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $TolerantEncoding
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    $name = Split-Path -Path $fullPath -Leaf
    $bytes = Read-SPSLifecycleFileByte -Path $fullPath

    try {
        $text = if ($TolerantEncoding) { ConvertFrom-SPSLifecycleCsvByte -Bytes $bytes -StrictAfterMark } else { ConvertFrom-SPSLifecycleCsvByte -Bytes $bytes -Strict }
    }
    catch [System.Text.DecoderFallbackException] {
        if ($TolerantEncoding) {
            throw "File '$name' has a byte that does not fit the encoding that its byte order mark declares (UTF-8 or UTF-16), so the file is damaged and what it says cannot be trusted: a character that is read wrong changes a web address, and the row would no longer match its site (an exclusion would protect nothing, and an older lock date could stay in force). It is not read. Save it again as 'CSV UTF-8', or restore it from a copy."
        }

        throw "File '$name' is not UTF-8 (Excel may have saved it in another encoding, or the file is damaged), so what it says cannot be trusted: a character that is read wrong changes a web address, and an older lock date would stay in force. It is not read. Save it as 'CSV UTF-8', or restore it from a copy."
    }

    $detected = Get-SPSLifecycleCsvDelimiter -Text $text
    $records = @(ConvertFrom-SPSLifecycleStrictCsv -Text $detected.Text -Delimiter $detected.Delimiter -FirstLine $detected.FirstLine -Source $name -SkipBlank)

    $header = @()
    if ($records.Count -gt 0) {
        $header = @($records[0].Fields | ForEach-Object { "$_".Trim() })
    }

    Assert-SPSLifecycleCsvHeader -Name $header -RequiredColumn $RequiredColumn -OptionalColumn $OptionalColumn -Source $name

    $rows = [System.Collections.Generic.List[System.Object]]::new()
    $lines = [System.Collections.Generic.List[System.Int32]]::new()
    for ($index = 1; $index -lt $records.Count; $index++) {
        $record = $records[$index]
        if ($record.Fields.Count -ne $header.Count) {
            throw "File '$name', line $($record.Line): the row has $($record.Fields.Count) value(s) and the header has $($header.Count) column(s). A row that is cut short, or that has a value too many, could hide a lock date, so the file is not read. Fix the row, or delete it."
        }

        $values = [ordered]@{}
        for ($column = 0; $column -lt $header.Count; $column++) {
            if ($header[$column]) {
                $values[$header[$column]] = $record.Fields[$column]
            }
            elseif ("$($record.Fields[$column])".Trim()) {
                throw "File '$name', line $($record.Line): a value sits under column $($column + 1), which has no name in the header, so the tool cannot tell what it is. Name the column, or delete the value."
            }
        }

        $rows.Add([PSCustomObject]$values)
        $lines.Add($record.Line)
    }

    [PSCustomObject]@{
        Name   = $name
        Header = $header
        Rows   = $rows.ToArray()
        Line   = $lines.ToArray()
    }
}
