function Test-SPSLifecycleOneDrive {
    <#
        .SYNOPSIS
        Tells whether a site is a OneDrive site, which the tool never touches (D12).

        .DESCRIPTION
        A site is a OneDrive site when its template is a personal one (SPSPERS#*) or when it is at the OneDrive
        host of the tenant (contoso-my.sharepoint.com for the tenant contoso). The host of the address is read, and
        compared whole, without regard to the case, to the dot of the DNS root that may end it, to the port, to the
        scheme and to user information: contoso-my.sharepoint.com. and http://someone@contoso-my.sharepoint.com:8443
        are the OneDrive host too. An address that does not parse, or whose host only starts like the OneDrive host, is
        treated as OneDrive as soon as it starts with https:// or http:// and that host: a site that is left out by
        mistake is safe, and a OneDrive site that is listed is not. A site whose path only looks like it is not one.

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

    $oneDriveHost = "$TenantName-my.sharepoint.com"
    $text = "$($Site.Url)".Trim()
    $uri = $null
    if ([System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Host.TrimEnd('.').Equals($oneDriveHost, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $text.StartsWith("https://$oneDriveHost", [System.StringComparison]::OrdinalIgnoreCase) -or $text.StartsWith("http://$oneDriveHost", [System.StringComparison]::OrdinalIgnoreCase)
}
