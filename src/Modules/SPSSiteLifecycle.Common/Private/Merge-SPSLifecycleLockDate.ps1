function Merge-SPSLifecycleLockDate {
    <#
        .SYNOPSIS
        Merges the lock dates of every source (lists and journal) into one index.

        .DESCRIPTION
        The lock date of a site decides whether it can be deleted or archived: a site with no known
        lock date is never touched, and neither is a site locked less than MinLockedDays ago.

        When a site appears in several sources, the latest date wins, because a later date can only delay a
        deletion. On equal dates the first source wins, so the order of the sources decides which file is named.
        An entry that has a site ID is that site and is matched by the ID, whatever its address (a renamed site
        keeps its date). An entry that has none is matched by the canonical form of its URL. Find-SPSLifecycleLockDate
        reads the index.

        The entries come from Import-SPSLifecycleLockDateList and Import-SPSLifecycleLockJournal, which
        normalize the site ID and the URL.

        Returns an object with Sources (the name, the rows and the entries of each source), EntryCount,
        ById, and ByUrl (the entries that have no site ID).

        .PARAMETER Import
        The objects that the importers return (Name, RowCount, Entries), in the order of priority.

        .EXAMPLE
        Merge-SPSLifecycleLockDate -Import $lists, $journal
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Management.Automation.PSObject[]]
        $Import
    )

    $byId = @{}
    $byUrl = @{}
    $sources = [System.Collections.Generic.List[System.Object]]::new()

    foreach ($source in $Import) {
        if ($null -eq $source.PSObject.Properties['Entries']) {
            throw 'Merge-SPSLifecycleLockDate takes what the importers return: an object with Name, RowCount and Entries.'
        }

        $entries = @($source.Entries)
        $sources.Add([PSCustomObject]@{
                Name       = $source.Name
                RowCount   = $source.RowCount
                EntryCount = $entries.Count
            })

        foreach ($entry in $entries) {
            $siteId = "$($entry.SiteId)"
            $urlKey = "$($entry.UrlKey)"
            if (-not $urlKey -and $entry.Url) {
                $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $entry.Url
            }

            if ($siteId) {
                if (-not $byId.ContainsKey($siteId) -or $entry.LockedOn -gt $byId[$siteId].LockedOn) {
                    $byId[$siteId] = $entry
                }
            }
            elseif ($urlKey) {
                if (-not $byUrl.ContainsKey($urlKey) -or $entry.LockedOn -gt $byUrl[$urlKey].LockedOn) {
                    $byUrl[$urlKey] = $entry
                }
            }
        }
    }

    [PSCustomObject]@{
        Sources    = $sources.ToArray()
        EntryCount = $byId.Count + $byUrl.Count
        ById       = $byId
        ByUrl      = $byUrl
    }
}
