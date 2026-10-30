function Get-SPSLifecycleListingRequest {
    <#
        .SYNOPSIS
        Builds the filter that the paged call of the SharePoint admin API is given.

        .DESCRIPTION
        The call lists the sites with the details, leaves the OneDrive sites out on the server (D12), applies the filter that
        it is given (see Get-SPSLifecycleListingFilter), and starts at the token that the page before gave. It is a function
        of its own because it is the only place where the property names of the admin API are written, and the only part of
        the paged call that can be checked against the types themselves without a tenant (see Test-SPSLifecycleListingApiType).

        .PARAMETER Filter
        The server filter, empty for none.

        .PARAMETER StartIndex
        The token of the page, empty for the first.

        .EXAMPLE
        Get-SPSLifecycleListingRequest -Filter "LockState -eq 'ReadOnly'" -StartIndex ''
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Filter = '',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $StartIndex = ''
    )

    $request = [Microsoft.Online.SharePoint.TenantAdministration.SPOSitePropertiesEnumerableFilter]::new()
    $request.IncludeDetail = $true
    $request.IncludePersonalSite = [Microsoft.Online.SharePoint.TenantAdministration.PersonalSiteFilter]::Exclude
    if ($Filter) {
        $request.Filter = $Filter
    }

    if ($StartIndex) {
        $request.StartIndex = $StartIndex
    }

    $request
}
