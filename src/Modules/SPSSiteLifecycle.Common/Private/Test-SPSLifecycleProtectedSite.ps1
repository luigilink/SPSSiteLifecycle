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

    # The -like operator reads the case with the culture of the machine, and Turkish does not match FUNSITE to FunSite:
    # the patterns are compiled once, without regard to the case and not to the culture.
    if ($null -eq $script:ProtectedTemplateMatcher) {
        $script:ProtectedTemplateMatcher = @(foreach ($row in Get-SPSLifecycleProtectedTemplate) {
                [System.Management.Automation.WildcardPattern]::new($row.Pattern, [System.Management.Automation.WildcardOptions]::IgnoreCase -bor [System.Management.Automation.WildcardOptions]::CultureInvariant)
            })
    }

    $template = "$($Site.Template)".Trim()
    foreach ($matcher in $script:ProtectedTemplateMatcher) {
        if ($matcher.IsMatch($template)) {
            return $true
        }
    }

    $false
}
