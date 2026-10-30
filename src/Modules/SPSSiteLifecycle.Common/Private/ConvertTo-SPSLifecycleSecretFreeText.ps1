function ConvertTo-SPSLifecycleSecretFreeText {
    <#
        .SYNOPSIS
        Takes what may be a secret out of a text that comes from another program, before the text is shown: a key, a long run of base64, a password.

        .DESCRIPTION
        The message of an error of PnP.PowerShell is told to the person, because it says what went wrong, but it is not the tool's text and
        nothing says what is in it. A block of a PEM file (-----BEGIN ... END-----), a run of 120 characters or more of the base64 alphabet (the
        whole certificate with its private key is one, of thousands), and each of the secrets that it is given (the password, when it was typed)
        are replaced by [removed], and the text is cut to 800 characters. A text with nothing of the kind is returned as it is, trimmed.

        .PARAMETER Text
        The text.

        .PARAMETER Secret
        Texts that must not appear in it: a password.

        .EXAMPLE
        ConvertTo-SPSLifecycleSecretFreeText -Text $_.Exception.Message -Secret $plain
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
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $Secret = @()
    )

    $clean = "$Text"
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, '-----BEGIN [A-Z0-9 ]+-----.*?(?:-----END [A-Z0-9 ]+-----|\z)', '[removed]', $options)
    $clean = [System.Text.RegularExpressions.Regex]::Replace($clean, '[A-Za-z0-9+/]{120,}={0,2}', '[removed]', $options)
    foreach ($value in @($Secret | Where-Object { $_ })) {
        $clean = $clean.Replace($value, '[removed]')
    }

    $clean = $clean.Trim()
    if ($clean.Length -gt 800) {
        $clean = $clean.Substring(0, 800) + '...'
    }

    $clean
}
