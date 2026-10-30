function Get-SPSLifecycleLiveSite {
    <#
        .SYNOPSIS
        Reads one site of the tenant by its address, as it is now, for the Act phase.

        .DESCRIPTION
        This is a read: Get-PnPTenantSite with the address and the details (about 0.7 to 0.9 s a site in the lab). It gives the
        record of the listing (see ConvertTo-SPSLifecycleSiteRecord, with the same checks: a property that the call did not
        load stops it, and the owners never leave the function) and HasHolds, whether the tenant reports a hold on the site,
        $true or $false, or $null when the answer holds no flag.

        It gives nothing when the tenant says that the site is not there (see Test-SPSLifecycleNotFoundMessage), and it
        throws when the site could not be read: the caller takes the first for a verdict and the second for an error, and
        a read that failed is never a site that is not there.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .EXAMPLE
        Get-SPSLifecycleLiveSite -Session $session -Url 'https://contoso.sharepoint.com/sites/sales'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Url
    )

    try {
        $answer = @(Get-PnPTenantSite -Identity $Url -Detailed -Connection $Session.Connection -ErrorAction Stop)
    }
    catch {
        if (Test-SPSLifecycleNotFoundMessage -Message $_.Exception.Message) {
            return
        }

        throw "The site '$Url' could not be read from the tenant: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }

    $sites = @($answer | Where-Object { $null -ne $_ })
    if ($sites.Count -eq 0) {
        return
    }

    if ($sites.Count -gt 1) {
        throw "The tenant gave more than one site ($($sites.Count)) for '$Url', so the site cannot be told from the others."
    }

    $record = ConvertTo-SPSLifecycleSiteRecord -Item $sites[0] -Source Cmdlet
    $holds = $sites[0].HasHolds
    Add-Member -InputObject $record -NotePropertyName HasHolds -NotePropertyValue $(if ($holds -is [System.Boolean]) { $holds } else { $null }) -PassThru
}
