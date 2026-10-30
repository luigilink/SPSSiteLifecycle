function Assert-SPSLifecycleSignInSetting {
    <#
        .SYNOPSIS
        Stops, before the tool asks for a password or reads a certificate, when the settings of the sign-in are not complete or not right.

        .DESCRIPTION
        The settings were checked when they were read (Get-SPSLifecycleSetting), and the sign-in checks them again with what it will
        use, so that a settings object that was built or changed in between cannot lead it to the wrong one. The client ID is needed
        in every case. The way to sign in is exactly Interactive or Certificate (read as it is written: the case that the settings
        reader gives, nothing else). For Certificate the tenant ID must be a GUID that is not all zeros, and exactly one of the
        thumbprint (40 hexadecimal characters) and the file must be given.

        .PARAMETER Setting
        The settings (ClientId, Authentication, TenantId, CertificateThumbprint, CertificatePath).

        .EXAMPLE
        Assert-SPSLifecycleSignInSetting -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    if (-not "$($Setting.ClientId)".Trim()) {
        throw 'ClientId: the sign-in needs the application (client) ID of the app registration of the tenant.'
    }

    $authentication = "$($Setting.Authentication)"
    if (-not $authentication -or [System.String]::Equals($authentication, 'Interactive', [System.StringComparison]::Ordinal)) {
        return
    }

    if (-not [System.String]::Equals($authentication, 'Certificate', [System.StringComparison]::Ordinal)) {
        throw "Authentication: '$(ConvertTo-SPSLifecycleVisibleText -Text $authentication -AsciiOnly)' is not a way to sign in: Interactive or Certificate."
    }

    $tenantId = [System.Guid]::Empty
    if (-not [System.Guid]::TryParse("$($Setting.TenantId)".Trim(), [ref]$tenantId) -or $tenantId -eq [System.Guid]::Empty) {
        throw "TenantId: the certificate sign-in needs the ID of the Microsoft Entra tenant, a GUID (now: '$(ConvertTo-SPSLifecycleVisibleText -Text "$($Setting.TenantId)" -AsciiOnly)')."
    }

    $thumbprint = "$($Setting.CertificateThumbprint)".Trim()
    $path = "$($Setting.CertificatePath)".Trim()
    if ([System.Boolean]$thumbprint -eq [System.Boolean]$path) {
        throw 'Authentication is Certificate, which needs exactly one of CertificateThumbprint and CertificatePath.'
    }

    if ($thumbprint -and -not [System.Text.RegularExpressions.Regex]::IsMatch($thumbprint, '\A[0-9A-Fa-f]{40}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw 'CertificateThumbprint: must be 40 hexadecimal characters, with no spaces or colons.'
    }
}
