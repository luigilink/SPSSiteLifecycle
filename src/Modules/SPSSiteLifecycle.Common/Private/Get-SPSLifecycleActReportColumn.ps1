function Get-SPSLifecycleActReportColumn {
    <#
        .SYNOPSIS
        Returns the columns of the Act report, in the order they are written.

        .DESCRIPTION
        The Act report is the record of an Act run: one row for each row of the reviewed report that has a decision, in the order of
        the file, in report-only mode too. It is written as the run goes, one row at a time, so that a run that stops half-way (an
        error, Ctrl+C, a machine that goes down) leaves the record of what was done. This table is the single source of truth for
        its columns. Each row has Name, Kind (see ConvertTo-SPSLifecycleReportCell) and Description.

        The outcome of a row is one of: Done (the action was done), Failed (it was tried, and failed: the detail says why and what
        became of the lock), WouldDo (report only: the verdict is an action), Skipped (a SKIP- verdict: nothing to do), Review (a
        REVIEW- verdict: a person has to look), ReadError (the site or its group could not be read: no verdict), and NotRun (the run
        stopped, or reached MaxActions, before the row).

        .EXAMPLE
        Get-SPSLifecycleActReportColumn | ForEach-Object { $_.Name }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    $rows = @(
        , @('Line', 'WholeNumber', 'The line of the row in the reviewed report, which a person finds in a spreadsheet.')
        , @('Url', 'Text', 'The address of the site.')
        , @('SiteId', 'Guid', 'The ID of the site in the reviewed report.')
        , @('Decision', 'Text', 'What the person decided: Delete, Archive or Lock.')
        , @('Verdict', 'Text', 'What the tool concluded from the live state of the site (see the Verdicts page). Empty when the site could not be read.')
        , @('Outcome', 'Text', 'What became of the row: Done, Failed, WouldDo, Skipped, Review, ReadError or NotRun.')
        , @('Detail', 'Text', 'What was done, why it was not, or what failed and what became of the lock of the site.')
        , @('ProcessedOn', 'Run', 'The time of the row, in UTC, in the compact form 20261030T090507Z.')
    )

    foreach ($row in $rows) {
        [PSCustomObject]@{
            Name        = $row[0]
            Kind        = $row[1]
            Description = $row[2]
        }
    }
}
