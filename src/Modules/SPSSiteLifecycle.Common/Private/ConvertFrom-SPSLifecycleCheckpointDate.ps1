function ConvertFrom-SPSLifecycleCheckpointDate {
    <#
        .SYNOPSIS
        Reads a date that ConvertTo-SPSLifecycleCheckpointDate wrote, and nothing else.

        .DESCRIPTION
        Gives the UTC date, or $null when the text is not in that form: a checkpoint is the tool's own file, and a
        date that is written in another form was changed by something else.

        .PARAMETER Text
        The text.

        .EXAMPLE
        ConvertFrom-SPSLifecycleCheckpointDate -Text '20261030T090700.1234567Z'
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[System.DateTime]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Text
    )

    $date = [System.DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ($null -ne $Text -and [System.DateTime]::TryParseExact($Text, "yyyyMMdd'T'HHmmss.fffffff'Z'", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$date)) {
        return $date
    }

    $null
}
