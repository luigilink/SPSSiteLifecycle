function Read-SPSLifecycleCsv {
    <#
        .SYNOPSIS
        Reads a CSV file saved by the tool, by Microsoft Graph, or by a spreadsheet.

        .DESCRIPTION
        The reading is tolerant, because the files are meant to be opened and saved again in a
        spreadsheet: the separator is detected (comma, semicolon or tab, and a first line sep= is
        skipped), UTF-8 with or without a byte order mark and UTF-16 are read, a file that is not
        valid UTF-8 is read as Windows-1252, and the empty rows that a spreadsheet adds are
        ignored. A file that another program (Excel) has open is still read; if it cannot be, the
        message says so.

        Stops with a clear message when the file is missing, cannot be read as CSV, or lacks one of
        the required columns. The header is checked even when the file has no row.

        .PARAMETER Path
        Path of the CSV file.

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

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: '$Path'."
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $memory = [System.IO.MemoryStream]::new()
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.IOException] {
        throw "Cannot read '$Path': the file is probably open in another program (Excel?). Close it, or save a copy and use the copy. ($($_.Exception.Message))"
    }

    $detected = Get-SPSLifecycleCsvDelimiter -Text (ConvertFrom-SPSLifecycleCsvByte -Bytes $bytes)
    $delimiter = $detected.Delimiter

    $header = @()
    $head = $detected.Text.Substring(0, [System.Math]::Min(65536, $detected.Text.Length))
    $firstLine = $head -split "\r\n|\n|\r" | Where-Object { $_.Trim() } | Select-Object -First 1
    if ($firstLine) {
        $header = @(Split-SPSLifecycleCsvLine -Line $firstLine -Delimiter $delimiter | ForEach-Object { $_.Trim() })
    }

    $rows = @()
    if ($detected.Text.Trim()) {
        try {
            $rows = @(ConvertFrom-Csv -InputObject $detected.Text -Delimiter $delimiter -ErrorAction Stop)
        }
        catch {
            throw "Cannot read '$Path' as a CSV file: $($_.Exception.Message)"
        }
    }

    $missing = @($RequiredColumn | Where-Object { $header -notcontains $_ })
    if ($missing.Count -gt 0) {
        $present = if ($header.Count -gt 0) { $header -join ', ' } else { '(none: the file is empty)' }
        throw "Column(s) not found in '$Path': $($missing -join ', '). Columns present: $present."
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
