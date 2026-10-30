function Add-SPSLifecycleCertificateToStore {
    <#
        .SYNOPSIS
        Adds a certificate with its private key to the CurrentUser store of Windows, and gives its thumbprint.

        .DESCRIPTION
        PnP.PowerShell signs in with a certificate of the store by its thumbprint, on Windows only. The key is imported from the .pfx file
        with its password, into the store of the user (not the machine), and stays there. It throws on another system, and when the file,
        the password or the store refuse it.

        .PARAMETER Path
        The .pfx file.

        .PARAMETER Password
        The password of the file.

        .EXAMPLE
        Add-SPSLifecycleCertificateToStore -Path $pfx -Password $password
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $Password
    )

    if (-not (Test-SPSLifecycleWindowsPlatform)) {
        throw 'The certificate store is available on Windows only: macOS and Linux use the .pfx file.'
    }

    $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (-not $PSCmdlet.ShouldProcess($full, 'Add the certificate to the CurrentUser store')) {
        return
    }

    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full, $Password, $flags)
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::My, [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $store.Add($certificate)
        $certificate.Thumbprint.ToUpperInvariant()
    }
    finally {
        $store.Close()
        $certificate.Dispose()
    }
}
