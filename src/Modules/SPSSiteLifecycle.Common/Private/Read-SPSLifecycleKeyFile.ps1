function Read-SPSLifecycleKeyFile {
    <#
        .SYNOPSIS
        Opens a .pfx file with its password and says what is in it: the thumbprint of its certificate and whether the private key is there.

        .DESCRIPTION
        The registration says that the app has a certificate, and the file that PnP.PowerShell wrote must hold the key of that certificate:
        an empty file, a text, a .cer or the key of another certificate are no key. The file is opened as a certificate that is not kept (on
        Windows the key is not persisted) and closed again. It gives Thumbprint (capitals) and HasPrivateKey, or nothing when the file is not
        there or cannot be opened with that password. It never throws and never tells the password.

        .PARAMETER Path
        The .pfx file.

        .PARAMETER Password
        The password of the file, as a SecureString.

        .EXAMPLE
        Read-SPSLifecycleKeyFile -Path ~/keys/SPSSiteLifecycle/SPSSiteLifecycle.pfx -Password $password
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [AllowNull()]
        [System.Security.SecureString]
        $Password = $null
    )

    try {
        $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return
        }

        $flags = if (Test-SPSLifecycleWindowsPlatform) { [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet } else { [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet }
        $certificate = if ($null -eq $Password) {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full, [System.String]'', $flags)
        }
        else {
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full, $Password, $flags)
        }

        try {
            [PSCustomObject]@{
                Thumbprint    = $certificate.Thumbprint.ToUpperInvariant()
                HasPrivateKey = [System.Boolean]$certificate.HasPrivateKey
            }
        }
        finally {
            $certificate.Dispose()
        }
    }
    catch {
        $null = $_
    }
}
