function Format-SPSLifecycleScanSummary {
    <#
        .SYNOPSIS
        Writes the summary of a Scan run as the few lines that the person who ran it reads.

        .DESCRIPTION
        The lines say how the run went: the time, how the sites were listed (and whether an interrupted listing was taken
        up), how many sites are in the report and how many were left out, what the report suggests, the verdicts by their
        count, where the report is, and what comes next. The numbers are written the same way whatever the culture of the
        machine (1,223), and the verdicts are sorted by their count and then by their name, so that two runs on the same
        tenant read the same. The lines hold no address of a site and no title: the report does, and nothing else.

        .PARAMETER Summary
        The summary of the run, as Invoke-SPSLifecycleScan gives it: TenantName, ElapsedSeconds, ReportPath, Scan (see
        Initialize-SPSLifecycleScanSummary) and Listing (see Initialize-SPSLifecycleListingSummary).

        .EXAMPLE
        Format-SPSLifecycleScanSummary -Summary $summary
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
    $listing = $Summary.Listing
    $scan = $Summary.Scan

    $number = {
        param([System.Int64]$Value)
        $Value.ToString('N0', $culture)
    }
    $plural = {
        param([System.Int64]$Count, [System.String]$One, [System.String]$Many)
        '{0} {1}' -f $Count.ToString('N0', $culture), $(if ($Count -eq 1) { $One } else { $Many })
    }

    $seconds = [System.Math]::Max(0.0, [System.Double]$Summary.ElapsedSeconds)
    if ($seconds -lt 60) {
        $time = '{0} s' -f ([System.Math]::Floor($seconds * 10) / 10).ToString('N1', $culture)
    }
    else {
        $whole = [System.Int64][System.Math]::Floor($seconds)
        $hours = [System.Int64][System.Math]::Floor($whole / 3600)
        $minutes = [System.Int64][System.Math]::Floor(($whole % 3600) / 60)
        $rest = $whole % 60
        $time = if ($hours -gt 0) { "$hours h $minutes min $rest s" } else { "$minutes min $rest s" }
    }

    $source = switch ($listing.Source) {
        'Csom' { 'the paged call of the SharePoint admin API' }
        default {
            $reason = "$($listing.FallbackReason)".Trim().TrimEnd('.')
            if ($reason) { "Get-PnPTenantSite (the paged call cannot be used: $reason)" } else { 'Get-PnPTenantSite (as it was asked)' }
        }
    }

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add("Scan of the tenant $($Summary.TenantName) ended in $time. It only reads: nothing was changed in the tenant.")
    $lines.Add(('Listing: {0}; {1} and {2} read from the tenant; left out by the listing: {3}, {4}; {5}.' -f
            $source,
            (& $plural $listing.PagesRead 'page' 'pages'),
            (& $plural $listing.SitesRead 'site' 'sites'),
            (& $plural $listing.OneDriveDropped 'OneDrive site' 'OneDrive sites'),
            (& $plural $listing.DuplicatesDropped 'site that came twice' 'sites that came twice'),
            (& $plural $listing.Retries 'page asked again' 'pages asked again')))

    if ($listing.Resumed) {
        $lines.Add(('Checkpoint: an interrupted listing was taken up: {0} ({1}) came from its checkpoint.' -f
                (& $plural $listing.PagesFromCheckpoint 'page' 'pages'),
                (& $plural $listing.SitesFromCheckpoint 'site' 'sites')))
    }
    elseif ($listing.StartReason) {
        $lines.Add("Checkpoint: not taken up: $($listing.StartReason)")
    }

    $lines.Add(('Sites in the report: {0}. Left out by the Scan: {1} for a OneDrive address or an address that SharePoint does not give, {2} for a lock state that the settings do not list.' -f
            (& $number $scan.SitesListed), (& $number $scan.LeftOutOneDrive), (& $number $scan.LeftOutLockState)))
    $lines.Add(('Suggested actions: Delete {0}, Archive {1}, Lock {2}, nothing {3}.' -f
            (& $number ([System.Int64]$scan.ByAction['Delete'])), (& $number ([System.Int64]$scan.ByAction['Archive'])),
            (& $number ([System.Int64]$scan.ByAction['Lock'])), (& $number ([System.Int64]$scan.ByAction['None']))))

    $verdicts = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($entry in $scan.ByVerdict.GetEnumerator()) {
        $verdicts.Add([PSCustomObject]@{ Name = [System.String]$entry.Key; Count = [System.Int64]$entry.Value })
    }

    $verdicts.Sort([System.Comparison[System.Object]] {
            param($a, $b)
            if ($a.Count -ne $b.Count) {
                return $b.Count.CompareTo($a.Count)
            }

            [System.String]::CompareOrdinal($a.Name, $b.Name)
        })
    $lines.Add($(if ($verdicts.Count -eq 0) { 'Verdicts: none.' } else { 'Verdicts: ' + (($verdicts | ForEach-Object { '{0} {1}' -f $_.Name, (& $number $_.Count) }) -join ', ') + '.' }))

    if ($scan.SitesListed -eq 0) {
        $lines.Add('The report holds no site: check Scan.LockStates and the lock states of the sites.')
    }

    $lines.Add("Report: $($Summary.ReportPath)")
    if ($scan.SitesListed -gt 0) {
        $lines.Add('Next: review the report. Decision is empty on every row: a person fills it in (Delete, Archive or Lock) before the Act phase reads the file.')
    }

    $lines.ToArray()
}
