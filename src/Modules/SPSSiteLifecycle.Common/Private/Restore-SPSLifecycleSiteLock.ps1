function Restore-SPSLifecycleSiteLock {
    <#
        .SYNOPSIS
        Locks a site again that the tool unlocked, and says whether it is locked, from what the site reports.

        .DESCRIPTION
        A request to lock a site returns before the site has changed state (see Set-SPSLifecycleSiteLockState), so it is not said
        that the site is locked until it reports ReadOnly (see Wait-SPSLifecycleLockState). Before the request, the site is read: a
        site that is not there has nothing to lock, and an address that now belongs to another site (another site ID) is left as it is,
        because the lock that the tool put on is not that site's. The request is sent even when the site reports ReadOnly, since an
        earlier request to unlock it may still be on its way.

        It never throws. It gives Locked ($true only when the site reported ReadOnly) and Note, a sentence for the report: the site
        was locked again, or why it is not known to be, and that the person has to look.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .PARAMETER SiteId
        The ID of the site that was unlocked.

        .EXAMPLE
        Restore-SPSLifecycleSiteLock -Session $session -Url $url -SiteId $siteId
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
        $Url,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SiteId
    )

    try {
        $live = Get-SPSLifecycleLiveSite -Session $Session -Url $Url
        if ($null -eq $live) {
            return [PSCustomObject]@{ Locked = $false; Note = 'The site is not there any more, so there is nothing to lock again.' }
        }

        if (-not [System.String]::Equals((ConvertTo-SPSLifecycleId -Value $live.SiteId), $SiteId, [System.StringComparison]::Ordinal)) {
            return [PSCustomObject]@{ Locked = $false; Note = 'The address belongs to another site now, which was left as it is.' }
        }

        Set-SPSLifecycleSiteLockState -Session $Session -Url $Url -State ReadOnly
        if ($null -ne (Wait-SPSLifecycleLockState -Session $Session -Url $Url -State ReadOnly -SiteId $SiteId)) {
            return [PSCustomObject]@{ Locked = $true; Note = 'The site was locked again.' }
        }

        [PSCustomObject]@{ Locked = $false; Note = 'The lock request was sent, but the site did not report ReadOnly within 2 minutes: check it, and lock it by hand if it is not read-only.' }
    }
    catch {
        [PSCustomObject]@{ Locked = $false; Note = "The site could not be locked again: $($_.Exception.Message.Trim().TrimEnd('.')). Lock it by hand." }
    }
}
