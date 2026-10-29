function Test-SPSLifecycleColumnPattern {
    <#
        .SYNOPSIS
        Checks that the filled cells of a column look like what the column should hold.

        .DESCRIPTION
        A column that is entirely empty, or in which fewer than 90 % of the filled cells match the
        pattern, almost always means that the wrong file or the wrong column was given (or that a
        report concealed the names). The function throws a message that says what to look at.

        .PARAMETER Value
        The cells of the column.

        .PARAMETER Pattern
        The regular expression a cell must match.

        .PARAMETER What
        What the column is, for the message ('Url' in lot.csv).

        .PARAMETER Hint
        Appended to the message when the pattern does not match, to say what to do.

        .EXAMPLE
        Test-SPSLifecycleColumnPattern -Value $rows.Url -Pattern '^https?://' -What "'Url' in lot.csv"
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Pattern,

        [Parameter(Mandatory = $true)]
        [System.String]
        $What,

        [Parameter()]
        [System.String]
        $Hint = ''
    )

    $filled = @($Value | Where-Object { "$_".Trim() })
    if ($filled.Count -eq 0) {
        throw "$What is empty on every row.$(if ($Hint) { " $Hint" })"
    }

    $matching = @($filled | Where-Object { "$_".Trim() -match $Pattern }).Count
    if (($matching / $filled.Count) -lt 0.9) {
        throw "$What does not look right ($matching of $($filled.Count) values match).$(if ($Hint) { " $Hint" })"
    }
}
