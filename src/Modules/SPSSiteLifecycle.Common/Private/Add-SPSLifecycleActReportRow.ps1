function Add-SPSLifecycleActReportRow {
    <#
        .SYNOPSIS
        Adds one row to the Act report, and writes it to the disk before it returns.

        .DESCRIPTION
        The row is written at the end of the report (see Initialize-SPSLifecycleActReport) with one call that is flushed to the
        disk, and the file is closed again: a run that stops after an action leaves the record of it. The values are written as
        the Scan report writes them (see ConvertTo-SPSLifecycleReportCell): the time in the compact form, the ID as a lowercase GUID,
        and a text that comes from the tenant neutralized against formula injection, and quoted when it holds the separator, a
        quote, a line break, or a space at its ends.

        The outcome must be one of Done, Failed, WouldDo, Skipped, Review, ReadError, NotRun, InProgress or Interrupted, and a row
        with another one, or whose value cannot be written, is refused with its line and its column, and nothing of it is
        written. A report that is not there is not created: it would have no header.
        InProgress and Interrupted are not outcomes of a row: the first is written before the tenant is touched, and the second
        when the run was interrupted during the action (see Invoke-SPSLifecycleActLoop).

        .PARAMETER Path
        The path of the report, as Initialize-SPSLifecycleActReport gave it.

        .PARAMETER Row
        The row: Line, Url, SiteId, Decision, Verdict, Outcome, Detail and ProcessedOn.

        .PARAMETER Delimiter
        The separator that the report was made with.

        .EXAMPLE
        Add-SPSLifecycleActReportRow -Path $path -Row $row -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Row,

        [Parameter()]
        [ValidateSet(',', ';', "`t")]
        [System.Char]
        $Delimiter = ','
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "The report '$Path' is not there: it is created with its header (Initialize-SPSLifecycleActReport) before a row is added."
    }

    $outcome = "$($Row.Outcome)"
    $known = $false
    foreach ($name in 'Done', 'Failed', 'WouldDo', 'Skipped', 'Review', 'ReadError', 'NotRun', 'InProgress', 'Interrupted') {
        if ([System.String]::Equals($outcome, $name, [System.StringComparison]::Ordinal)) {
            $known = $true
        }
    }

    if (-not $known) {
        throw "Outcome '$(ConvertTo-SPSLifecycleVisibleText -Text $outcome -AsciiOnly)' (line $($Row.Line)) is not Done, Failed, WouldDo, Skipped, Review, ReadError, NotRun, InProgress or Interrupted."
    }

    $current = ''
    try {
        $cells = foreach ($column in Get-SPSLifecycleActReportColumn) {
            $current = $column.Name
            $property = $Row.PSObject.Properties[$column.Name]
            $value = if ($null -ne $property) { $property.Value } else { $null }
            $cell = ConvertTo-SPSLifecycleReportCell -Kind $column.Kind -Value $value
            ConvertTo-SPSLifecycleCsvField -Text $cell -Delimiter $Delimiter
        }
    }
    catch {
        throw "Cannot write the row of line $($Row.Line), column $current`: $($_.Exception.Message)"
    }

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((($cells -join $Delimiter) + "`r`n"))
    $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}
