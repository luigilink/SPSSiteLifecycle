function Format-SPSLifecycleActSummary {
    <#
        .SYNOPSIS
        Writes the summary of an Act run as the few lines that the person who ran it reads.

        .DESCRIPTION
        The lines say how the run went: the time and whether the tenant was changed, how many rows have a decision and what became of
        them (Done, Failed, WouldDo, Skipped, Review, ReadError, NotRun), why the run stopped when it did, and where the report is.
        The numbers are written the same way whatever the culture of the machine. The lines hold no address of a site: the report does.

        .PARAMETER Summary
        The summary of the run, as Invoke-SPSLifecycleAct gives it: TenantName, Mode, ElapsedSeconds, Counts, StoppedBecause and
        ReportPath.

        .EXAMPLE
        Format-SPSLifecycleActSummary -Summary $summary
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Summary
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $time = ConvertTo-SPSLifecycleDurationText -Seconds ([System.Double]$Summary.ElapsedSeconds)
    $changed = if ($Summary.Mode -eq 'Execute') { 'EXECUTE: the tenant was changed.' } else { 'REPORT ONLY: nothing was changed.' }

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add("Act of the tenant $($Summary.TenantName) ended in $time. $changed")

    $total = [System.Int64]0
    $parts = foreach ($name in 'Done', 'Failed', 'WouldDo', 'Skipped', 'Review', 'ReadError', 'NotRun') {
        $count = [System.Int64]$Summary.Counts[$name]
        $total += $count
        '{0} {1}' -f $name, $count.ToString('N0', $culture)
    }
    $lines.Add(('Rows with a decision: {0}. {1}.' -f $total.ToString('N0', $culture), ($parts -join ', ')))

    if ($Summary.StoppedBecause -eq 'ConsecutiveErrors') {
        $lines.Add('The run stopped after 3 errors in a row: the rows that follow were not read.')
    }

    $lines.Add("Report: $($Summary.ReportPath)")
    $lines.ToArray()
}
