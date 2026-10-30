function Initialize-SPSLifecycleListingSummary {
    <#
        .SYNOPSIS
        Gives the empty summary that the listing of the tenant counts and times into.

        .DESCRIPTION
        The listing (Invoke-SPSLifecycleSiteListing) sends its records down the pipeline, and it writes what it did
        into this object, which the caller reads when the pipeline is done. It records the timings so that the
        extrapolation of D7 (about 2.4 s a page of 1,500 sites, 7 minutes for 259,000 sites) can be checked on a
        large tenant. A summary belongs to one run: each call gives a new one.

        The object has:

        - Source: how the sites were listed, Csom (the paged call of the admin API) or Cmdlet (Get-PnPTenantSite, the
          fallback), and FallbackReason, why the fallback was used.
        - Filter: the filter that the server applied, empty when there was none.
        - PersonalSites: what the call was asked about the OneDrive sites (D12), Excluded when the server was asked to
          leave them out.
        - StartedOn, FinishedOn (UTC) and ElapsedSeconds.
        - Resumed: whether the run took up a checkpoint, and StartReason, why it did not when one was there.
        - PagesFromCheckpoint and SitesFromCheckpoint: what was taken from the checkpoint.
        - PagesRead and SitesRead: what the tenant gave in this run, SitesRead before the sites that are dropped.
        - OneDriveDropped: the OneDrive sites that the call returned although it was asked not to (D12), counted and
          dropped, and DuplicatesDropped: the sites that came twice.
        - SitesReturned: the records given to the Scan, from the checkpoint and from the tenant.
        - Retries: the pages that had to be asked again.
        - PageSecondsTotal and PageSecondsMax: the time that the pages took in this run.

        .EXAMPLE
        $summary = Initialize-SPSLifecycleListingSummary
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param ()

    [PSCustomObject][ordered]@{
        Source              = ''
        FallbackReason      = ''
        Filter              = ''
        PersonalSites       = ''
        StartedOn           = $null
        FinishedOn          = $null
        ElapsedSeconds      = 0.0
        Resumed             = $false
        StartReason         = ''
        PagesFromCheckpoint = 0
        SitesFromCheckpoint = 0
        PagesRead           = 0
        SitesRead           = 0
        OneDriveDropped     = 0
        DuplicatesDropped   = 0
        SitesReturned       = 0
        Retries             = 0
        PageSecondsTotal    = 0.0
        PageSecondsMax      = 0.0
    }
}
