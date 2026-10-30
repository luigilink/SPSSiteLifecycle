function Invoke-SPSLifecycleScan {
    <#
        .SYNOPSIS
        Runs the Scan phase: reads the tenant, gives each site its verdict, and writes the CSV report that a person reviews.

        .DESCRIPTION
        The Scan only reads. It does, in this order:

        1. Reads the settings for the Scan (see Get-SPSLifecycleSetting), then the activity reports that they name, the lock date
           lists and the lock journal, and the exclusion lists. A setting or a file that is wrong stops the run here, before the
           sign-in window opens and before anything is written.
        2. Starts the report (the folder is created, a report of the same second is never replaced), which checks the settings
           again for the Scan core (ConvertTo-SPSLifecycleScanRow) before the sign-in too.
        3. Signs in, reads the home site, and lists the sites page by page (Get-SPSLifecycleTenantSite), resuming an
           interrupted listing from its checkpoint.
        4. Gives each site its verdict and writes its row as soon as it is made, so that a report of 260,000 sites needs no
           more memory than one of 100. A run that stops half-way leaves no report that looks complete.
        5. Writes the lines that say how it went (Write-Information), and returns the summary.

        The home site is protected: its address comes from the tenant (see Get-SPSLifecycleHomeSiteUrl), and the Scan core asks
        for it when the first site comes, once the listing has signed in.

        Returns the summary of the run: Phase, TenantName, StartedOn (UTC), ElapsedSeconds, ReportPath, ActivityReports (the
        kinds that were read), Scan (the counts of the sites and of the verdicts) and Listing (how the sites were listed).

        .PARAMETER ConfigFile
        The settings file (.psd1).

        .PARAMETER Now
        The time of the run, in UTC, which is the time of the report and of GeneratedOn on every row. Default: now.

        .EXAMPLE
        Invoke-SPSLifecycleScan -ConfigFile .\contoso.psd1 -InformationAction Continue
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ConfigFile,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $runTime = ConvertTo-SPSLifecycleUtcDateTime -Value $Now
    $setting = Get-SPSLifecycleSetting -Path $ConfigFile -Phase Scan

    $dateFormat = @($setting.CsvDateFormats)
    $reports = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($source in @(
            @{ Kind = 'SharePoint'; Path = $setting.Scan.SharePointUsageReport }
            @{ Kind = 'Teams'; Path = $setting.Scan.TeamsActivityReport }
            @{ Kind = 'Groups'; Path = $setting.Scan.GroupsActivityReport }
        )) {
        if ($source.Path) {
            $reports.Add((Import-SPSLifecycleActivityReport -Path $source.Path -Kind $source.Kind -DateFormat $dateFormat))
        }
    }

    $lockDateIndex = Get-SPSLifecycleLockDateIndex -LockDateFile @($setting.LockDateFiles) -LockJournal $setting.LockJournal -DateFormat $dateFormat
    $exclusionIndex = Get-SPSLifecycleExclusionIndex -ExclusionFile @($setting.ExclusionFiles)

    $listingSummary = Initialize-SPSLifecycleListingSummary
    $scanSummary = Initialize-SPSLifecycleScanSummary
    $homeSiteSource = { $listingSummary.HomeSiteUrl }.GetNewClosure()

    $reportPath = Get-SPSLifecycleTenantSite -Setting $setting -Summary $listingSummary -Now $runTime |
        ConvertTo-SPSLifecycleScanRow -Setting $setting -ActivityReport $reports.ToArray() -LockDateIndex $lockDateIndex -ExclusionIndex $exclusionIndex -Summary $scanSummary -Now $runTime -HomeSiteUrlSource $homeSiteSource |
        Export-SPSLifecycleReport -OutputFolder $setting.OutputFolder -Delimiter $setting.CsvDelimiterChar -GeneratedOn $runTime

    $summary = [PSCustomObject][ordered]@{
        Phase           = 'Scan'
        TenantName      = $setting.TenantName
        StartedOn       = $runTime
        ElapsedSeconds  = $clock.Elapsed.TotalSeconds
        ReportPath      = $reportPath
        ActivityReports = @($reports | ForEach-Object { $_.Kind })
        Scan            = $scanSummary
        Listing         = $listingSummary
    }

    foreach ($line in Format-SPSLifecycleScanSummary -Summary $summary) {
        Write-Information -MessageData $line
    }

    $summary
}
