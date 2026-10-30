function Get-SPSLifecycleListingGuard {
    <#
        .SYNOPSIS
        Gives, as one number, what a site is for the safeguards of the tool, to tell a site that came twice from two readings that disagree.

        .DESCRIPTION
        A tenant that is read page by page can give a site twice, when it changes while it is read. If the two readings hold the
        same here, the second is a duplicate and is dropped. If they do not, one of them is not what the site is, and keeping the
        first one would hide the other, which may be the one that protects the site (a hub site, a site of a Teams channel, a
        site that is not read-only any more, a site that was changed a minute ago). The fields that are compared are the ones that
        a safeguard or a verdict reads: the address, the template, the lock state, the group, the hub and Teams flags, the archive
        status, the size and the date of the last change. A size or a date that is not known is not zero and is not a date, and
        differs from every one that is known. The title is not compared: no verdict reads it, and it can change at any time.

        The listing keeps this for every site that it has read, for as long as it runs, so it is a 64-bit number (the first eight
        bytes of the SHA-256 of the fields) and not the text: 260,000 sites take about 61 MB with it, and 200 MB with the text. Two
        readings that disagree give the same number only once in 2^64. It is never written to the disk.

        .PARAMETER Site
        A site record (see ConvertTo-SPSLifecycleSiteRecord).

        .EXAMPLE
        Get-SPSLifecycleListingGuard -Site $record
    #>
    [CmdletBinding()]
    [OutputType([System.Int64])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Site
    )

    # A size is written as a number and a date as a count of ticks in UTC (a date with no kind is UTC, as in the record), without the
    # culture; a tilde is what is not known, which no number is. A value of another type than the record gives is written as its
    # text, so that the guard never stops on it and still tells it from the others (the Scan core says what is wrong with it).
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $size = '~'
    if ($null -ne $Site.StorageUsedMB) {
        $size = [System.Convert]::ToString($Site.StorageUsedMB, $invariant)
    }

    $ticks = '~'
    $date = $Site.LastContentModified
    if ($date -is [System.DateTime]) {
        $ticks = [System.Convert]::ToString($(if ($date.Kind -eq [System.DateTimeKind]::Local) { $date.ToUniversalTime().Ticks } else { $date.Ticks }), $invariant)
    }
    elseif ($null -ne $date) {
        $ticks = '?' + [System.Convert]::ToString($date, $invariant)
    }

    # A separator that no field holds: a line break is not in a web address, a template, a GUID, a status or a number.
    $text = [System.String]::Join("`n", @($Site.Url, $Site.Template, $Site.LockState, $Site.GroupId, $Site.IsHubSite, $Site.IsTeamsConnected, $Site.IsTeamsChannelConnected, $Site.ArchiveStatus, $size, $ticks))
    [System.BitConverter]::ToInt64([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text)), 0)
}
