function ConvertTo-SPSLifecycleDate {
    <#
        .SYNOPSIS
        Reads a date from a CSV cell, in UTC, without ever guessing from the culture.

        .DESCRIPTION
        ISO 8601 dates are always accepted: 2026-10-28, 2026-10-28T16:30:00Z, 2026-10-28 16:30,
        and the compact forms 20261028 and 20261028T163000Z. A date without a time zone is taken
        as UTC.

        Any other format must be listed in DateFormat (for example dd/MM/yyyy). The special value
        Culture also accepts the date patterns of the current culture. Nothing else is tried: a day
        and a month swapped in a lock date could silently change whether a site is eligible.

        An empty value gives $null. A value that cannot be read throws, with a message that says
        which setting to use.

        .PARAMETER Text
        The cell text.

        .PARAMETER DateFormat
        Extra formats from the CsvDateFormats setting.

        .EXAMPLE
        ConvertTo-SPSLifecycleDate -Text '28/10/2026' -DateFormat 'dd/MM/yyyy'
    #>
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Text,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $DateFormat = @()
    )

    $value = "$Text".Trim()
    if (-not $value) {
        return $null
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [System.DateTime]::MinValue

    if ([System.DateTime]::TryParseExact($value, 'yyyy-MM-dd', $invariant, $styles, [ref]$parsed)) {
        return $parsed
    }

    $isoFormats = @(
        'yyyy-MM-ddTHH:mm', 'yyyy-MM-ddTHH:mmK',
        'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-ddTHH:mm:ssK',
        'yyyy-MM-ddTHH:mm:ss.FFFFFFF', 'yyyy-MM-ddTHH:mm:ss.FFFFFFFK',
        'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss',
        'yyyyMMdd', 'yyyyMMddTHHmmss', 'yyyyMMddTHHmmssK'
    )
    if ([System.DateTime]::TryParseExact($value, [System.String[]]$isoFormats, $invariant, $styles, [ref]$parsed)) {
        return $parsed
    }

    $extra = @($DateFormat | Where-Object { $_ })
    foreach ($format in $extra) {
        if ($format -eq 'Culture') {
            if ([System.DateTime]::TryParse($value, [System.Globalization.CultureInfo]::CurrentCulture, $styles, [ref]$parsed)) {
                return $parsed
            }
        }
        elseif ([System.DateTime]::TryParseExact($value, $format, $invariant, $styles, [ref]$parsed)) {
            return $parsed
        }
    }

    $configured = if ($extra.Count -gt 0) { ($extra | ForEach-Object { "'$_'" }) -join ', ' } else { 'none' }
    throw "'$value' is not a date the tool can read. ISO 8601 dates are always accepted (2026-10-28, 2026-10-28T16:30:00Z, 20261028T163000Z). Any other format must be listed in the CsvDateFormats setting (now: $configured), for example 'dd/MM/yyyy'."
}
