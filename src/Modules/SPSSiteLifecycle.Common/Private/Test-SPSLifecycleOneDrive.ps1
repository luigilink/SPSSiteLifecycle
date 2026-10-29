function Test-SPSLifecycleOneDrive {
    <#
        .SYNOPSIS
        Tells whether a site is a OneDrive site, which the tool never touches (D12).

        .DESCRIPTION
        A site is a OneDrive site when its template is a personal one (SPSPERS#*) or when it is at the OneDrive
        host of the tenant (contoso-my.sharepoint.com for the tenant contoso). The host is compared whole, and
        without regard to the case: a site whose path or whose host only looks like it is not one.

        The verdict engine uses it to give SKIP-ONEDRIVE, and the Scan core uses it first, to leave these sites out
        before any other work, because a tenant can hold more OneDrive sites than other sites.

        .PARAMETER Site
        The site record: Url and Template.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .EXAMPLE
        Test-SPSLifecycleOneDrive -Site $site -TenantName 'contoso'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Site,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TenantName
    )

    if ("$($Site.Template)" -like 'SPSPERS#*') {
        return $true
    }

    $oneDriveHost = "https://$TenantName-my.sharepoint.com"
    $key = ConvertTo-SPSLifecycleUrlKey -Url $Site.Url

    $key.Equals($oneDriveHost, [System.StringComparison]::OrdinalIgnoreCase) -or $key.StartsWith("$oneDriveHost/", [System.StringComparison]::OrdinalIgnoreCase)
}
