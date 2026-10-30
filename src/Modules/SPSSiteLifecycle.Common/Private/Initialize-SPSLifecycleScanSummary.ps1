function Initialize-SPSLifecycleScanSummary {
    <#
        .SYNOPSIS
        Gives the empty summary that the Scan core counts into.

        .DESCRIPTION
        The Scan core (ConvertTo-SPSLifecycleScanRow) sends its rows down the pipeline, so that a report of 260,000 sites
        needs no more memory than one of 100, and it counts what it does into this object, which the caller reads when
        the pipeline is done. A summary belongs to one run: each call gives a new one.

        The object has:

        - SitesRead: the site records that the listing gave.
        - SitesListed: the rows that were written, one per site.
        - LeftOutOneDrive: the OneDrive sites, and the sites whose address is not in the form that SharePoint gives
          (see Test-SPSLifecycleOneDrive), which are never listed (D12).
        - LeftOutLockState: the sites whose lock state is not one that the Scan lists (the Scan.LockStates setting).
        - ByVerdict: the number of rows for each verdict.
        - ByAction: the number of rows for each suggested action (Delete, Archive, Lock, or None when the verdict is
          not an action).

        SitesRead is the sum of the three others: SitesListed, LeftOutOneDrive and LeftOutLockState.

        .EXAMPLE
        $summary = Initialize-SPSLifecycleScanSummary
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param ()

    [PSCustomObject]@{
        SitesRead        = 0
        SitesListed      = 0
        LeftOutOneDrive  = 0
        LeftOutLockState = 0
        ByVerdict        = @{}
        ByAction         = @{}
    }
}
