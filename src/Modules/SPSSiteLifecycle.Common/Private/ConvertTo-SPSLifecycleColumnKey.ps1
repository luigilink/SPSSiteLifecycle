function ConvertTo-SPSLifecycleColumnKey {
    <#
        .SYNOPSIS
        Gives a column name the form in which two spellings of the same name look the same.

        .DESCRIPTION
        The name is normalized (NFKC, so a full-width letter or a ligature becomes the plain letter), and only its
        letters and digits are kept, in lowercase: a space, a hyphen, an underscore, a soft hyphen, a zero-width
        space or a no-break space do not change the key. Site ID, Site_Id, SiteId and Site<U+00AD>Id have the same
        key.

        The key is not used to accept a column. It is used to find a header that looks like a column the tool
        knows, and that is not spelled as the tool expects (see Assert-SPSLifecycleCsvHeader): such a header must
        stop the tool, because the tool would otherwise read it as a column that is not there, and lose what
        the column carries (a site ID, a deleted flag).

        A letter of another alphabet that looks like a Latin one (a Cyrillic a) is a different letter: this
        function does not claim to detect it.

        .PARAMETER Name
        The name of the column.

        .EXAMPLE
        ConvertTo-SPSLifecycleColumnKey -Name 'Site ID'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    if ([System.String]::IsNullOrEmpty($Name)) {
        return ''
    }

    $normalized = $Name.Normalize([System.Text.NormalizationForm]::FormKC)
    [System.Text.RegularExpressions.Regex]::Replace($normalized, '[^\p{L}\p{N}]', '').ToLowerInvariant()
}
