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

        Returns an object with the file name, the number of rows and the entries (Url, UrlKey,
        SiteId, LockedOn, Source).

        .PARAMETER Path
        Path of the CSV file.

        .PARAMETER DateFormat
        Extra date formats from the CsvDateFormats setting.

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
        $DateFormat = @()
    )

    $name = Split-Path -Path $Path -Leaf
    $rows = @(Read-SPSLifecycleCsv -Path $Path -RequiredColumn 'Url', 'LockedOn')
    $hasSiteId = $rows.Count -gt 0 -and @($rows[0].PSObject.Properties.Name) -contains 'SiteId'

    if ($rows.Count -gt 0) {
        Test-SPSLifecycleColumnPattern -Value $rows.Url -Pattern '^https?://' -What "'Url' in $name" -Hint 'The first column must hold the site URLs.'
    }

    $latest = @{}
    $dateCache = @{}
    foreach ($row in $rows) {
        $url = "$($row.Url)".Trim()
        $siteId = if ($hasSiteId) { ConvertTo-SPSLifecycleId -Value $row.SiteId } else { '' }
        if (-not $url -and -not $siteId) {
            continue
        }

        $text = "$($row.LockedOn)".Trim()
        if (-not $text) {
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
