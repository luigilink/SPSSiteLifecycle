function Import-SPSLifecycleActivityReport {
    <#
        .SYNOPSIS
        Reads a Microsoft 365 activity report (CSV) and indexes the last activity date of each site or group.

        .DESCRIPTION
        Three reports are supported, each one a CSV file downloaded from the Microsoft 365 admin
        center (Reports > Usage) or from Microsoft Graph:

        - SharePoint: the SharePoint site usage report. Rows are indexed by Site Id and by Site URL.
        - Teams: the Teams activity report (teams). Rows are indexed by Team Id, which is the ID of the
          Microsoft 365 group behind the team.
        - Groups: the Microsoft 365 groups activity report. Rows are indexed by Group Id.

        A row of a deleted site or group is ignored (the Is Deleted column is read as true or false in
        the words of a spreadsheet in another language too, and any other value stops the tool, see
        ConvertTo-SPSLifecycleBoolean). When an ID appears twice, the latest date wins.
        A row without a date stays in the index with no date: the site or group is known to the
        report but had no activity in its period.

        The names of the SharePoint report can be concealed by a tenant setting (Site URL empty and
        Site Id all zeros). When the Site URL is empty but the Site Id is filled, the rows are
        matched by Site Id. When both are empty, the function stops and says how to fix it.

        Returns an object with Kind, Name, RowCount, DeletedRowCount, ReportPeriod, RefreshDate,
        ById and ByUrl (hashtables from the key to the last activity date, or $null), and ByUrlId.

        ByUrlId is for the SharePoint report. It gives, for each address, the ID of the site of its row (a lowercase
        GUID), an empty text when the row has no usable site ID, and a star when rows with different site IDs share
        the address. A site that is looked up by its address can then be refused the row of another site: an address
        that a new site reuses must not inherit the activity of the site that had it (see Find-SPSLifecycleActivity).

        .PARAMETER Path
        Path of the CSV file.

        .PARAMETER Kind
        SharePoint, Teams or Groups.

        .PARAMETER DateFormat
        Extra date formats from the CsvDateFormats setting.

        .EXAMPLE
        Import-SPSLifecycleActivityReport -Path .\SharePointSiteUsageDetail.csv -Kind SharePoint
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('SharePoint', 'Teams', 'Groups')]
        [System.String]
        $Kind,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $DateFormat = @()
    )

    $name = Split-Path -Path $Path -Leaf
    $idColumn = switch ($Kind) {
        'SharePoint' { 'Site Id' }
        'Teams' { 'Team Id' }
        'Groups' { 'Group Id' }
    }

    $required = @($idColumn, 'Last Activity Date')
    if ($Kind -eq 'SharePoint') {
        $required += 'Site URL'
    }

    $rows = @(Read-SPSLifecycleCsv -Path $Path -RequiredColumn $required -OptionalColumn 'Is Deleted', 'Report Period', 'Report Refresh Date')
    if ($rows.Count -eq 0) {
        throw "The $Kind report '$name' has no row. Download the report again from the Microsoft 365 admin center (Reports > Usage)."
    }

    if ($Kind -eq 'SharePoint') {
        $urlCells = @($rows | ForEach-Object { "$($_.'Site URL')".Trim() } | Where-Object { $_ })
        $idCells = @($rows | ForEach-Object { ConvertTo-SPSLifecycleId -Value $_.'Site Id' } | Where-Object { $_ })
        if ($urlCells.Count -eq 0 -and $idCells.Count -eq 0) {
            throw "The report '$name' shows neither the site URLs nor the site IDs: the names are concealed. A Global Administrator can turn this off in the Microsoft 365 admin center (Settings > Org settings > Services > Reports: clear 'Display concealed user, group, and site names in all reports'), then download the report again."
        }

        if ($urlCells.Count -gt 0) {
            Test-SPSLifecycleColumnPattern -Value $urlCells -Pattern '^https?://' -What "'Site URL' in $name" -Hint 'Is this the SharePoint site usage report?'
        }
    }
    else {
        $idCells = @($rows | ForEach-Object { ConvertTo-SPSLifecycleId -Value $_.$idColumn } | Where-Object { $_ })
        if ($idCells.Count -eq 0) {
            throw "'$idColumn' is empty or not a GUID on every row of '$name'. Is this the $Kind activity report, and are the names concealed (see the SharePoint report help)?"
        }
    }

    $byId = @{}
    $byUrl = @{}
    $byUrlId = @{}
    $dateCache = @{}
    $flagCache = @{}
    $deleted = 0
    $hasDeletedColumn = Test-SPSLifecycleColumnName -Name $rows[0].PSObject.Properties.Name -Column 'Is Deleted'

    foreach ($row in $rows) {
        if ($hasDeletedColumn) {
            $flag = "$($row.'Is Deleted')".Trim()
            if ($flag) {
                if (-not $flagCache.ContainsKey($flag)) {
                    try {
                        $flagCache[$flag] = ConvertTo-SPSLifecycleBoolean -Text $flag
                    }
                    catch {
                        throw "File '$name', column 'Is Deleted': $($_.Exception.Message)"
                    }
                }

                if ($flagCache[$flag]) {
                    $deleted++
                    continue
                }
            }
        }

        $text = "$($row.'Last Activity Date')".Trim()
        $date = $null
        if ($text) {
            if (-not $dateCache.ContainsKey($text)) {
                try {
                    $dateCache[$text] = ConvertTo-SPSLifecycleDate -Text $text -DateFormat $DateFormat
                }
                catch {
                    throw "File '$name', column 'Last Activity Date': $($_.Exception.Message)"
                }
            }

            $date = $dateCache[$text]
        }

        $id = ConvertTo-SPSLifecycleId -Value $row.$idColumn
        if ($id) {
            if (-not $byId.ContainsKey($id) -or ($date -and (-not $byId[$id] -or $date -gt $byId[$id]))) {
                $byId[$id] = $date
            }
        }

        if ($Kind -eq 'SharePoint') {
            $key = ConvertTo-SPSLifecycleUrlKey -Url $row.'Site URL'
            if ($key) {
                if (-not $byUrlId.ContainsKey($key)) {
                    $byUrlId[$key] = $id
                }
                elseif ($byUrlId[$key] -cne $id) {
                    $byUrlId[$key] = '*'
                }
            }

            if ($key -and (-not $byUrl.ContainsKey($key) -or ($date -and (-not $byUrl[$key] -or $date -gt $byUrl[$key])))) {
                $byUrl[$key] = $date
            }
        }
    }

    $period = "$($rows[0].'Report Period')".Trim()
    $refresh = $null
    if ("$($rows[0].'Report Refresh Date')".Trim()) {
        try {
            $refresh = ConvertTo-SPSLifecycleDate -Text $rows[0].'Report Refresh Date' -DateFormat $DateFormat
        }
        catch {
            Write-Verbose -Message "The refresh date of '$name' could not be read: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        Kind            = $Kind
        Name            = $name
        RowCount        = $rows.Count
        DeletedRowCount = $deleted
        ReportPeriod    = $period
        RefreshDate     = $refresh
        ById            = $byId
        ByUrl           = $byUrl
        ByUrlId         = $byUrlId
    }
}
