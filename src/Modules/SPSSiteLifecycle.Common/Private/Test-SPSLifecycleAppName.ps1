function Test-SPSLifecycleAppName {
    <#
        .SYNOPSIS
        Tells whether a text is a name that the setup script accepts for the app, which is also the name of its certificate files.

        .DESCRIPTION
        One to 64 characters of ASCII (letters, digits, dots, dashes and underscores), starting with a letter or a digit and not ending
        with a dot, matched as it is written: one character at a time, with no case folding and no culture (the Kelvin sign and a
        zero-width space are not letters of a name), and with \A and \z, so that a line break at the end is not ignored. The name is also
        refused when it is one that Windows keeps for a device (CON, PRN, AUX, NUL, COM1 to COM9, LPT1 to LPT9), with an extension or not,
        because the files are <name>.pfx and <name>.cer.

        .PARAMETER Name
        The text to check.

        .EXAMPLE
        Test-SPSLifecycleAppName -Name 'SPSSiteLifecycle'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    $text = "$Name"
    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($text, '\A[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        return $false
    }

    $firstPart = $text.Split([System.Char]'.')[0].ToLowerInvariant()
    -not [System.Text.RegularExpressions.Regex]::IsMatch($firstPart, '\A(?:con|prn|aux|nul|com[1-9]|lpt[1-9])\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}
