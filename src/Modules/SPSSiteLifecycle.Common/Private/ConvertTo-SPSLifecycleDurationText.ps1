function ConvertTo-SPSLifecycleDurationText {
    <#
        .SYNOPSIS
        Writes a number of seconds as the duration that a person reads in the summary of a run.

        .DESCRIPTION
        Under a minute it is the seconds with one decimal, cut and not rounded (59.96 s is 59.9 s, never 60.0 s), then minutes and
        seconds (2 min 5 s), then hours, minutes and seconds (1 h 0 min 0 s). The numbers are written the same way whatever the
        culture of the machine, and a negative number is no time.

        .PARAMETER Seconds
        The duration in seconds.

        .EXAMPLE
        ConvertTo-SPSLifecycleDurationText -Seconds 125.4
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Double]
        $Seconds
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $value = [System.Math]::Max(0.0, $Seconds)
    if ($value -lt 60) {
        return '{0} s' -f ([System.Math]::Floor($value * 10) / 10).ToString('N1', $culture)
    }

    $whole = [System.Int64][System.Math]::Floor($value)
    $hours = [System.Int64][System.Math]::Floor($whole / 3600)
    $minutes = [System.Int64][System.Math]::Floor(($whole % 3600) / 60)
    $rest = $whole % 60
    if ($hours -gt 0) { "$hours h $minutes min $rest s" } else { "$minutes min $rest s" }
}
