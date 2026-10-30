function Test-SPSLifecycleListingApiType {
    <#
        .SYNOPSIS
        Checks that the types of the SharePoint admin API have what the paged listing uses.

        .DESCRIPTION
        The paged listing (Get-SPSLifecycleTenantSitePage) builds a filter, sets four of its properties
        (IncludeDetail, IncludePersonalSite, Filter, StartIndex) and calls a method of the tenant with it. A version of
        PnP.PowerShell where a type is missing, a property has another name or type, or the method takes something else,
        would fail in the middle of a listing, or worse, ignore a filter. The check is made before the first page.

        The types are given, so that the check does not need the tenant and can be tested with types of the same shape.

        Returns an object with Available and Reason (empty when it is available).

        .PARAMETER TenantType
        The type of the tenant of the admin API, or $null when it is not found.

        .PARAMETER FilterType
        The type of the filter of the paged call, or $null.

        .PARAMETER PersonalSiteFilterType
        The enumeration that says what to do about the OneDrive sites, or $null.

        .EXAMPLE
        Test-SPSLifecycleListingApiType -TenantType $tenant -FilterType $filter -PersonalSiteFilterType $personal
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Type]
        $TenantType,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Type]
        $FilterType,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Type]
        $PersonalSiteFilterType
    )

    $result = {
        param($Reason)
        [PSCustomObject][ordered]@{ Available = (-not $Reason); Reason = $Reason }
    }

    if ($null -eq $TenantType -or $null -eq $FilterType -or $null -eq $PersonalSiteFilterType) {
        return & $result 'The types of the SharePoint admin API (Tenant, SPOSitePropertiesEnumerableFilter, PersonalSiteFilter) are not in this PnP.PowerShell.'
    }

    $expected = [ordered]@{
        Filter              = [System.String]
        IncludeDetail       = [System.Boolean]
        IncludePersonalSite = $PersonalSiteFilterType
        StartIndex          = [System.String]
    }
    foreach ($name in $expected.Keys) {
        $property = $FilterType.GetProperty($name)
        if ($null -eq $property) {
            return & $result "The filter of the admin API has no property '$name' in this PnP.PowerShell."
        }

        if ($property.PropertyType -ne $expected[$name] -or -not $property.CanWrite) {
            return & $result "The property '$name' of the filter of the admin API is not a writable $($expected[$name].Name) in this PnP.PowerShell."
        }
    }

    if (-not $PersonalSiteFilterType.IsEnum -or [System.Enum]::GetNames($PersonalSiteFilterType) -cnotcontains 'Exclude') {
        return & $result "The enumeration of the OneDrive sites has no value 'Exclude' in this PnP.PowerShell."
    }

    $method = $TenantType.GetMethod('GetSitePropertiesFromSharePointByFilters', [System.Type[]]@($FilterType))
    if ($null -eq $method) {
        return & $result 'The tenant of the admin API has no method GetSitePropertiesFromSharePointByFilters that takes the filter in this PnP.PowerShell.'
    }

    $page = $method.ReturnType
    $token = $page.GetProperty('NextStartIndexFromSharePoint')
    if ($null -eq $token -or $token.PropertyType -ne [System.String]) {
        return & $result "The page that the admin API gives has no text property 'NextStartIndexFromSharePoint' in this PnP.PowerShell."
    }

    & $result ''
}
