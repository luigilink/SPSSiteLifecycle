function Open-SPSLifecycleTenantSession {
    <#
        .SYNOPSIS
        Signs in to the admin site of the tenant, and gives the session that the other adapters use.

        .DESCRIPTION
        Right before the sign-in, the tool checks again that the tenant is not refused and that the admin address is the
        one of that tenant (see Assert-SPSLifecycleTenantAllowed): the sign-in is the point after which nothing can be
        taken back. The settings are checked again for the sign-in (see Assert-SPSLifecycleSignInSetting). The sign-in is interactive
        by default, with the ClientId of the settings (the app registration of the tenant), or, with Authentication = Certificate, the
        sign-in of the app alone with a certificate, for a run that nobody watches (#9): the password of a .pfx file comes from the
        environment variable that the settings name, or is typed (see Get-SPSLifecycleSignInPassword), and the certificate is read before
        the sign-in (see Read-SPSLifecycleSignInCertificate): a certificate that has expired, is not valid yet or has no private key stops
        the tool, and one that ends in less than 30 days is a warning (see Test-SPSLifecycleCertificateDate). The arguments are built by a
        pure function (see Get-SPSLifecycleConnectionArgument). The connection is kept in the session and not made the current one of the
        PowerShell session, so that a connection that the user already has is left as it is.

        Returns the session: the connection, the tenant it is for, its admin address and the tenants that are refused (the adapters
        that change the tenant check their target against them, see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Setting
        The settings (TenantName, AdminUrl, ClientId, RefusedTenants, and for a certificate Authentication, TenantId, CertificateThumbprint,
        CertificatePath, CertificatePasswordVariable), as Get-SPSLifecycleSetting gives them.

        .PARAMETER Now
        The time, in UTC, for the dates of the certificate. Default: now.

        .EXAMPLE
        $session = Open-SPSLifecycleTenantSession -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    Assert-SPSLifecycleTenantAllowed -Setting $Setting
    Assert-SPSLifecycleSignInSetting -Setting $Setting
    Assert-SPSLifecyclePnPModule

    $password = $null
    if ([System.String]::Equals("$($Setting.Authentication)", 'Certificate', [System.StringComparison]::Ordinal)) {
        $password = Get-SPSLifecycleSignInPassword -Setting $Setting
        $certificate = Read-SPSLifecycleSignInCertificate -Setting $Setting -Password $password
        if (-not $certificate.HasPrivateKey) {
            throw 'The certificate has no private key, so the app cannot sign in with it. Give the .pfx file, which holds the key, and not the .cer file.'
        }

        $dates = Test-SPSLifecycleCertificateDate -NotBefore $certificate.NotBefore -NotAfter $certificate.NotAfter -Now $Now
        if ($dates.State -eq 'Expired' -or $dates.State -eq 'NotYetValid') {
            throw $dates.Message
        }

        if ($dates.State -eq 'Soon') {
            Write-Warning -Message $dates.Message
        }
    }

    $arguments = Get-SPSLifecycleConnectionArgument -Setting $Setting -CertificatePassword $password
    $tenantName = "$($Setting.TenantName)".Trim().ToLowerInvariant()
    try {
        $connection = Connect-PnPOnline @arguments -ReturnConnection -ErrorAction Stop
    }
    catch {
        throw "The sign-in to the admin site of the tenant failed: $($_.Exception.Message)"
    }

    if ($null -eq $connection) {
        throw 'The sign-in to the admin site of the tenant gave no connection. The calls that follow would use the connection that this PowerShell session already holds, which may be the one of another tenant, so the tool stops.'
    }

    [PSCustomObject][ordered]@{
        Connection     = $connection
        TenantName     = $tenantName
        AdminUrl       = "$($Setting.AdminUrl)"
        RefusedTenants = @($Setting.RefusedTenants)
    }
}
