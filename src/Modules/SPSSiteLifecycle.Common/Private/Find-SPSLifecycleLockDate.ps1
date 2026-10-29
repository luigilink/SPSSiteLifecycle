function Find-SPSLifecycleLockDate {
    <#
        .SYNOPSIS
        Gives the lock date of a site, and the file that gave it.

        .DESCRIPTION
        An entry that has a site ID is looked up by that ID, and an entry that has none by the canonical form
        of its URL. An entry whose site ID is another one is ignored, even when the address is the same: that
        site reused the address of a site that is gone. When both kinds of entry match, the latest date wins and
        the entry of the site ID wins a tie.

        When the ID of the site is unknown (empty, not a GUID, all zeros), nothing is found. The tool cannot
        tell whose date an entry would be: a replacement site at the address of a site that was locked years ago
        would inherit its date and become a candidate for deletion, and an entry that is left out could just as
        well hide the more recent lock of the site itself. A site without a lock date is never touched, which
        is the one answer that is safe in both cases. The Scan phase reads the site ID of every site, and the
        Act phase reads it again before an action, so this is not a case that a run meets.

        Returns the entry (Url, UrlKey, SiteId, LockedOn, Source), or nothing when no source knows the site.

        .PARAMETER Index
        The index from Merge-SPSLifecycleLockDate.

        .PARAMETER SiteId
        The ID of the site, as the tenant gives it now.

        .PARAMETER Url
        The URL of the site.

        .EXAMPLE
        Find-SPSLifecycleLockDate -Index $index -SiteId $site.SiteId -Url $site.Url
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Index,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $SiteId = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Url = ''
    )

    $id = ConvertTo-SPSLifecycleId -Value $SiteId
    if (-not $id) {
        return
    }

    $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $Url
    $found = $null
    if ($Index.ById.ContainsKey($id)) {
        $found = $Index.ById[$id]
    }

    if ($urlKey -and $Index.ByUrl.ContainsKey($urlKey)) {
        $byAddress = $Index.ByUrl[$urlKey]
        if ($null -eq $found -or $byAddress.LockedOn -gt $found.LockedOn) {
            $found = $byAddress
        }
    }

    $found
}
