function ConvertTo-SPSLifecycleVisibleText {
    <#
        .SYNOPSIS
        Writes the characters that a message would not show (a soft hyphen, a zero-width space, a control
        character, a space that is not a plain space) as \uXXXX.

        .DESCRIPTION
        A column named Site<U+00AD>Id is displayed as SiteId, so a message that says that SiteId is missing
        from "Url, SiteId, LockedOn" looks absurd. With this function the same message says
        "Url, Site\u00ADId, LockedOn", and the reader can see what is wrong with the header.

        .PARAMETER Text
        The text to show.

        .EXAMPLE
        ConvertTo-SPSLifecycleVisibleText -Text "Site$([char]0xAD)Id"
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Text
    )

    if ([System.String]::IsNullOrEmpty($Text)) {
        return ''
    }

    [System.Text.RegularExpressions.Regex]::Replace($Text, '[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Zs}-[ ]]', { param($match) '\u{0:X4}' -f [System.Int32][System.Char]$match.Value })
}
