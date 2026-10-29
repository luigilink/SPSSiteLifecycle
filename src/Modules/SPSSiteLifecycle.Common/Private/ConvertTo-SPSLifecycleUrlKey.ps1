function ConvertTo-SPSLifecycleUrlKey {
    <#
        .SYNOPSIS
        Gives a site URL a canonical form, so that two spellings of the same URL compare equal.

        .DESCRIPTION
        The key is used as a hashtable key to match the sites of a list, a report and the tenant, and
        to compare a site with the root site, the home site and the protected paths. For a web
        address (http or https), the key is made of the scheme, the host, the port when it is not the
        default one, and the path, without the trailing slashes, the query and the fragment, with
        the percent-encoding decoded (%C3%A9 and é are the same letter) and in lowercase.

        Any other text (a path, a name) is only trimmed, stripped of its trailing slashes and
        lowercased. A null or empty value gives an empty string.

        The comparison must not depend on the culture: the invariant culture is used for the case.

        .PARAMETER Url
        The URL to normalize.

        .EXAMPLE
        ConvertTo-SPSLifecycleUrlKey -Url 'https://Contoso.sharepoint.com:443/sites/%C3%89quipe/'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Url
    )

    process {
        $text = "$Url".Trim()
        $uri = $null
        if ($text -and [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in 'http', 'https' -and $uri.Host) {
            $port = if ($uri.IsDefaultPort) { '' } else { ":$($uri.Port)" }
            $path = [System.Uri]::UnescapeDataString($uri.AbsolutePath).TrimEnd('/')
            return "$($uri.Scheme)://$($uri.Host)$port$path".ToLowerInvariant()
        }

        $text.TrimEnd('/').ToLowerInvariant()
    }
}
