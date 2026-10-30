function Read-SPSLifecycleCertificatePassword {
    <#
        .SYNOPSIS
        Asks a person for the password of the private key of the certificate, twice, and gives it as a SecureString.

        .DESCRIPTION
        The password is typed, never shown, never given on a command line, and never written anywhere: it goes to PnP.PowerShell as a
        SecureString. It must be typed the same twice, and have at least 12 characters (the file protects a key that can act on every
        site of the tenant). Nothing is asked more than once: a mistake stops the script, before anything was done in the tenant.

        .EXAMPLE
        $password = Read-SPSLifecycleCertificatePassword
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param ()

    $first = Read-Host -Prompt 'Password for the private key of the certificate (12 characters or more; it is not shown and not saved)' -AsSecureString
    if ($first.Length -lt 12) {
        throw 'The password has fewer than 12 characters. Nothing was changed.'
    }

    $second = Read-Host -Prompt 'Type the password again' -AsSecureString
    $same = [System.String]::Equals([System.Net.NetworkCredential]::new('', $first).Password, [System.Net.NetworkCredential]::new('', $second).Password, [System.StringComparison]::Ordinal)
    if (-not $same) {
        throw 'The two passwords are not the same. Nothing was changed.'
    }

    $first
}
