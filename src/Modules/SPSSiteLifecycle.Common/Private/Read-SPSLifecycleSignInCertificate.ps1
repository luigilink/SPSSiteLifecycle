function Read-SPSLifecycleSignInCertificate {
    <#
        .SYNOPSIS
        Reads the certificate that the app signs in with: its thumbprint, its dates, and whether the private key is there.

        .DESCRIPTION
        The tool reads the certificate before it signs in, to stop on one that has expired and to warn about one that ends soon (see
        Test-SPSLifecycleCertificateDate). A thumbprint is looked up in the My store of the current user, then of the machine (Windows
        only: macOS and Linux have no store and use the file). A file is opened with its password, as a certificate that is not kept (on
        Windows the key is not persisted), and closed again. It gives Thumbprint (capitals), NotBefore and NotAfter (UTC), HasPrivateKey and
        Subject. It throws when the certificate is not there, or cannot be opened: the message names the file and never tells a password.

        .PARAMETER Setting
        The settings (CertificateThumbprint or CertificatePath).

        .PARAMETER Password
        The password of the .pfx file, as a SecureString, when it has one.

        .EXAMPLE
        Read-SPSLifecycleSignInCertificate -Setting $setting -Password $password
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter()]
        [AllowNull()]
        [System.Security.SecureString]
        $Password = $null
    )

    $describe = {
        param($Certificate)
        [PSCustomObject][ordered]@{
            Thumbprint    = $Certificate.Thumbprint.ToUpperInvariant()
            NotBefore     = $Certificate.NotBefore.ToUniversalTime()
            NotAfter      = $Certificate.NotAfter.ToUniversalTime()
            HasPrivateKey = [System.Boolean]$Certificate.HasPrivateKey
            Subject       = "$($Certificate.Subject)"
        }
    }

    $thumbprint = "$($Setting.CertificateThumbprint)".Trim().ToUpperInvariant()
    if ($thumbprint) {
        if (-not (Test-SPSLifecycleWindowsPlatform)) {
            throw 'CertificateThumbprint: the certificate store is available on Windows only. On macOS and Linux, give the .pfx file in CertificatePath.'
        }

        foreach ($location in [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine) {
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new([System.Security.Cryptography.X509Certificates.StoreName]::My, $location)
            try {
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
                $found = @($store.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $thumbprint, $false))
                if ($found.Count -gt 0) {
                    return (& $describe $found[0])
                }
            }
            catch {
                $null = $_
            }
            finally {
                $store.Close()
            }
        }

        throw "There is no certificate with the thumbprint $thumbprint in the My store of the current user or of the machine."
    }

    $path = Resolve-SPSLifecycleFileSystemPath -Path "$($Setting.CertificatePath)".Trim()
    $leaf = Split-Path -Path $path -Leaf
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "The certificate file '$leaf' is not there ($path)."
    }

    $flags = if (Test-SPSLifecycleWindowsPlatform) { [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet } else { [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet }
    # No password is a null one first: macOS with .NET 8 opens a file that has none, or an empty one, with a null password only, and an empty
    # text is what a null becomes when it is cast to a string.
    $attempts = if ($null -eq $Password) { @([System.Management.Automation.Language.NullString]::Value, [System.String]'') } else { @($Password) }
    $certificate = $null
    foreach ($attempt in $attempts) {
        try {
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($path, $attempt, $flags)
            break
        }
        catch {
            $null = $_
        }
    }

    if ($null -eq $certificate) {
        throw "The certificate file '$leaf' could not be opened: the password is not the right one, or the file is not a certificate with its private key (.pfx)."
    }

    try {
        & $describe $certificate
    }
    finally {
        $certificate.Dispose()
    }
}
