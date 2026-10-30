function Test-SPSLifecycleRefusedTenant {
    <#
        .SYNOPSIS
        Tells whether the tool refuses to run on a tenant.

        .DESCRIPTION
        The tool never runs on the Microsoft corporate tenants, nor on a tenant that the settings list (see
        Get-SPSLifecycleRefusedTenantList). The name is compared in lowercase, whatever the case it was written in and
        the culture of the machine. A name that is empty is refused too: nothing can say which tenant it is.

        The settings are checked with this function when they are read, and the adapter checks again right before it
        signs in, so that a settings object that was built or changed in between cannot lead the tool to a refused
        tenant.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .PARAMETER RefusedTenant
        The tenants of the RefusedTenants setting.

        .EXAMPLE
        Test-SPSLifecycleRefusedTenant -TenantName 'contoso' -RefusedTenant 'fabrikam'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $TenantName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $RefusedTenant = @()
    )

    $name = "$TenantName".Trim().ToLowerInvariant()
    if (-not $name) {
        return $true
    }

    (Get-SPSLifecycleRefusedTenantList -RefusedTenant $RefusedTenant) -contains $name
}
