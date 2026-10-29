function Read-SPSLifecycleCsv {
    <#
        .SYNOPSIS
        Reads a CSV file saved by the tool, by Microsoft Graph, or by a spreadsheet.

        .DESCRIPTION
        The reading is tolerant, because the files are meant to be opened and saved again in a
        spreadsheet: the separator is detected (comma, semicolon or tab, and a first line sep= is
        skipped), UTF-8 with or without a byte order mark and UTF-16 are read, a file that is not
        valid UTF-8 is read as Windows-1252, the blank lines before the header and the empty rows
        that a spreadsheet adds are ignored, and the spaces around the names of the columns are
        removed. Two columns with the same name stop the tool. A file that another program (Excel) has open is still read; if it cannot be, the
        message says so.

        The names of the columns are compared one character at a time, whatever the case and the culture, because
        that is how a row finds its properties: a header named Site<U+00AD>Id is not SiteId, and the message shows
        the hidden character. A header that looks like a column the tool knows (a required or an optional one)
        and is not spelled that way stops the tool too (see Assert-SPSLifecycleCsvHeader): an optional column that
        is not there is normal, and the information that the lookalike carries would be lost without a message.

        This reader is tolerant on purpose: it is for the files that a person gives. A file in which a row that
        is lost or dropped is dangerous, the lock journal, is read by Read-SPSLifecycleStrictCsv.

        Stops with a clear message when the file is missing, cannot be read as CSV, or lacks one of
        the required columns. The header is checked even when the file has no row.

        .PARAMETER Path
        Path of the CSV file. A relative path is relative to the location of the PowerShell session.

        .PARAMETER RequiredColumn
        Names of the columns that must exist (the case is ignored).

        .PARAMETER OptionalColumn
        Names of the columns that the file may have and that the tool reads if it does. They are not required, but a
        header that looks like one of them without being spelled like it stops the tool.

        .EXAMPLE
        Read-SPSLifecycleCsv -Path .\lock-dates.csv -RequiredColumn 'Url', 'LockedOn'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
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
        $OptionalColumn = @()
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    $bytes = Read-SPSLifecycleFileByte -Path $fullPath

    $detected = Get-SPSLifecycleCsvDelimiter -Text (ConvertFrom-SPSLifecycleCsvByte -Bytes $bytes)
    $delimiter = $detected.Delimiter
    $text = $detected.Text

    # The header is the first line that is not blank. Its names are trimmed and written back, so that the names
    # that were checked are the names of the properties of the rows (ConvertFrom-Csv keeps the spaces of a name).
    $header = @()
    $first = [System.Text.RegularExpressions.Regex]::Match($text, '\A(?:[ \t]*(?:\r\n|\n|\r))*([^\r\n]*)')
    $headerLine = $first.Groups[1].Value
    if ($headerLine.Trim()) {
        $header = @(Split-SPSLifecycleCsvLine -Line $headerLine -Delimiter $delimiter | ForEach-Object { $_.Trim() })
        $rewritten = ($header | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join $delimiter
        $text = $rewritten + $text.Substring($first.Index + $first.Length)
    }

    Assert-SPSLifecycleCsvHeader -Name $header -RequiredColumn $RequiredColumn -OptionalColumn $OptionalColumn -Source $fullPath

    $rows = @()
    if ($text.Trim()) {
        try {
            $rows = @(ConvertFrom-Csv -InputObject $text -Delimiter $delimiter -ErrorAction Stop)
        }
        catch {
            throw "Cannot read '$fullPath' as a CSV file: $($_.Exception.Message)"
        }
    }

    $kept = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($row in $rows) {
        foreach ($property in $row.PSObject.Properties) {
            if ($property.Value -and "$($property.Value)".Trim()) {
                $kept.Add($row)
                break
            }
        }
    }

    $kept.ToArray()
}
