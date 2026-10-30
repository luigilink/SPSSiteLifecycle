function Invoke-SPSLifecycleSiteAction {
    <#
        .SYNOPSIS
        Does what the verdict of a row says, to the site that was just read: lock, archive, delete the site, or delete its group.
        This changes the tenant.

        .DESCRIPTION
        The caller (the Act loop) has read the site and given the row its verdict right before (Get-SPSLifecycleActVerdict), and
        this function does what that verdict says, with the steps that the lab showed to be needed:

        - LOCK: the site is made read-only, and the tool waits for it (Wait-SPSLifecycleLockState). Then the date goes in the lock
          journal (a later run reads it as the age of the lock), and only an unlocked site is locked. A lock that the site does
          not report in 2 minutes writes no date: the request was sent, and a person checks. A date that cannot be written is an
          error: the site is locked, and the message says that its date is not in the journal.
        - DELETE-SITE (a site without a group): a read-only site refuses a direct deletion, so it is unlocked first (and waited
          for), then deleted into the recycle bin. When the deletion, or the wait, fails, the site is locked again. An unlocked
          site is deleted directly.
        - DELETE-VIA-GROUP: the group is deleted by its ID, which deletes the site some time later (from minutes to hours). The
          site is not unlocked.
        - ARCHIVE: the archive is requested (it takes place later). With UnlockBeforeArchive, a read-only site is unlocked first
          and locked again afterwards (the lab: the lock is accepted on an archived site), and with GrantSiteAdmin the signed-in
          administrator is added as an administrator of the site collection between the two (a read-only site refuses a change of
          owners). A site that was not locked is neither unlocked nor locked again.

        It returns the sentence for the report when everything went as intended, and it throws otherwise, with what failed and
        what became of the lock of the site ("The site was locked again.", or that it could not be, and to lock it by hand). Any
        verdict that is not one of the four actions, a site without an address or an ID, and a lock state that is not
        what the action takes (ReadOnly or Unlock, only Unlock for LOCK) are refused before the tenant is called.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Setting
        The effective settings: LockJournal, CsvDelimiterChar and the Act settings UnlockBeforeArchive and GrantSiteAdmin.

        .PARAMETER Verdict
        LOCK, ARCHIVE, DELETE-SITE or DELETE-VIA-GROUP.

        .PARAMETER Site
        The live record of the site (see Get-SPSLifecycleLiveSite): Url, SiteId, GroupId and LockState.

        .PARAMETER Account
        The account of the signed-in administrator (see Get-SPSLifecycleSignedInAccount), for GrantSiteAdmin.

        .PARAMETER Now
        The current time in UTC, which is the date of a lock.

        .EXAMPLE
        Invoke-SPSLifecycleSiteAction -Session $session -Setting $setting -Verdict 'DELETE-VIA-GROUP' -Site $result.Site
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Verdict,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Site,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Account = '',

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $action = $null
    foreach ($name in 'LOCK', 'ARCHIVE', 'DELETE-SITE', 'DELETE-VIA-GROUP') {
        if ([System.String]::Equals($Verdict, $name, [System.StringComparison]::Ordinal)) {
            $action = $name
        }
    }

    if ($null -eq $action) {
        throw "The verdict '$(ConvertTo-SPSLifecycleVisibleText -Text $Verdict -AsciiOnly)' is not an action: the tool changes nothing for it."
    }

    $url = "$($Site.Url)".Trim()
    $siteId = ConvertTo-SPSLifecycleId -Value $Site.SiteId
    if (-not $url -or -not $siteId) {
        throw 'The site that is to be changed has no address or no usable ID: the tool changes nothing for a site that it cannot name.'
    }

    $lockState = "$($Site.LockState)"
    $isReadOnly = [System.String]::Equals($lockState, 'ReadOnly', [System.StringComparison]::Ordinal)
    $isUnlocked = [System.String]::Equals($lockState, 'Unlock', [System.StringComparison]::Ordinal)
    $groupText = "$($Site.GroupId)".Trim()
    $groupId = ConvertTo-SPSLifecycleId -Value $Site.GroupId
    $zero = [System.Guid]::Empty
    $hasGroupId = $groupText -and -not ([System.Guid]::TryParse($groupText, [ref]$zero) -and $zero -eq [System.Guid]::Empty)

    if ($action -eq 'LOCK' -and -not $isUnlocked) {
        throw "The lock state of the site is '$(ConvertTo-SPSLifecycleVisibleText -Text $lockState)': only an unlocked site is locked."
    }

    if ($action -ne 'LOCK' -and $action -ne 'DELETE-VIA-GROUP' -and -not ($isReadOnly -or $isUnlocked)) {
        throw "The lock state of the site is '$(ConvertTo-SPSLifecycleVisibleText -Text $lockState)', not ReadOnly or Unlock: the tool changes only a site that is in one of the two."
    }

    if ($action -eq 'DELETE-SITE' -and $hasGroupId) {
        throw 'The site has a group (or a group ID that is not a GUID), so deleting the site alone would leave the group behind: the tool deletes it through its group.'
    }

    if ($action -eq 'DELETE-VIA-GROUP' -and -not $groupId) {
        throw "The site has no group (its group ID is '$(ConvertTo-SPSLifecycleVisibleText -Text $groupText)'): there is no group to delete."
    }

    $account = "$Account".Trim()
    $unlockBeforeArchive = $Setting.Act.UnlockBeforeArchive -eq $true
    $grantSiteAdmin = $Setting.Act.GrantSiteAdmin -eq $true
    if ($action -eq 'ARCHIVE' -and $grantSiteAdmin -and -not $account) {
        throw 'GrantSiteAdmin is on, but the account that signed in is not known, so it cannot be added to the administrators of the site collection: nothing was changed.'
    }

    # The lock of a site that this function unlocked: put back when what follows fails, and said so in the message.
    $relock = {
        param([System.String]$Failure)

        try {
            Set-SPSLifecycleSiteLockState -Session $Session -Url $url -State ReadOnly
            "$Failure The site was locked again."
        }
        catch {
            "$Failure The site could not be locked again: $($_.Exception.Message.Trim().TrimEnd('.')). Lock it by hand."
        }
    }
    $unlock = {
        Set-SPSLifecycleSiteLockState -Session $Session -Url $url -State Unlock
    }
    $waitForUnlock = {
        if (-not (Wait-SPSLifecycleLockState -Session $Session -Url $url -State Unlock)) {
            throw 'The site did not report Unlock within 2 minutes.'
        }
    }

    switch ($action) {
        'LOCK' {
            Set-SPSLifecycleSiteLockState -Session $Session -Url $url -State ReadOnly
            if (-not (Wait-SPSLifecycleLockState -Session $Session -Url $url -State ReadOnly)) {
                throw 'The site did not report ReadOnly within 2 minutes. The lock request was sent and may still be applied: check the site, and add its date to a lock date list if it is read-only.'
            }

            try {
                $null = Add-SPSLifecycleLockJournalEntry -Path $Setting.LockJournal -Url $url -SiteId $siteId -LockedOn $Now -Delimiter $Setting.CsvDelimiterChar
            }
            catch {
                throw "The site is locked now, but its date is not in the lock journal: $($_.Exception.Message.Trim().TrimEnd('.')). Add it to a lock date list by hand: a locked site without a date is never deleted."
            }

            'The site is read-only now, and its date is in the lock journal.'
        }

        'DELETE-SITE' {
            $unlocked = $false
            try {
                if ($isReadOnly) {
                    & $unlock
                    $unlocked = $true
                    & $waitForUnlock
                }

                Remove-SPSLifecycleSite -Session $Session -Url $url
            }
            catch {
                $message = $_.Exception.Message.Trim()
                if ($unlocked) {
                    throw (& $relock $message)
                }

                throw
            }

            'The site was deleted: it is in the recycle bin of the deleted sites.'
        }

        'DELETE-VIA-GROUP' {
            Remove-SPSLifecycleGroup -Session $Session -GroupId $groupId
            'The group was deleted: SharePoint deletes the site some time later (from minutes to hours).'
        }

        'ARCHIVE' {
            $unlocked = $false
            try {
                if ($unlockBeforeArchive -and $isReadOnly) {
                    & $unlock
                    $unlocked = $true
                    & $waitForUnlock
                }

                if ($grantSiteAdmin) {
                    Add-SPSLifecycleSiteAdmin -Session $Session -Url $url -Account $account
                }

                Request-SPSLifecycleSiteArchive -Session $Session -Url $url
            }
            catch {
                $message = $_.Exception.Message.Trim()
                if ($unlocked) {
                    throw (& $relock $message)
                }

                throw
            }

            if ($unlocked) {
                try {
                    Set-SPSLifecycleSiteLockState -Session $Session -Url $url -State ReadOnly
                }
                catch {
                    throw "The archive was requested, but the site could not be locked again: $($_.Exception.Message.Trim().TrimEnd('.')). Lock it by hand."
                }

                'The archive was requested: it takes place later. The site is locked again.'
            }
            else {
                'The archive was requested: it takes place later.'
            }
        }
    }
}
