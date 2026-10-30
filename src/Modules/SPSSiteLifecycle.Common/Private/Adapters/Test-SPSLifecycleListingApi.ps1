function Test-SPSLifecycleListingApi {
    <#
        .SYNOPSIS
        Tells whether the paged call of the SharePoint admin API that the Scan lists the sites with is in this PnP.PowerShell.

        .DESCRIPTION
        The paged listing uses types of the client library that PnP.PowerShell brings (Tenant,
        SPOSitePropertiesEnumerableFilter, PersonalSiteFilter). A version that does not have them, or whose members have
        another name, cannot list the sites that way: the Scan then falls back on Get-PnPTenantSite, and says why. The
        checks are made on the types themselves (see Test-SPSLifecycleListingApiType).

        Returns an object with Available and Reason.

        .EXAMPLE
        Test-SPSLifecycleListingApi
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param ()

    $namespace = 'Microsoft.Online.SharePoint.TenantAdministration'
    Test-SPSLifecycleListingApiType -TenantType ("$namespace.Tenant" -as [System.Type]) -FilterType ("$namespace.SPOSitePropertiesEnumerableFilter" -as [System.Type]) -PersonalSiteFilterType ("$namespace.PersonalSiteFilter" -as [System.Type])
}
