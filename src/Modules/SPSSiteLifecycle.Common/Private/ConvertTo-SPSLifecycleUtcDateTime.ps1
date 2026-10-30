function ConvertTo-SPSLifecycleUtcDateTime {
    <#
        .SYNOPSIS
        Gives a date that a program handed over as a UTC date: a date, a date with an offset, or ISO 8601 text.

        .DESCRIPTION
        The Scan core compares dates with arithmetic, and an arithmetic on two dates ignores their kind: a local date
        would be off by the offset of the machine, and a text would be compared as text, with the format of the culture.
        A date with a local kind is converted to UTC, a date with no kind is read as UTC (as the report writer does), a
        date with an offset is converted, and a text is read as ISO 8601 (see ConvertTo-SPSLifecycleDate, which reads a
        blank text as no date). A null is no date. Anything else stops with a message: a value that cannot be read
        must not be taken for a date that says nothing.

        .PARAMETER Value
        The value to convert.

        .EXAMPLE
        ConvertTo-SPSLifecycleUtcDateTime -Value $site.LastContentModified
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[System.DateTime]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.DateTimeOffset]) {
        return $Value.UtcDateTime
    }

    if ($Value -is [System.DateTime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Local) {
            return $Value.ToUniversalTime()
        }

        return [System.DateTime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
    }

    if ($Value -is [System.String]) {
        return ConvertTo-SPSLifecycleDate -Text $Value
    }

    throw "'$(ConvertTo-SPSLifecycleVisibleText -Text "$Value")' ($($Value.GetType().Name)) is not a date."
}
