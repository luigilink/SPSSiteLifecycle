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

        A list is what a person provides, and it is read by Read-SPSLifecycleCsv: a row that has no date says
        nothing about its site, so it is ignored, and the column SiteId is optional (a header that only looks like
        it, Site ID or a hidden character, stops the tool, because the identity of every row would be lost).

        A date before 2000-01-01 stops the tool, in a list and in the journal: SharePoint Online did not exist, so no
        site was locked then. It is what a spreadsheet writes for a blank cell (1900-01-01, 1899-12-30,
        1970-01-01, 0001-01-01), and a site whose date is read as a century old looks as if it had been locked for
        ever, and passes any delay of MinLockedDays: the error whose direction is dangerous. A date in the future
        only delays a deletion, so it is accepted.

        With Strict, which the lock journal is read with, nothing is ignored. The journal is the tool's own file,
        where every row is a lock that was recorded, and a row that is lost or dropped could leave an older date of
        the same site in force. The file is read by Read-SPSLifecycleStrictCsv (a text that breaks the CSV rules,
        a row that is cut short or that has a value too many, and a value under a column without a name stop the
        tool), the SiteId column is required, and every row is checked on its own: a row without a date, with a
        site ID that is not a GUID, with an address that is not a full web address, or with neither an address nor a
        site ID stops the tool and names its line. There is no threshold: a journal in which 90 % of the rows are
        good is not a good journal.

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
    if ($Strict) {
        $table = Read-SPSLifecycleStrictCsv -Path $Path -RequiredColumn 'Url', 'SiteId', 'LockedOn'
        $rows = @($table.Rows)
        $lines = @($table.Line)
        $hasSiteId = $true
    }
    else {
        $rows = @(Read-SPSLifecycleCsv -Path $Path -RequiredColumn 'Url', 'LockedOn' -OptionalColumn 'SiteId')
        $hasSiteId = $rows.Count -gt 0 -and (Test-SPSLifecycleColumnName -Name $rows[0].PSObject.Properties.Name -Column 'SiteId')
        if ($rows.Count -gt 0) {
            Test-SPSLifecycleColumnPattern -Value $rows.Url -Pattern '^https?://' -What "'Url' in $name" -Hint 'The first column must hold the site URLs.'
        }
    }

    $earliestLockDate = [System.DateTime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $latest = @{}
    $dateCache = @{}
    $rowNumber = 0
    foreach ($row in $rows) {
        $rowNumber++
        $url = "$($row.Url)".Trim()
        $givenId = if ($hasSiteId) { "$($row.SiteId)".Trim() } else { '' }
        $siteId = if ($givenId) { ConvertTo-SPSLifecycleId -Value $givenId } else { '' }
        $where = if ($Strict) { "File '$name', line $($lines[$rowNumber - 1])" } else { '' }

        if ($Strict) {
            if ($givenId -and -not $siteId) {
                throw "$where`: the site ID '$(ConvertTo-SPSLifecycleVisibleText -Text $givenId)' is not a GUID, or is all zeros. A row that loses its site ID would be matched by its address, and could be attributed to another site. Fix the row, or delete it."
            }

            if ($url -and -not (Test-SPSLifecycleWebAddress -Text $url)) {
                throw "$where`: '$(ConvertTo-SPSLifecycleVisibleText -Text $url)' is not a full web address (https://...). A row whose address cannot be used would be indexed under a key that no site has, and a lock could be hidden. Fix the row, or delete it."
            }
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
                $parsed = ConvertTo-SPSLifecycleDate -Text $text -DateFormat $DateFormat
                if ($parsed -lt $earliestLockDate) {
                    throw "the date '$(ConvertTo-SPSLifecycleVisibleText -Text $text)' is before 2000-01-01, so it is not the date of a lock (SharePoint Online did not exist). A spreadsheet writes a blank date as 1900-01-01, 1899-12-30 or 1970-01-01, and the site would look as if it had been locked for ever. Fix the date, or delete the row."
                }

                $dateCache[$text] = $parsed
            }
            catch {
                throw "File '$name', column 'LockedOn'$(if ($Strict) { ", line $($lines[$rowNumber - 1])" }): $($_.Exception.Message)"
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
