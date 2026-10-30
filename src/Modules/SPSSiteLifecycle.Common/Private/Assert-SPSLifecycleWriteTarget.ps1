function Assert-SPSLifecycleWriteTarget {
    <#
        .SYNOPSIS
        Stops unless what an adapter is about to change is a site or a group that the tool may touch, in the tenant of the session.

        .DESCRIPTION
        The adapters that change the tenant (lock, delete, archive, administrators) call this function before they call it. The Act
        phase has already decided from the live state of the row, and this is the last line: it does not read the tenant, and it
        does not trust the caller.

        - The tenant of the session must not be refused, and must be a tenant (see Assert-SPSLifecycleTenantAllowed).
        - An address must be the full https address of a site at the host of that tenant, https://<tenant>.sharepoint.com,
          exactly: no other host (the admin site, a OneDrive host, another tenant, a host with a dot at the end or with a
          letter that only looks like another), no port other than the default one, no user information, no query or
          fragment, no space or hidden character, and a path (the root site is never touched). The path is checked as it is
          written, because the adapter sends it as it is written: no backslash, no dot segment, no two slashes in a row, and no
          encoded slash, backslash or percent sign, which can hide what the path is (https://contoso.sharepoint.com/%2f is the
          root site, written in a way that a check of the decoded path would miss).
        - A group is asked for by its ID, a GUID that is not all zeros and that is written as a GUID, never by a name.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession): TenantName, AdminUrl and RefusedTenants.

        .PARAMETER Url
        The address of the site.

        .PARAMETER GroupId
        The ID of the group.

        .EXAMPLE
        Assert-SPSLifecycleWriteTarget -Session $Session -Url $Url
    #>
    [CmdletBinding(DefaultParameterSetName = 'Site')]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true, ParameterSetName = 'Site')]
        [AllowEmptyString()]
        [System.String]
        $Url,

        [Parameter(Mandatory = $true, ParameterSetName = 'Group')]
        [AllowEmptyString()]
        [System.String]
        $GroupId
    )

    Assert-SPSLifecycleTenantAllowed -Setting ([PSCustomObject]@{
            TenantName     = $Session.TenantName
            AdminUrl       = $Session.AdminUrl
            RefusedTenants = @($Session.RefusedTenants)
        })

    if ($PSCmdlet.ParameterSetName -eq 'Group') {
        $guid = [System.Guid]::Empty
        $isGuid = [System.Text.RegularExpressions.Regex]::IsMatch($GroupId, '\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant) -and
        [System.Guid]::TryParse($GroupId, [ref]$guid) -and $guid -ne [System.Guid]::Empty
        if (-not $isGuid) {
            throw "The group ID '$(ConvertTo-SPSLifecycleVisibleText -Text $GroupId)' is not a GUID that names a group (an empty text, all zeros, a name, a GUID with a space or braces are refused): the tool deletes a group only by its ID."
        }

        return
    }

    $shown = ConvertTo-SPSLifecycleVisibleText -Text $Url
    if (-not (Test-SPSLifecycleWebAddress -Text $Url)) {
        throw "'$shown' is not the web address of a site (a full address without a space or a hidden character): the tool never changes anything at an address that it cannot read as one."
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "The address '$shown' is not an https address: the tool changes a site only at https."
    }

    $tenantHost = '{0}.sharepoint.com' -f "$($Session.TenantName)".Trim().ToLowerInvariant()
    if (-not [System.String]::Equals($uri.Host, $tenantHost, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The address '$shown' is not at the host of the tenant of the session ($tenantHost): it belongs to another tenant, to OneDrive or to another service, and the tool never changes it."
    }

    if ($uri.UserInfo) {
        throw "The address '$shown' holds user information, which a site address never does."
    }

    if (-not $uri.IsDefaultPort) {
        throw "The address '$shown' has a port that is not the default one of https, which a site address never has."
    }

    if ($uri.Query) {
        throw "The address '$shown' has a query, which a site address never has."
    }

    if ($uri.Fragment) {
        throw "The address '$shown' has a fragment, which a site address never has."
    }

    # The address that an adapter sends is the one that was written, and .NET reads it more kindly than SharePoint may: a backslash is a slash,
    # a dot segment is resolved, and an encoded slash hides what the path is. So the path is checked as it is written, and nothing that needs
    # a reader to be kind is a site.
    if ($Url.Contains('\')) {
        throw "The address '$shown' has a backslash, which a site address never has."
    }

    $path = [System.Text.RegularExpressions.Regex]::Match($Url, '\Ahttps://[^/?#]*(?<path>[^?#]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant).Groups['path'].Value
    if ([System.Text.RegularExpressions.Regex]::IsMatch($path, '%(2[fF]|5[cC]|25)', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "The address '$shown' has an encoded slash, backslash or percent sign in its path, which can hide what the path is: the tool never changes it."
    }

    if ($path.Contains('//')) {
        throw "The address '$shown' has two slashes in a row in its path, which a site address never has."
    }

    foreach ($segment in $path.Split('/')) {
        if ([System.Text.RegularExpressions.Regex]::IsMatch($segment, '\A(\.|%2[eE]){1,2}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            throw "The address '$shown' has a dot segment in its path, which a site address never has."
        }
    }

    if (-not $path.Trim('/')) {
        throw "The address '$shown' is the root site of the tenant, which the tool never changes."
    }
}
