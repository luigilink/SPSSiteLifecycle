function Get-SPSLifecycleSiteChange {
    <#
        .SYNOPSIS
        Says what changed in a site between two reads, when it matters to an action that is about to be done.

        .DESCRIPTION
        A read-only site is unlocked before it is deleted or archived, and it stays unlocked for as long as the lock takes to come off
        (up to 2 minutes): the verdict was given before, and people can write in the site meanwhile. So the site is read again after the
        unlock, and nothing may have changed since the verdict. This function compares the two reads and gives the first difference in
        words, or an empty text when there is none:

        - the site ID (the address may now belong to another site), the address, the template, the group (a group ID that is empty or all
          zeros is no group, and one that is neither that nor a GUID is an error, never "no group"), the hub flag and the channel flag, and
          the archive status;
        - the hold: only a flag that says False lets the action go on, as for the verdict (an unread safeguard is not a green light);
        - the content: its date must not be later than before, and must be readable;
        - with CheckSize (a deletion), the size must be known and not above DeleteMaxSizeGB.

        The lock state is not compared: it is what the unlock changed.

        .PARAMETER Before
        The live record that the verdict was given from (see Get-SPSLifecycleLiveSite).

        .PARAMETER After
        The live record that was read after the unlock.

        .PARAMETER CheckSize
        Checks the size too: for a deletion.

        .PARAMETER DeleteMaxSizeGB
        The size above which a site is never deleted, in GB.

        .EXAMPLE
        Get-SPSLifecycleSiteChange -Before $site -After $after -CheckSize -DeleteMaxSizeGB 1
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Before,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $After,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $CheckSize,

        [Parameter()]
        [System.Double]
        $DeleteMaxSizeGB = 0
    )

    $same = {
        param($First, $Second)
        [System.String]::Equals("$First", "$Second", [System.StringComparison]::Ordinal)
    }

    $beforeId = ConvertTo-SPSLifecycleId -Value $Before.SiteId
    $afterId = ConvertTo-SPSLifecycleId -Value $After.SiteId
    if (-not $beforeId -or -not (& $same $beforeId $afterId)) {
        return 'its site ID is not the one that was read: the address belongs to another site now'
    }

    if ((ConvertTo-SPSLifecycleUrlKey -Url $Before.Url) -ne (ConvertTo-SPSLifecycleUrlKey -Url $After.Url)) {
        return 'its address is not the same'
    }

    if (-not (& $same $Before.Template $After.Template)) {
        return 'its template is not the same'
    }

    # A group ID that is empty or all zeros is "no group", and any other text that is not a GUID is not: it is not read as "no group" either.
    $groupKey = {
        param($Value)
        $text = "$Value".Trim()
        if (-not $text) {
            return ''
        }

        $guid = [System.Guid]::Empty
        if (-not [System.Guid]::TryParse($text, [ref]$guid)) {
            return $null
        }

        if ($guid -eq [System.Guid]::Empty) { '' } else { $guid.ToString() }
    }
    $beforeGroup = & $groupKey $Before.GroupId
    $afterGroup = & $groupKey $After.GroupId
    if ($null -eq $afterGroup -or $null -eq $beforeGroup) {
        return 'its group ID is not a GUID'
    }

    if (-not (& $same $beforeGroup $afterGroup)) {
        return 'its group is not the same'
    }

    if ($After.IsHubSite -isnot [System.Boolean] -or $After.IsHubSite -ne $Before.IsHubSite) {
        return 'its hub site flag is not the same'
    }

    if ($After.IsTeamsChannelConnected -isnot [System.Boolean] -or $After.IsTeamsChannelConnected -ne $Before.IsTeamsChannelConnected) {
        return 'its channel site flag is not the same'
    }

    if (-not (& $same $Before.ArchiveStatus $After.ArchiveStatus)) {
        return 'its archive status is not the same'
    }

    if ($After.HasHolds -isnot [System.Boolean] -or $After.HasHolds) {
        return 'the tenant reports a hold on it, or does not report the flag'
    }

    if ($null -eq $After.LastContentModified) {
        return 'the date of its content cannot be read'
    }

    if ($null -ne $Before.LastContentModified -and (ConvertTo-SPSLifecycleUtcDateTime -Value $After.LastContentModified) -gt (ConvertTo-SPSLifecycleUtcDateTime -Value $Before.LastContentModified)) {
        return 'its content changed'
    }

    if ($CheckSize) {
        $size = $After.StorageUsedMB
        if ($null -eq $size -or $size -isnot [System.ValueType] -or $size -lt 0) {
            return 'its size is unknown'
        }

        if (([System.Double]$size / 1024) -gt $DeleteMaxSizeGB) {
            return 'its size is above DeleteMaxSizeGB'
        }
    }

    ''
}
