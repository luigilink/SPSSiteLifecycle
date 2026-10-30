function ConvertTo-SPSLifecycleSitePage {
    <#
        .SYNOPSIS
        Gives the page that the listing reads from the sites that a call gave.

        .DESCRIPTION
        The adapters call the tenant and hand what they get to this function, which holds all that is not a call: the first
        site of the page is checked for properties that the call did not load (see Assert-SPSLifecycleSiteLoaded, which is
        the reason why a missing group ID cannot be read as no group), and each site becomes a record (see
        ConvertTo-SPSLifecycleSiteRecord). A page that holds no site is a page, with a token: a server filter makes them
        common.

        Returns an object with Items (the records) and NextStartIndex (the token of the next page, empty after the last).

        .PARAMETER Item
        The sites that the call gave: possibly none.

        .PARAMETER Source
        Csom for the paged call of the admin API, Cmdlet for Get-PnPTenantSite.

        .PARAMETER NextStartIndex
        The token of the next page.

        .EXAMPLE
        ConvertTo-SPSLifecycleSitePage -Item $result -Source Csom -NextStartIndex $result.NextStartIndexFromSharePoint
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Item,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Csom', 'Cmdlet')]
        [System.String]
        $Source,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [System.String]
        $NextStartIndex
    )

    $sites = @(if ($null -ne $Item) { $Item })
    if ($sites.Count -gt 0) {
        Assert-SPSLifecycleSiteLoaded -Item $sites[0] -Source $Source
    }

    $records = [System.Collections.Generic.List[System.Object]]::new($sites.Count)
    foreach ($site in $sites) {
        $records.Add((ConvertTo-SPSLifecycleSiteRecord -Item $site -Source $Source))
    }

    [PSCustomObject][ordered]@{
        Items          = $records.ToArray()
        NextStartIndex = "$NextStartIndex"
    }
}
