function Test-SPSLifecycleWebAddress {
    <#
        .SYNOPSIS
        Tells whether a text is the full web address of a site, and nothing else.

        .DESCRIPTION
        A full address starts with http:// or https://, has a host (the .NET parser refuses an http address that
        has none), and holds no white space, line break or hidden character (a zero-width space, a soft hyphen, a
        byte order mark) anywhere, the ends included. The text is not trimmed: a caller that wants to accept
        spaces around an address trims it first.

        This is the test for a file in which an address that cannot be used would hide a row. A path, an address
        without a scheme, another scheme, an address with no host and a cell that holds only a hidden character
        are not addresses.

        .PARAMETER Text
        The text to test.

        .EXAMPLE
        Test-SPSLifecycleWebAddress -Text 'https://contoso.sharepoint.com/sites/sales'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Text
    )

    $value = "$Text"
    if (-not $value -or [System.Text.RegularExpressions.Regex]::IsMatch($value, '[\p{Cc}\p{Cf}\p{Z}]')) {
        return $false
    }

    $uri = $null
    [System.Uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in 'http', 'https'
}
