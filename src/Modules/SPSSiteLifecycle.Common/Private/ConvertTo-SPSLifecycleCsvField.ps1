function ConvertTo-SPSLifecycleCsvField {
    <#
        .SYNOPSIS
        Writes one value as a field of a CSV line.

        .DESCRIPTION
        A value that holds the delimiter, a double quote, a line break or a tab is put between double
        quotes, and its double quotes are doubled. Any other value is written as it is. The result can
        be read back by Read-SPSLifecycleCsv whatever the delimiter.

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

    if ($Text.IndexOf($Delimiter) -ge 0 -or $Text.IndexOfAny([System.Char[]]@('"', "`r", "`n", "`t")) -ge 0) {
        return '"' + $Text.Replace('"', '""') + '"'
    }

    $Text
}
