function ConvertTo-SPSLifecycleVisibleText {
    <#
        .SYNOPSIS
        Writes the characters that a message would not show (a soft hyphen, a zero-width space, a control
        character, a space that is not a plain space) and the combining marks as \uXXXX.

        .DESCRIPTION
        A column named Site<U+00AD>Id is displayed as SiteId, so a message that says that SiteId is missing
        from "Url, SiteId, LockedOn" looks absurd. With this function the same message says
        "Url, Site\u00ADId, LockedOn", and the reader can see what is wrong with the header. A combining mark (the
        dot above that turns a capital I into a dotted one) is drawn on the letter before it, so it is written
        out as well.

        With -AsciiOnly, every character that is not a printable character of ASCII is written as \uXXXX, a letter included:
        that is for a text that must be ASCII (a tenant name, a setting), where the Kelvin sign looks like a K, a capital I with a
        dot above like an I, and a full-width letter like a letter of the alphabet. A character outside the Basic Multilingual Plane
        is written as its two halves.

        .PARAMETER Text
        The text to show.

        .PARAMETER AsciiOnly
        Writes every character that is not a printable character of ASCII (U+0020 to U+007E) as \uXXXX.

        .EXAMPLE
        ConvertTo-SPSLifecycleVisibleText -Text "Site$([char]0xAD)Id"

        .EXAMPLE
        ConvertTo-SPSLifecycleVisibleText -Text "cont$([char]0x212A)so" -AsciiOnly
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

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AsciiOnly
    )

    if ([System.String]::IsNullOrEmpty($Text)) {
        return ''
    }

    $pattern = if ($AsciiOnly) { '[^\u0020-\u007E]' } else { '[\p{Cc}\p{Cf}\p{M}\p{Zl}\p{Zp}\p{Zs}-[ ]]' }
    [System.Text.RegularExpressions.Regex]::Replace($Text, $pattern, { param($match) '\u{0:X4}' -f [System.Int32][System.Char]$match.Value })
}
