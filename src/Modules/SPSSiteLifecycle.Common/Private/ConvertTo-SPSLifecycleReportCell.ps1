function ConvertTo-SPSLifecycleReportCell {
    <#
        .SYNOPSIS
        Turns one value of a site record into the text of a cell of the Scan report.

        .DESCRIPTION
        The text never depends on the culture of the machine, so that a report written on a French
        server reads the same on an English one (see Get-SPSLifecycleReportColumn for the kinds):

        - WholeNumber: rounded to a whole number, with no separator. A value that is missing, negative,
          not a number or not finite is unknown and gives an empty cell. It never gives 0, because
          the verdict engine reads 0 as a size that is known.
        - Date: 2026-10-28 for a date at midnight UTC, otherwise 2026-10-28T16:30:00Z. A date with no
          time zone is taken as UTC, a local date is converted to UTC.
        - Run: 20261028T163000Z, the form that survives a spreadsheet.
        - Boolean: True or False. The words of a spreadsheet in another language are read too.
        - Guid: lowercase, empty when the value is empty, not a GUID, or all zeros.
        - Text: neutralized against formula injection.
        - Blank: always empty.

        A date or a boolean that cannot be read throws: a report that says something wrong is worse
        than no report.

        .PARAMETER Kind
        Text, Guid, Boolean, WholeNumber, Date, Run or Blank.

        .PARAMETER Value
        The value of the record.

        .EXAMPLE
        ConvertTo-SPSLifecycleReportCell -Kind WholeNumber -Value 1234.5
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Text', 'Guid', 'Boolean', 'WholeNumber', 'Date', 'Run', 'Blank')]
        [System.String]
        $Kind,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Value
    )

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    $toUtc = {
        param($Item)
        if ($Item -is [System.DateTimeOffset]) {
            return $Item.UtcDateTime
        }

        if ($Item -is [System.DateTime]) {
            if ($Item.Kind -eq [System.DateTimeKind]::Local) {
                return $Item.ToUniversalTime()
            }

            return [System.DateTime]::SpecifyKind($Item, [System.DateTimeKind]::Utc)
        }

        ConvertTo-SPSLifecycleDate -Text $Item
    }

    switch ($Kind) {
        'Blank' {
            return ''
        }

        'Text' {
            return ConvertTo-SPSLifecycleSafeText -Text $Value
        }

        'Guid' {
            return ConvertTo-SPSLifecycleId -Value $Value
        }

        'Boolean' {
            if ($Value -is [System.Boolean]) {
                return $Value.ToString($invariant)
            }

            $flag = ConvertTo-SPSLifecycleBoolean -Text $Value
            if ($null -eq $flag) {
                return ''
            }

            return $flag.ToString($invariant)
        }

        'WholeNumber' {
            if ($null -eq $Value -or $Value -is [System.Boolean]) {
                return ''
            }

            $number = 0.0
            if ($Value -is [System.String]) {
                if (-not [System.Double]::TryParse($Value.Trim(), [System.Globalization.NumberStyles]::Float, $invariant, [ref]$number)) {
                    return ''
                }
            }
            elseif ($Value -is [System.ValueType] -and $Value -isnot [System.DateTime]) {
                try {
                    $number = [System.Double]$Value
                }
                catch {
                    return ''
                }
            }
            else {
                return ''
            }

            if (-not [System.Double]::IsFinite($number) -or $number -lt 0) {
                return ''
            }

            return [System.Math]::Round($number, [System.MidpointRounding]::AwayFromZero).ToString('0', $invariant)
        }

        'Date' {
            if ($null -eq $Value -or ($Value -is [System.String] -and -not $Value.Trim())) {
                return ''
            }

            $date = & $toUtc $Value
            if ($date.TimeOfDay -eq [System.TimeSpan]::Zero) {
                return $date.ToString('yyyy-MM-dd', $invariant)
            }

            return $date.ToString('yyyy-MM-ddTHH:mm:ss', $invariant) + 'Z'
        }

        'Run' {
            $date = & $toUtc $Value
            return $date.ToString('yyyyMMddTHHmmss', $invariant) + 'Z'
        }
    }
}
