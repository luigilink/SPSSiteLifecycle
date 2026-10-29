function Find-SPSLifecycleActivity {
    <#
        .SYNOPSIS
        Finds the last activity of a site in the activity reports that were given, and names the report that gave it.

        .DESCRIPTION
        The SharePoint site usage report is matched by the ID of the site. The address is a second way in, for a row
        that has no usable site ID (a report with concealed names). A row that has the ID of another site is never
        given to this one, even at the same address: that site reused the address of a site that is gone, and it must
        not inherit the activity of the old one (the same rule as for the lock dates). A row that rows with different
        IDs share is not given either, and neither is any row when the ID of the site is unknown, or when the report
        cannot say whose row an address is (ByUrlId). In all these cases the site is not found, which gives the verdict
        REVIEW-NO-ACTIVITY-ROW: nothing says that it is inactive.

        The Teams and the Microsoft 365 groups reports are matched by the ID of the group of the site. A site that has
        no group is not in them.

        The last activity is the most recent date over the reports that know the site. A report that knows the site and
        has no date for it (no activity in its period) counts as a row, and gives no date. When dates are equal, the
        first report of the order SharePoint, Teams, Groups is named. Each report gives its own date as well, for the
        columns of the Scan CSV.

        Returns an object with HasRow (the site is in at least one report), LastActivity (a date, or $null),
        LastActivitySource (SharePoint, Teams, Groups, or an empty text), SharePoint, Teams and Groups (the date of each
        report, or $null).

        .PARAMETER SharePoint
        The import of the SharePoint site usage report (Import-SPSLifecycleActivityReport), or $null when none was given.

        .PARAMETER Teams
        The import of the Teams activity report, or $null.

        .PARAMETER Groups
        The import of the Microsoft 365 groups activity report, or $null.

        .PARAMETER SiteId
        The ID of the site, as the tenant gives it now.

        .PARAMETER Url
        The address of the site.

        .PARAMETER GroupId
        The ID of the Microsoft 365 group of the site, empty when it has none.

        .EXAMPLE
        Find-SPSLifecycleActivity -SharePoint $usage -Teams $teams -SiteId $site.SiteId -Url $site.Url -GroupId $site.GroupId
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSObject]
        $SharePoint = $null,

        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSObject]
        $Teams = $null,

        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSObject]
        $Groups = $null,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $SiteId = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Url = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $GroupId = ''
    )

    $siteKey = ConvertTo-SPSLifecycleId -Value $SiteId
    $groupKey = ConvertTo-SPSLifecycleId -Value $GroupId

    $hasRow = $false
    $sharePointDate = $null
    $teamsDate = $null
    $groupsDate = $null

    if ($null -ne $SharePoint -and $siteKey) {
        if ($SharePoint.ById.ContainsKey($siteKey)) {
            $hasRow = $true
            $sharePointDate = $SharePoint.ById[$siteKey]
        }
        else {
            $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $Url
            $byUrlId = $SharePoint.ByUrlId
            if ($urlKey -and $null -ne $byUrlId -and $SharePoint.ByUrl.ContainsKey($urlKey) -and $byUrlId.ContainsKey($urlKey)) {
                if ($byUrlId[$urlKey] -ceq '') {
                    $hasRow = $true
                    $sharePointDate = $SharePoint.ByUrl[$urlKey]
                }
            }
        }
    }

    if ($null -ne $Teams -and $groupKey -and $Teams.ById.ContainsKey($groupKey)) {
        $hasRow = $true
        $teamsDate = $Teams.ById[$groupKey]
    }

    if ($null -ne $Groups -and $groupKey -and $Groups.ById.ContainsKey($groupKey)) {
        $hasRow = $true
        $groupsDate = $Groups.ById[$groupKey]
    }

    $last = $null
    $source = ''
    if ($sharePointDate) {
        $last = $sharePointDate
        $source = 'SharePoint'
    }

    if ($teamsDate -and (-not $last -or $teamsDate -gt $last)) {
        $last = $teamsDate
        $source = 'Teams'
    }

    if ($groupsDate -and (-not $last -or $groupsDate -gt $last)) {
        $last = $groupsDate
        $source = 'Groups'
    }

    [PSCustomObject]@{
        HasRow             = $hasRow
        LastActivity       = $last
        LastActivitySource = $source
        SharePoint         = $sharePointDate
        Teams              = $teamsDate
        Groups             = $groupsDate
    }
}
