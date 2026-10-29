function ConvertTo-SPSLifecycleCsvField {
    <#
        .SYNOPSIS
        Writes one value as a field of a CSV line.

        .DESCRIPTION
        A value that holds the delimiter, a double quote, a line break or a tab, or that starts or ends
        with white space, is put between double quotes, and its double quotes are doubled. Any other
        value is written as it is. The result can be read back by Read-SPSLifecycleCsv whatever the
        delimiter.

        .PARAMETER Text
        The text of the cell.

        .PARAMETER Delimiter
        The separator of the file: a comma, a semicolon or a tab.

        .EXAMPLE
        ConvertTo-SPSLifecycleCsvField -Text 'Sales; EMEA' -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Text,

        [Parameter(Mandatory = $true)]
        [System.Char]
        $Delimiter
    )

    if ($null -eq $Text -or $Text.Length -eq 0) {
        return ''
    }

    # ConvertFrom-Csv drops the spaces that start an unquoted field, and other readers trim both ends. A quoted
    # field is kept as it is.
    $needsQuotes = $Text.IndexOf($Delimiter) -ge 0 -or
    $Text.IndexOfAny([System.Char[]]@('"', "`r", "`n", "`t")) -ge 0 -or
    [System.Char]::IsWhiteSpace($Text[0]) -or
    [System.Char]::IsWhiteSpace($Text[$Text.Length - 1])
    if ($needsQuotes) {
        return '"' + $Text.Replace('"', '""') + '"'
    }

    $Text
}
