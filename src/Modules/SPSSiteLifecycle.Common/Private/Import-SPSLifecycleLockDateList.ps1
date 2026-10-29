function Import-SPSLifecycleLockDateList {
    <#
        .SYNOPSIS
        Reads a list of sites with the date they were locked.

        .DESCRIPTION
        The file has a Url column, a LockedOn column and, optionally, a SiteId column. A row
        without a date is ignored (a site without a lock date is never deleted anyway).

        A row that has a site ID is that site, whatever its address, and a row that has none is
        known by its address only. When a site appears twice, the latest date is kept: a later lock
        date can only delay a deletion. Two site IDs that used the same address stay two entries,
        because the second site is not the first.

        A list is what a person provides, and a row that has no date says nothing about its site, so it is
        ignored. With Strict, which the lock journal is read with, nothing is ignored: the journal is the tool's
        own file, where every row is a lock that was recorded, so a row without a date, with a site ID that is not
        a GUID, or with neither an address nor a site ID could hide a lock that is more recent than the other rows
        of the site, and stops the tool. A quote that is never closed stops it too, and the SiteId column is
        required, because a journal that lost it would attribute its dates to addresses.

        The column SiteId is the one that the rows have: a header that only looks like it (a hidden character) is
        not SiteId, and without the check the identity of every row would be lost.

        Returns an object with the file name, the number of rows and the entries (Url, UrlKey,
        SiteId, LockedOn, Source).

        .PARAMETER Path
        Path of the CSV file.

        .PARAMETER DateFormat
        Extra date formats from the CsvDateFormats setting.

        .PARAMETER Strict
        Stops on a row that cannot be used, instead of ignoring it. Used for the lock journal.

        .EXAMPLE
        Import-SPSLifecycleLockDateList -Path .\lock-dates.csv -DateFormat 'dd/MM/yyyy'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $DateFormat = @(),

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Strict
    )

    $name = Split-Path -Path $Path -Leaf
    $required = if ($Strict) { @('Url', 'SiteId', 'LockedOn') } else { @('Url', 'LockedOn') }
    $rows = @(Read-SPSLifecycleCsv -Path $Path -RequiredColumn $required -RequireBalancedQuote:$Strict)
    $hasSiteId = $rows.Count -gt 0 -and (Test-SPSLifecycleColumnName -Name $rows[0].PSObject.Properties.Name -Column 'SiteId')

    if ($rows.Count -gt 0) {
        Test-SPSLifecycleColumnPattern -Value $rows.Url -Pattern '^https?://' -What "'Url' in $name" -Hint 'The first column must hold the site URLs.'
    }

    $latest = @{}
    $dateCache = @{}
    $rowNumber = 0
    foreach ($row in $rows) {
        $rowNumber++
        $url = "$($row.Url)".Trim()
        $givenId = if ($hasSiteId) { "$($row.SiteId)".Trim() } else { '' }
        $siteId = if ($givenId) { ConvertTo-SPSLifecycleId -Value $givenId } else { '' }
        $where = "File '$name', row $rowNumber (the rows that are empty are not counted)"

        if ($Strict -and $givenId -and -not $siteId) {
            throw "$where`: the site ID '$givenId' is not a GUID, or is all zeros. A row that loses its site ID would be matched by its address, and could be attributed to another site. Fix the row, or delete it."
        }

        if (-not $url -and -not $siteId) {
            if ($Strict) {
                throw "$where has neither an address nor a site ID: its date belongs to no site, and a lock could be hidden. Fix the row, or delete it."
            }

            continue
        }

        $text = "$($row.LockedOn)".Trim()
        if (-not $text) {
            if ($Strict) {
                $who = if ($siteId) { $siteId } else { $url }
                throw "$where ($who): no lock date. The lock journal is written by the tool, so a row without a date was cut short or cleared, and an older date of the same site could be used in its place. Fix the row, or delete it."
            }

            continue
        }

        if (-not $dateCache.ContainsKey($text)) {
            try {
                $dateCache[$text] = ConvertTo-SPSLifecycleDate -Text $text -DateFormat $DateFormat
            }
            catch {
                throw "File '$name', column 'LockedOn': $($_.Exception.Message)"
            }
        }

        $urlKey = if ($url) { ConvertTo-SPSLifecycleUrlKey -Url $url } else { '' }
        $key = if ($siteId) { "id:$siteId" } else { "url:$urlKey" }
        $date = $dateCache[$text]
        if (-not $latest.ContainsKey($key) -or $date -gt $latest[$key].LockedOn) {
            $latest[$key] = [PSCustomObject]@{
                Url      = $url
                UrlKey   = $urlKey
                SiteId   = $siteId
                LockedOn = $date
                Source   = $name
            }
        }
    }

    [PSCustomObject]@{
        Name     = $name
        RowCount = $rows.Count
        Entries  = @($latest.Values)
    }
}
