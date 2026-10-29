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

        Stops with a clear message when the file is missing, cannot be read as CSV, or lacks one of
        the required columns. The header is checked even when the file has no row.

        .PARAMETER Path
        Path of the CSV file. A relative path is relative to the location of the PowerShell session.

        .PARAMETER RequiredColumn
        Names of the columns that must exist (the case is ignored).

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
        $RequiredColumn = @()
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File not found: '$fullPath'."
    }

    try {
        $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $memory = [System.IO.MemoryStream]::new()
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
        throw "File not found: '$fullPath'."
    }
    catch [System.IO.IOException] {
        throw "Cannot read '$fullPath': the file is probably open in another program (Excel?). Close it, or save a copy and use the copy. ($($_.Exception.Message))"
    }

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

    $repeated = @($header | Where-Object { $_ } | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($repeated.Count -gt 0) {
        throw "Column(s) that appear more than once in '$fullPath' (the case and the spaces around a name do not count): $($repeated -join ', ')."
    }

    $rows = @()
    if ($text.Trim()) {
        try {
            $rows = @(ConvertFrom-Csv -InputObject $text -Delimiter $delimiter -ErrorAction Stop)
        }
        catch {
            throw "Cannot read '$fullPath' as a CSV file: $($_.Exception.Message)"
        }
    }

    $missing = @($RequiredColumn | Where-Object { $header -notcontains $_ })
    if ($missing.Count -gt 0) {
        $present = if ($header.Count -gt 0) { $header -join ', ' } else { '(none: the file is empty)' }
        throw "Column(s) not found in '$fullPath': $($missing -join ', '). Columns present: $present."
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
