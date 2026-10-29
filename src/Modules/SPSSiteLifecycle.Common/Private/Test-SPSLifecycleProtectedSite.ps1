function Test-SPSLifecycleProtectedSite {
    <#
        .SYNOPSIS
        Tells whether a site is one that the tool never touches.

        .DESCRIPTION
        A site is protected when it is the root site of the tenant, a hub site, the home site, a
        system site by its path (see Get-SPSLifecycleProtectedPath), or when its template is a
        system template (see Get-SPSLifecycleProtectedTemplate).

        .PARAMETER Site
        The site record: Url, Template and IsHubSite.

        .PARAMETER TenantUrl
        The root URL of the tenant, for example https://contoso.sharepoint.com.

        .PARAMETER HomeSiteUrl
        The URL of the SharePoint home site, when known.

        .EXAMPLE
        Test-SPSLifecycleProtectedSite -Site $site -TenantUrl 'https://contoso.sharepoint.com'
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
        $TenantUrl,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $HomeSiteUrl = ''
    )

    $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $Site.Url
    if ($urlKey -and $urlKey -eq (ConvertTo-SPSLifecycleUrlKey -Url $TenantUrl)) {
        return $true
    }

    if ($urlKey -and $HomeSiteUrl -and $urlKey -eq (ConvertTo-SPSLifecycleUrlKey -Url $HomeSiteUrl)) {
        return $true
    }

    if ($Site.IsHubSite -eq $true) {
        return $true
    }

    $uri = $null
    if ([System.Uri]::TryCreate("$($Site.Url)".Trim(), [System.UriKind]::Absolute, [ref]$uri)) {
        $path = [System.Uri]::UnescapeDataString($uri.AbsolutePath).TrimEnd('/').ToLowerInvariant()
        foreach ($protected in @(Get-SPSLifecycleProtectedPath)) {
            if ($path -eq $protected.Path) {
                return $true
            }
        }
    }

    $template = "$($Site.Template)"
    foreach ($protected in @(Get-SPSLifecycleProtectedTemplate)) {
        if ($template -like $protected.Pattern) {
            return $true
        }
    }

    $false
}
