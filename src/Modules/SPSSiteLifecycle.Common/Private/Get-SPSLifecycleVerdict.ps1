function Get-SPSLifecycleVerdict {
    <#
        .SYNOPSIS
        Gives the verdict for one site: what the tool suggests (Scan) or would do (Act).

        .DESCRIPTION
        The gates are checked in a fixed order and the first one that matches decides. Every verdict
        is listed, with its meaning, in Get-SPSLifecycleVerdictCatalog.

        1. OneDrive, channel site, protected site, archived site.
        2. The lock state, the exclusion lists, and the lock age of a read-only site.
        3. Scan only: the activity reports and the last content change.
        4. The size, when the verdict depends on it.
        5. Act only: the state of the Microsoft 365 group.
        6. The outcome of the action: LOCK, ARCHIVE, DELETE-SITE or DELETE-VIA-GROUP, or a refusal
           (template that cannot be archived, site too large to delete).

        With Action Suggest (the Scan phase), the tool picks the action: Lock for an unlocked
        site, otherwise Delete for a site up to DeleteMaxSizeGB and Archive above it. With Delete,
        Archive or Lock (the Act phase), the action is the decision of a person, and a decision never
        lifts a gate.

        The function reads nothing and changes nothing: the caller gives it the state it has read. An
        input that is missing or cannot be read (a size that is blank, negative or not a number, a
        group state that was not read) never leads to an action: the verdict is a REVIEW one.

        .PARAMETER Site
        The site record: Url, Template, LockState, GroupId, IsHubSite, IsTeamsChannelConnected,
        ArchiveStatus, StorageUsedMB and LastContentModified.

        .PARAMETER Setting
        The effective settings (see Get-SPSLifecycleSetting).

        .PARAMETER Action
        Suggest, Delete, Archive or Lock.

        .PARAMETER Now
        The current time in UTC.

        .PARAMETER LockedOn
        The date the site was locked, when known.

        .PARAMETER Excluded
        True when the site is in an exclusion file.

        .PARAMETER Activity
        Scan only: an object with HasRow (the site is in an activity report) and LastActivity (the
        latest date over the reports, or $null).

        .PARAMETER GroupState
        Act only: None, Active, SoftDeleted or NotFound, as read live. For a site that has a group, any
        other state than Active, an empty one included, gives a REVIEW verdict: a state that was not
        read never lets an action through. Leave it empty in Scan, which does not read groups.

        .PARAMETER HomeSiteUrl
        The URL of the SharePoint home site, when known.

        .EXAMPLE
        Get-SPSLifecycleVerdict -Site $site -Setting $setting -Action Suggest -Activity $activity -LockedOn $lockedOn
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Site,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Suggest', 'Delete', 'Archive', 'Lock')]
        [System.String]
        $Action,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow,

        [Parameter()]
        [AllowNull()]
        [System.Nullable[System.DateTime]]
        $LockedOn = $null,

        [Parameter()]
        [System.Boolean]
        $Excluded = $false,

        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSObject]
        $Activity = $null,

        [Parameter()]
        [AllowEmptyString()]
        [ValidateSet('', 'None', 'Active', 'SoftDeleted', 'NotFound')]
        [System.String]
        $GroupState = '',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $HomeSiteUrl = ''
    )

    $template = "$($Site.Template)"
    $lockState = "$($Site.LockState)"
    $groupId = ConvertTo-SPSLifecycleId -Value $Site.GroupId
    $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $Site.Url
    $accepted = @($Setting.AcceptedLockStates)

    if ($template -like 'SPSPERS#*' -or $urlKey.StartsWith("https://$($Setting.TenantName)-my.sharepoint.com")) {
        return 'SKIP-ONEDRIVE'
    }

    if ($template -like 'TEAMCHANNEL#*' -or $Site.IsTeamsChannelConnected -eq $true) {
        return 'SKIP-CHANNEL-SITE'
    }

    if (Test-SPSLifecycleProtectedSite -Site $Site -TenantUrl $Setting.TenantUrl -HomeSiteUrl $HomeSiteUrl) {
        return 'SKIP-PROTECTED'
    }

    $archiveStatus = "$($Site.ArchiveStatus)"
    if ($archiveStatus -and $archiveStatus -ne 'NotArchived') {
        return 'SKIP-ALREADY-ARCHIVED'
    }

    $suggestLock = $false
    switch ($Action) {
        'Lock' {
            if ($lockState -ne 'Unlock') {
                return 'SKIP-LOCK-STATE'
            }
        }

        'Suggest' {
            if ($lockState -eq 'Unlock' -and $accepted -notcontains 'Unlock') {
                $suggestLock = $true
            }
            elseif ($accepted -notcontains $lockState) {
                return 'SKIP-LOCK-STATE'
            }
        }

        default {
            if ($accepted -notcontains $lockState) {
                return 'SKIP-LOCK-STATE'
            }
        }
    }

    if ($Excluded) {
        return 'SKIP-EXCLUDED'
    }

    if ($lockState -eq 'ReadOnly' -and $Action -ne 'Lock') {
        if ($null -eq $LockedOn) {
            return 'SKIP-NO-LOCK-DATE'
        }

        if (($Now - $LockedOn).TotalDays -lt $Setting.MinLockedDays) {
            return 'SKIP-TOO-RECENT-LOCK'
        }
    }

    if ($Action -eq 'Suggest') {
        if (-not $Activity -or -not $Activity.HasRow) {
            return 'REVIEW-NO-ACTIVITY-ROW'
        }

        $lastTouch = $Activity.LastActivity
        $modified = $Site.LastContentModified
        if ($modified -and (-not $lastTouch -or $modified -gt $lastTouch)) {
            $lastTouch = $modified
        }

        if ($lastTouch -and ($Now - $lastTouch).TotalDays -lt $Setting.Scan.InactiveDays) {
            return 'SKIP-RECENT-ACTIVITY'
        }
    }

    # A size that is missing, blank, negative, not a number or not finite is unknown. It is never read as zero.
    $sizeMB = 0.0
    $sizeKnown = [System.Double]::TryParse("$($Site.StorageUsedMB)".Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$sizeMB) -and [System.Double]::IsFinite($sizeMB) -and $sizeMB -ge 0
    $needsSize = ($Action -eq 'Delete') -or ($Action -eq 'Suggest' -and -not $suggestLock)
    if ($needsSize -and -not $sizeKnown) {
        return 'REVIEW-NO-SIZE'
    }

    # In Act, a group-connected site needs a group that was read and is active: a missing state is not a green light.
    # Scan does not read groups, so it only checks a state that the caller gives.
    if ($groupId -and ($Action -ne 'Suggest' -or $GroupState)) {
        if ($GroupState -eq 'SoftDeleted') {
            return 'REVIEW-GROUP-SOFTDELETED'
        }

        if ($GroupState -ne 'Active') {
            return 'REVIEW-GROUP-NOTFOUND'
        }
    }

    $tooLarge = $sizeKnown -and (($sizeMB / 1024) -gt $Setting.DeleteMaxSizeGB)
    $deleteVerdict = if ($groupId) { 'DELETE-VIA-GROUP' } else { 'DELETE-SITE' }
    $archivable = Test-SPSLifecycleArchivableTemplate -Template $template

    switch ($Action) {
        'Lock' {
            return 'LOCK'
        }

        'Archive' {
            if (-not $archivable) {
                return 'SKIP-NOT-ARCHIVABLE'
            }

            return 'ARCHIVE'
        }

        'Delete' {
            if ($tooLarge) {
                return 'SKIP-TOO-LARGE-TO-DELETE'
            }

            return $deleteVerdict
        }

        default {
            if ($suggestLock) {
                return 'LOCK'
            }

            if (-not $tooLarge) {
                return $deleteVerdict
            }

            if (-not $archivable) {
                return 'SKIP-NOT-ARCHIVABLE'
            }

            return 'ARCHIVE'
        }
    }
}
