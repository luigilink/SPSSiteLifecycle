function ConvertTo-SPSLifecycleCheckpointDate {
    <#
        .SYNOPSIS
        Writes a date as the text that a checkpoint holds: UTC, to the tick, whatever the culture.

        .DESCRIPTION
        The form is 20261030T090700.1234567Z. It is not one that a JSON reader recognizes as a date (PowerShell turns
        2026-10-30T09:07:00Z into a date of the local time zone), and it keeps the tick, so that a record that comes
        back from a checkpoint is the one that went in. A date with no kind is a UTC date, as everywhere in the tool
        (see ConvertTo-SPSLifecycleUtcDateTime).

        .PARAMETER Value
        The date.

        .EXAMPLE
        ConvertTo-SPSLifecycleCheckpointDate -Value ([System.DateTime]::UtcNow)
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Value
    )

    $utc = ConvertTo-SPSLifecycleUtcDateTime -Value $Value
    $utc.ToString("yyyyMMdd'T'HHmmss.fffffff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}
