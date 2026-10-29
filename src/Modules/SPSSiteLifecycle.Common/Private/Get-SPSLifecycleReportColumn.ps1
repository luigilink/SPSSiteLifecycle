function Get-SPSLifecycleReportColumn {
    <#
        .SYNOPSIS
        Returns the columns of the Scan report, in the order they are written.

        .DESCRIPTION
        This table is the single source of truth for the columns of the CSV file that the Scan phase
        writes, that a person reviews in a spreadsheet, and that the Act phase reads. The order, the
        kind of each column and the four columns that Act reads are decided in D10 of the design
        decisions.

        Each row has: Name, Kind, ReadByAct and Description. The kind says how a value is written
        (see ConvertTo-SPSLifecycleReportCell):

        - Text: a text that comes from the tenant, neutralized against formula injection.
        - Guid: a GUID, in lowercase.
        - Boolean: True or False.
        - WholeNumber: a whole number. A value that is unknown stays empty, it is never written as 0.
        - Date: a date in ISO 8601, in UTC.
        - Run: the time of the run, in the compact form that survives a spreadsheet (20261028T163000Z).
        - Blank: always empty. The tool writes nothing there, a person fills it in.

        There is no column for the owners of a site, because they are personal data.

        .EXAMPLE
        Get-SPSLifecycleReportColumn | Where-Object { $_.ReadByAct }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    $rows = @(
        , @('Url', 'Text', $true, 'The address of the site.')
        , @('Verdict', 'Text', $false, 'What the tool concluded: an action, a SKIP- or a REVIEW- verdict (see the Verdicts page).')
        , @('SuggestedAction', 'Text', $false, 'What the tool suggests: Delete, Archive or Lock. It only helps to filter and to fill in Decision.')
        , @('Decision', 'Blank', $true, 'Filled in by a person: Delete, Archive or Lock. Empty leaves the site untouched.')
        , @('SiteId', 'Guid', $true, 'The ID of the site. The Act phase checks that the address still belongs to this site.')
        , @('Title', 'Text', $false, 'The title of the site. Never read by the Act phase.')
        , @('Template', 'Text', $false, 'The template of the site, for example GROUP#0.')
        , @('GroupId', 'Guid', $false, 'The ID of the Microsoft 365 group of the site, empty when it has none.')
        , @('IsTeamsConnected', 'Boolean', $false, 'True when the site belongs to a team.')
        , @('LockState', 'Text', $false, 'The lock state: Unlock, ReadOnly or NoAccess.')
        , @('ArchiveStatus', 'Text', $false, 'The archive status of the site.')
        , @('StorageUsedMB', 'WholeNumber', $false, 'The storage in use, in whole megabytes.')
        , @('LastActivity', 'Date', $false, 'The most recent activity over the reports that were given.')
        , @('LastActivitySource', 'Text', $false, 'The report that gave LastActivity.')
        , @('InactiveDays', 'WholeNumber', $false, 'The days between LastActivity and the time of the run.')
        , @('SharePointActivity', 'Date', $false, 'The last activity in the SharePoint site usage report.')
        , @('TeamsActivity', 'Date', $false, 'The last activity in the Teams activity report.')
        , @('GroupActivity', 'Date', $false, 'The last activity in the Microsoft 365 groups activity report.')
        , @('ContentModified', 'Date', $false, 'The last modification of the content, as the tenant reports it.')
        , @('LockedOn', 'Date', $false, 'The date the site was locked, when it is known.')
        , @('LockedOnSource', 'Text', $false, 'Where LockedOn comes from: a lock date list or the lock journal.')
        , @('GeneratedOn', 'Run', $true, 'The time of the run, in UTC. The Act phase refuses a file that is too old.')
    )

    foreach ($row in $rows) {
        [PSCustomObject]@{
            Name        = $row[0]
            Kind        = $row[1]
            ReadByAct   = [System.Boolean]$row[2]
            Description = $row[3]
        }
    }
}
