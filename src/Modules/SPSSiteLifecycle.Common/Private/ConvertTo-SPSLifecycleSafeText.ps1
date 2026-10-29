function ConvertTo-SPSLifecycleSafeText {
    <#
        .SYNOPSIS
        Keeps a text that comes from the tenant from being run as a formula by a spreadsheet.

        .DESCRIPTION
        A spreadsheet runs a cell that starts with an equals sign, a plus sign, a minus sign, an at sign,
        a tab or a carriage return as a formula (CSV injection, CWE-1236:
        https://cwe.mitre.org/data/definitions/1236.html). The title of a site is chosen by its owners, so
        it can be anything. A text that starts with one of these characters gets a leading apostrophe,
        which the spreadsheet shows as nothing and does not run. Any other text is returned as it is.

        A null gives an empty text.

        .PARAMETER Text
        The text to write in a cell.

        .EXAMPLE
        ConvertTo-SPSLifecycleSafeText -Text '=HYPERLINK("http://example.com")'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Text
    )

    process {
        $value = "$Text"
        if ($value.Length -gt 0 -and $value[0] -in '=', '+', '-', '@', "`t", "`r") {
            return "'" + $value
        }

        $value
    }
}
