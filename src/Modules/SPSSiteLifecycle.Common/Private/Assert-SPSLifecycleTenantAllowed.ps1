function Assert-SPSLifecycleTenantAllowed {
    <#
        .SYNOPSIS
        Stops, right before the sign-in, when the settings would lead the tool to a tenant that it refuses.

        .DESCRIPTION
        The settings were checked when they were read (Get-SPSLifecycleSetting), and the sign-in is the point after which
        nothing can be taken back, so the check is made again with what the sign-in will use: the tenant name must not be
        refused, the admin address must be https://<tenant>-admin.sharepoint.com (nothing else: no path, no port, no
        user information, no other host), the tenant of that address must not be refused either, and it must be the tenant
        that the settings name, so that the sign-in cannot go to another one.

        The name and the address are ASCII, checked one character at a time (see Test-SPSLifecycleTenantName): a regular
        expression that ignores the case also reads the Kelvin sign as a k and a dotted capital I as an i, and a sign-in to
        a host that is spelled with one of them would go to an address that is not the one that the settings seem to name.

        .PARAMETER Setting
        The settings (TenantName, AdminUrl, RefusedTenants), as Get-SPSLifecycleSetting gives them.

        .EXAMPLE
        Assert-SPSLifecycleTenantAllowed -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    $name = "$($Setting.TenantName)".Trim()
    if (-not $name) {
        throw 'TenantName: no tenant name was given, so the tool cannot tell which tenant it would sign in to.'
    }

    if (-not (Test-SPSLifecycleTenantName -Name $name)) {
        throw "TenantName: '$(ConvertTo-SPSLifecycleVisibleText -Text $name -AsciiOnly)' is not the name of a tenant: letters, digits and hyphens only, starting with a letter or a digit, 63 characters at most."
    }

    $refused = @($Setting.RefusedTenants)
    if (Test-SPSLifecycleRefusedTenant -TenantName $name -RefusedTenant $refused) {
        throw "TenantName: the tenant '$($name.ToLowerInvariant())' is refused. The tool never runs on the Microsoft corporate tenants or on a tenant listed in RefusedTenants."
    }

    $admin = "$($Setting.AdminUrl)".Trim()
    $match = [System.Text.RegularExpressions.Match]::Empty
    if ([System.Text.RegularExpressions.Regex]::IsMatch($admin, '\A[\u0020-\u007E]+\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        $match = [System.Text.RegularExpressions.Regex]::Match($admin, '\Ahttps://([A-Za-z0-9-]+)-admin\.sharepoint\.com/?\z', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }

    if (-not $match.Success) {
        throw "AdminUrl: '$(ConvertTo-SPSLifecycleVisibleText -Text $admin -AsciiOnly)' is not the address of the admin site of a tenant (https://<tenant>-admin.sharepoint.com)."
    }

    $adminTenant = $match.Groups[1].Value
    if (Test-SPSLifecycleRefusedTenant -TenantName $adminTenant -RefusedTenant $refused) {
        throw "AdminUrl: the tenant '$($adminTenant.ToLowerInvariant())' of the admin address is refused. The tool never runs on the Microsoft corporate tenants or on a tenant listed in RefusedTenants."
    }

    if (-not [System.String]::Equals($adminTenant, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "AdminUrl is for another tenant ('$($adminTenant.ToLowerInvariant())') than TenantName ('$($name.ToLowerInvariant())'): the sign-in would go to a tenant that the settings do not name."
    }
}
