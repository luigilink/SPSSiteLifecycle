function Read-SPSLifecycleCertificateInfo {
    <#
        .SYNOPSIS
        Reads the thumbprint and the end date of a certificate from its public file (.cer), or gives nothing when it cannot be read.

        .DESCRIPTION
        The public file holds no secret. The setup script reads it after the registration, to tell the person the real thumbprint and the
        real date the certificate ends, and to check that the certificate that was uploaded is the one that was written. It never
        throws: a file that is not there or not a certificate gives nothing.

        .PARAMETER Path
        The .cer file.

        .EXAMPLE
        Read-SPSLifecycleCertificateInfo -Path ~/.spssitelifecycle/SPSSiteLifecycle.cer
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    try {
        $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return
        }

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($full)
        try {
            [PSCustomObject]@{
                Thumbprint = $certificate.Thumbprint.ToUpperInvariant()
                NotAfter   = $certificate.NotAfter.ToUniversalTime()
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
