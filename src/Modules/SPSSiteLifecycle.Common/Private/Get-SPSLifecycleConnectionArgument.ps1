function Get-SPSLifecycleConnectionArgument {
    <#
        .SYNOPSIS
        Builds the arguments of the sign-in to the admin site of the tenant (Connect-PnPOnline), from the settings.

        .DESCRIPTION
        A pure function, so that the arguments are tested without a sign-in. The address is the admin site, and the client ID is the one of
        the settings. Interactive: the interactive sign-in, in the domain of the tenant (<TenantName>.onmicrosoft.com). Certificate: no
        interactive sign-in, the tenant is the tenant ID of the settings, and the certificate is the thumbprint in capitals (a certificate of
        the Windows store) or the file with its password, when it has one. The settings are checked first (see
        Assert-SPSLifecycleSignInSetting). It does not add -ReturnConnection or -ErrorAction: the adapter does.

        .PARAMETER Setting
        The settings.

        .PARAMETER CertificatePassword
        The password of the .pfx file, as a SecureString, for the file only.

        .EXAMPLE
        Get-SPSLifecycleConnectionArgument -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter()]
        [AllowNull()]
        [System.Security.SecureString]
        $CertificatePassword = $null
    )

    Assert-SPSLifecycleSignInSetting -Setting $Setting

    $arguments = [System.Collections.Specialized.OrderedDictionary]::new()
    $arguments['Url'] = "$($Setting.AdminUrl)"
    $arguments['ClientId'] = "$($Setting.ClientId)".Trim()

    if ([System.String]::Equals("$($Setting.Authentication)", 'Certificate', [System.StringComparison]::Ordinal)) {
        $arguments['Tenant'] = [System.Guid]::Parse("$($Setting.TenantId)".Trim()).ToString()
        $thumbprint = "$($Setting.CertificateThumbprint)".Trim()
        if ($thumbprint) {
            $arguments['Thumbprint'] = $thumbprint.ToUpperInvariant()
        }
        else {
            $arguments['CertificatePath'] = "$($Setting.CertificatePath)".Trim()
            if ($null -ne $CertificatePassword) {
                $arguments['CertificatePassword'] = $CertificatePassword
            }
        }
    }
    else {
        $arguments['Interactive'] = $true
        $arguments['Tenant'] = "$("$($Setting.TenantName)".Trim().ToLowerInvariant()).onmicrosoft.com"
    }

    $arguments
}
