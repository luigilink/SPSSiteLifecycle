function Test-SPSLifecycleOneDrive {
    <#
        .SYNOPSIS
        Tells whether a site is one that the tool leaves out with OneDrive (D12): a OneDrive site, or a site whose address it cannot read.

        .DESCRIPTION
        A site is a OneDrive site when its template is a personal one (SPSPERS#*) or when it is at the OneDrive
        host of the tenant (contoso-my.sharepoint.com for the tenant contoso), compared whole and without regard to
        the case (and not to the culture: Turkish does not read an i like English does). User information in front
        of the host does not hide it.

        A site whose address is not in the form that SharePoint gives is left out with them, because nothing can say
        what it is. That form is an https address whose host is the one that DNS sees: the host after the IDNA mapping
        (IdnHost) is the host as it is written (Host), with no dot of the DNS root and no port other than the default
        one. The mapping changes a host that has a soft hyphen, a zero-width space, a full-width letter, an ideographic
        full stop or a letter that is not ASCII, and it refuses a host that has a bidirectional isolate or a zero-width
        joiner. Combined with user information, a port or the dot of the DNS root, these spellings are too many to
        list, and they hide a OneDrive host as well as the root site, the home site or an excluded site, whose
        addresses are compared as text. An address that does not parse, a text that is not an address and another
        scheme (http included) are left out as well. A site that is left out by mistake is safe, and a site that is
        listed by mistake is not. A host that only starts like the OneDrive host is left out too, and a site whose path
        only looks like the OneDrive host is not.

        An empty address is not left out here: the caller says that it is missing.

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

    if ("$($Site.Template)".Trim().StartsWith('SPSPERS#', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $text = "$($Site.Url)".Trim()
    if (-not $text) {
        return $false
    }

    $uri = $null
    $isPlain = [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -eq 'https' -and $uri.IsDefaultPort
    if ($isPlain) {
        # PowerShell gives $null for IdnHost when the IDNA mapping of the host fails. The comparison is ordinal: a culture
        # ignores the characters that the mapping drops, and would read the two hosts as the same.
        $dnsHost = $uri.IdnHost
        $isPlain = $null -ne $dnsHost -and
        -not $uri.Host.EndsWith('.', [System.StringComparison]::Ordinal) -and
        [System.String]::Equals($dnsHost, $uri.Host, [System.StringComparison]::Ordinal)
    }

    if (-not $isPlain) {
        return $true
    }

    $oneDriveHost = "$TenantName-my.sharepoint.com"
    $uri.Host.Equals($oneDriveHost, [System.StringComparison]::OrdinalIgnoreCase) -or $text.StartsWith("https://$oneDriveHost", [System.StringComparison]::InvariantCultureIgnoreCase)
}
