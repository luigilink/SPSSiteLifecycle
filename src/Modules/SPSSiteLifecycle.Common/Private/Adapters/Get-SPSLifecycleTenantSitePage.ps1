function Get-SPSLifecycleTenantSitePage {
    <#
        .SYNOPSIS
        Reads one page of the sites of the tenant, and gives it as site records.

        .DESCRIPTION
        This is the only function that asks the tenant for its sites. It gives the object that the listing reads: Items,
        the records of the page (see ConvertTo-SPSLifecycleSitePage), and NextStartIndex, the token of the next page.

        Csom is the paged call of the SharePoint admin API, Tenant.GetSitePropertiesFromSharePointByFilters, about 1,500
        sites a page, with the details, and with the OneDrive sites left out by the server (D12). The server filters on the
        text that it is given (see Get-SPSLifecycleListingFilter). The token of a page is the one that the page before gave
        (NextStartIndexFromSharePoint), and a page that holds no site of the filter comes back empty with a token. The query
        goes through Invoke-PnPQuery, which asks again when the tenant throttles.

        Cmdlet is Get-PnPTenantSite, the fallback: the whole listing in one page, with no token, so that it cannot be resumed.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Source
        Csom or Cmdlet.

        .PARAMETER StartIndex
        The token of the page, empty for the first.

        .PARAMETER Filter
        The server filter, empty for none.

        .EXAMPLE
        Get-SPSLifecycleTenantSitePage -Session $session -Source Csom -StartIndex '' -Filter "LockState -eq 'ReadOnly'"
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Csom', 'Cmdlet')]
        [System.String]
        $Source,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $StartIndex = '',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Filter = ''
    )

    if ($Source -eq 'Cmdlet') {
        $parameters = @{ Detailed = $true; Connection = $Session.Connection }
        if ($Filter) {
            $parameters.Filter = $Filter
        }

        return ConvertTo-SPSLifecycleSitePage -Item @(Get-PnPTenantSite @parameters -ErrorAction Stop) -Source Cmdlet -NextStartIndex ''
    }

    $context = Get-PnPContext -Connection $Session.Connection -ErrorAction Stop
    $tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($context)
    $request = Get-SPSLifecycleListingRequest -Filter $Filter -StartIndex $StartIndex
    $result = $tenant.GetSitePropertiesFromSharePointByFilters($request)
    $context.Load($result)
    Invoke-PnPQuery -RetryCount 5 -Connection $Session.Connection -ErrorAction Stop

    ConvertTo-SPSLifecycleSitePage -Item $result -Source Csom -NextStartIndex "$($result.NextStartIndexFromSharePoint)"
}
