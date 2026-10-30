function Get-SPSLifecycleActVerdict {
    <#
        .SYNOPSIS
        Gives the verdict of a row of the reviewed report from the live state of its site and of its group, right before its action.

        .DESCRIPTION
        A site can change between the Scan and the Act (days or weeks apart), and an address can be reused by another site. So the
        Act phase reads the site again for each row, and this function decides from what it reads (D6). It changes nothing.

        1. The site is read by its address (Get-SPSLifecycleLiveSite). A site that is not there is SKIP-NOT-FOUND, and an address
           that now belongs to another site (another site ID) is SKIP-SITEID-MISMATCH. A tenant that answers with a site of
           another address, or a group ID that is not a GUID (a site taken for one without a group would be deleted as a site),
           is an error.
        2. The verdict engine (Get-SPSLifecycleVerdict) decides with the live site, the decision of the person as the action, the
           lock dates and the exclusion lists, the home site, and the state of the group. The decision never lifts a gate. The
           group is read (Get-SPSLifecycleGroupState) only when the site has one and every gate before the group has been passed,
           so that a row that is stopped earlier costs no call to Microsoft Graph. A group state that is not one of the four is
           taken for a state that was not read: the group cannot be confirmed active.
        3. A row that the engine would let through (LOCK, ARCHIVE, DELETE-SITE or DELETE-VIA-GROUP) is then kept back, in this
           order: REVIEW-CONTENT-MODIFIED when the content of the site changed after the report was generated (GeneratedOn), or
           when its date cannot be read, and REVIEW-RETENTION when the tenant reports a hold on the site or does not report the
           flag at all (only a flag that says False lets the row through: an unread safeguard is not a green light). A verdict
           that already stops the row (a SKIP- or a REVIEW-) is kept: it says more, and the row is not an action either way. A
           retention policy that the site does not report is not seen: the tool cannot see every Microsoft Purview policy.

        A read that fails (throttling, network, access denied) is not a verdict and never leads to an action: the result has the
        message in ReadError and an empty Verdict, which the loop counts for its stop after 3 errors in a row.

        Returns Verdict, ReadError, Site (the live record, empty when the site was not read or was not the one asked for),
        GroupState ('' when it was not read, None for a site without a group) and LockedOn (the lock date that the sources give).

        .PARAMETER Row
        The row of the reviewed report (see Import-SPSLifecycleReviewedReport): Line, Url, SiteId, Decision (Delete, Archive or
        Lock) and GeneratedOn. A row without one of them, or with another decision, stops the function: nothing is read.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Setting
        The effective settings (see Get-SPSLifecycleSetting).

        .PARAMETER LockDateIndex
        The index of the lock dates (Get-SPSLifecycleLockDateIndex).

        .PARAMETER ExclusionIndex
        The index of the exclusion lists (Get-SPSLifecycleExclusionIndex).

        .PARAMETER HomeSiteUrl
        The address of the home site, which is protected (see Get-SPSLifecycleHomeSiteUrl).

        .PARAMETER Now
        The current time in UTC.

        .EXAMPLE
        Get-SPSLifecycleActVerdict -Row $row -Session $session -Setting $setting -LockDateIndex $locks -ExclusionIndex $exclusions -HomeSiteUrl $home
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Row,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $LockDateIndex,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $ExclusionIndex,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $HomeSiteUrl = '',

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $line = "$($Row.Line)"
    $decision = "$($Row.Decision)"
    $known = $false
    foreach ($name in 'Delete', 'Archive', 'Lock') {
        if ([System.String]::Equals($decision, $name, [System.StringComparison]::Ordinal)) {
            $known = $true
        }
    }

    if (-not $known) {
        throw "Decision '$(ConvertTo-SPSLifecycleVisibleText -Text $decision -AsciiOnly)' (line $line) is not Delete, Archive or Lock: the tool never acts on a decision that it does not know."
    }

    $rowSiteId = ConvertTo-SPSLifecycleId -Value $Row.SiteId
    if (-not $rowSiteId) {
        throw "The row at line $line has no usable SiteId: without it the site that is read cannot be told from a site that reused its address."
    }

    $url = "$($Row.Url)".Trim()
    if (-not $url) {
        throw "The row at line $line has no Url."
    }

    $generatedOn = ConvertTo-SPSLifecycleUtcDateTime -Value $Row.GeneratedOn
    if ($null -eq $generatedOn) {
        throw "The row at line $line has no GeneratedOn: the tool cannot tell whether the site changed since the Scan."
    }

    $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $url
    $nowUtc = ConvertTo-SPSLifecycleUtcDateTime -Value $Now
    $result = [PSCustomObject][ordered]@{
        Verdict    = ''
        ReadError  = ''
        Site       = $null
        GroupState = ''
        LockedOn   = $null
    }

    try {
        $site = Get-SPSLifecycleLiveSite -Session $Session -Url $url
    }
    catch {
        $result.ReadError = $_.Exception.Message
        return $result
    }

    if ($null -eq $site) {
        $result.Verdict = 'SKIP-NOT-FOUND'
        return $result
    }

    if ((ConvertTo-SPSLifecycleUrlKey -Url $site.Url) -ne $urlKey) {
        $result.ReadError = "The tenant answered with the site of another address than the one that was asked for ($url), so the answer is not used."
        return $result
    }

    $result.Site = $site
    $liveSiteId = ConvertTo-SPSLifecycleId -Value $site.SiteId
    if (-not [System.String]::Equals($liveSiteId, $rowSiteId, [System.StringComparison]::Ordinal)) {
        $result.Verdict = 'SKIP-SITEID-MISMATCH'
        return $result
    }

    # An empty group ID and the all-zero one that the tenant gives to a site without a group say that there is no group. Any other
    # value that is not a GUID is not "no group": the site would be deleted as a site, and its group left behind.
    $groupId = ConvertTo-SPSLifecycleId -Value $site.GroupId
    if (-not $groupId) {
        $groupText = "$($site.GroupId)".Trim()
        $zero = [System.Guid]::Empty
        if ($groupText -and -not [System.Guid]::TryParse($groupText, [ref]$zero)) {
            $result.ReadError = "The group ID of the site ($url) is not a GUID ('$(ConvertTo-SPSLifecycleVisibleText -Text $groupText)'), so its group cannot be read."
            return $result
        }

        $result.GroupState = 'None'
    }

    $lock = Find-SPSLifecycleLockDate -Index $LockDateIndex -SiteId $liveSiteId -Url $site.Url
    if ($null -ne $lock) {
        $result.LockedOn = $lock.LockedOn
    }

    $verdictParameters = @{
        Site        = $site
        Setting     = $Setting
        Action      = $decision
        Now         = $nowUtc
        Excluded    = [System.Boolean]$ExclusionIndex.Keys.ContainsKey($urlKey)
        HomeSiteUrl = $HomeSiteUrl
    }
    if ($null -ne $result.LockedOn) {
        $verdictParameters.LockedOn = $result.LockedOn
    }

    # The group gate comes after the others: the engine says that it reached it by asking for a state that was not read.
    $verdict = Get-SPSLifecycleVerdict @verdictParameters -GroupState ''
    if ($groupId -and $verdict -eq 'REVIEW-GROUP-NOTFOUND') {
        try {
            $state = "$(Get-SPSLifecycleGroupState -Session $Session -GroupId $groupId)"
        }
        catch {
            $result.ReadError = $_.Exception.Message
            return $result
        }

        # Compared one character at a time: the comparison operators do not see a hidden character, and a state that is not exactly one
        # of the four is a state that was not read.
        $result.GroupState = ''
        foreach ($name in 'None', 'Active', 'SoftDeleted', 'NotFound') {
            if ([System.String]::Equals($state, $name, [System.StringComparison]::Ordinal)) {
                $result.GroupState = $name
            }
        }

        $verdict = Get-SPSLifecycleVerdict @verdictParameters -GroupState $result.GroupState
    }

    if ($verdict -in 'LOCK', 'ARCHIVE', 'DELETE-SITE', 'DELETE-VIA-GROUP') {
        $modified = $site.LastContentModified
        if ($null -eq $modified -or (ConvertTo-SPSLifecycleUtcDateTime -Value $modified) -gt $generatedOn) {
            $verdict = 'REVIEW-CONTENT-MODIFIED'
        }
        elseif ($site.HasHolds -isnot [System.Boolean] -or $site.HasHolds) {
            # Only a flag that says False lets the row through: a hold that the tenant does not report (an older PnP.PowerShell, a value that is
            # not a boolean) cannot be ruled out, and an unread safeguard is not a green light.
            $verdict = 'REVIEW-RETENTION'
        }
    }

    $result.Verdict = $verdict
    $result
}
