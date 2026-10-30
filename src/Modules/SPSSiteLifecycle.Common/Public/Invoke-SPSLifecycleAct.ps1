function Invoke-SPSLifecycleAct {
    <#
        .SYNOPSIS
        Runs the Act phase: reads the reviewed report, checks each row live, and deletes, archives or locks the sites that a person
        decided on, behind the safeguards of D6. It changes the tenant only when Act.Execute is $true and a person confirms it.

        .DESCRIPTION
        In this order:

        1. The settings for the Act phase, the lock dates (the lists and the journal) and the exclusion lists are read, and the reviewed
           report is read and checked as a whole (Import-SPSLifecycleReviewedReport): an unknown decision, a file that is too old, an
           address that is not one of the tenant, a OneDrive address, a refused tenant, a site that appears twice and a lock
           journal that is damaged stop the tool here, before the sign-in and before anything is asked or changed. A report with no
           decision is not an error: the tool says that there is nothing to do.
        2. The banner (see Format-SPSLifecycleActBanner): the mode, the file, its date and age, the decisions, the most that the run
           will do.
        3. With Execute, the confirmation (see Confirm-SPSLifecycleAct): the name of the tenant, then a phrase that carries the number
           of actions. Anything else stops the tool, and so does an input that is redirected.
        4. The Act report is created (see Initialize-SPSLifecycleActReport), then the tool signs in, reads the home site, and, when a row
           is to be archived, checks that Microsoft 365 Archive is on for sites (with Execute, it stops when it is off or when it cannot
           tell; in report-only mode it says so) and, with GrantSiteAdmin, reads the account that signed in.
        5. The loop (see Invoke-SPSLifecycleActLoop) reads each row again right before its action, does it or says what it would do,
           and writes its row in the report at once. It stops after 3 errors in a row, and does at most MaxActions actions.
        6. The summary is written as lines of information (see Format-SPSLifecycleActSummary), and returned.

        Report-only mode is the default: Act.Execute must be exactly $true to change the tenant, and without it no adapter that changes
        the tenant is called, and nothing is asked.

        Returns Phase, TenantName, Mode, StartedOn, ElapsedSeconds, InputFile, ReportPath, Plan, Counts (Done, Failed, WouldDo, Skipped,
        Review, ReadError, NotRun), ActionsAttempted, StoppedBecause (empty, or ConsecutiveErrors) and Warnings.

        .PARAMETER ConfigFile
        The settings file (.psd1).

        .PARAMETER Now
        The time of the run, in UTC, which is the time of the report and of the age of the reviewed report, and, when it is given, the
        time of every row. Default: now, and the time of each row is its own.

        .EXAMPLE
        Invoke-SPSLifecycleAct -ConfigFile .\contoso.psd1 -InformationAction Continue
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
    $setting = Get-SPSLifecycleSetting -Path $ConfigFile -Phase Act

    $dateFormat = @($setting.CsvDateFormats)
    $lockDateIndex = Get-SPSLifecycleLockDateIndex -LockDateFile @($setting.LockDateFiles) -LockJournal $setting.LockJournal -DateFormat $dateFormat
    $exclusionIndex = Get-SPSLifecycleExclusionIndex -ExclusionFile @($setting.ExclusionFiles)
    $import = Import-SPSLifecycleReviewedReport -Setting $setting -Now $runTime

    $counts = [ordered]@{ Done = 0; Failed = 0; WouldDo = 0; Skipped = 0; Review = 0; ReadError = 0; NotRun = 0 }
    $warnings = [System.Collections.Generic.List[System.String]]::new()
    $summary = [PSCustomObject][ordered]@{
        Phase            = 'Act'
        TenantName       = $setting.TenantName
        Mode             = if ($setting.Act.Execute -is [System.Boolean] -and $setting.Act.Execute) { 'Execute' } else { 'ReportOnly' }
        StartedOn        = $runTime
        ElapsedSeconds   = 0.0
        InputFile        = $import.Path
        ReportPath       = ''
        Plan             = $null
        Counts           = $counts
        ActionsAttempted = 0
        StoppedBecause   = ''
        Warnings         = @()
    }

    if ($import.NothingToDo) {
        Write-Information -MessageData 'Nothing to do: no row of the reviewed report has a decision (Delete, Archive or Lock).'
        $summary.ElapsedSeconds = $clock.Elapsed.TotalSeconds
        return $summary
    }

    $plan = Get-SPSLifecycleActPlan -Import $import -Setting $setting
    $summary.Plan = $plan
    foreach ($line in Format-SPSLifecycleActBanner -Plan $plan -Setting $setting) {
        Write-Information -MessageData $line
    }

    if ($plan.Mode -eq 'Execute') {
        Confirm-SPSLifecycleAct -Plan $plan -Setting $setting
    }

    $summary.ReportPath = Initialize-SPSLifecycleActReport -OutputFolder $setting.OutputFolder -Delimiter $setting.CsvDelimiterChar -GeneratedOn $runTime

    $session = $null
    try {
        $session = Open-SPSLifecycleTenantSession -Setting $setting
        $homeSiteUrl = Get-SPSLifecycleHomeSiteUrl -Session $session

        if ($plan.HasArchive) {
            $archiveEnabled = Get-SPSLifecycleArchiveEnabled -Session $session
            if ($archiveEnabled -is [System.Boolean] -and -not $archiveEnabled) {
                if ($plan.Mode -eq 'Execute') {
                    throw 'Microsoft 365 Archive is off for sites (EnableSiteArchive is False): turn it on in the Microsoft 365 admin center (Settings, Org settings, Pay-as-you-go services, Microsoft 365 Archive), or take the rows to archive out of the file. Nothing was changed.'
                }

                $warnings.Add('Microsoft 365 Archive is off for sites (EnableSiteArchive is False): the archives of a real run would fail.')
            }
            elseif ($archiveEnabled -isnot [System.Boolean]) {
                if ($plan.Mode -eq 'Execute') {
                    throw 'The tool could not tell whether Microsoft 365 Archive is on for sites (EnableSiteArchive is not reported), and an archive that fails after the site was unlocked and the administrator was added would leave those changes: it does not start. Take the rows to archive out of the file, or update PnP.PowerShell. Nothing was changed.'
                }

                $warnings.Add('The tool could not tell whether Microsoft 365 Archive is on for sites (EnableSiteArchive is not reported): an archive may fail, and an Execute run would not start.')
            }
        }

        foreach ($warning in $warnings) {
            Write-Information -MessageData "Warning: $warning"
        }

        $account = ''
        if ($plan.Mode -eq 'Execute' -and $plan.HasArchive -and $plan.GrantSiteAdmin) {
            $account = Get-SPSLifecycleSignedInAccount -Session $session
        }

        $loopParameters = @{
            Session        = $session
            Setting        = $setting
            Plan           = $plan
            Row            = @($import.Rows)
            LockDateIndex  = $lockDateIndex
            ExclusionIndex = $exclusionIndex
            HomeSiteUrl    = $homeSiteUrl
            Account        = $account
            ReportPath     = $summary.ReportPath
        }
        if ($PSBoundParameters.ContainsKey('Now')) {
            $loopParameters.Now = $runTime
        }

        $loop = Invoke-SPSLifecycleActLoop @loopParameters
    }
    finally {
        if ($null -ne $session) {
            Close-SPSLifecycleTenantSession -Session $session
        }
    }

    $summary.Counts = $loop.Counts
    $summary.ActionsAttempted = $loop.ActionsAttempted
    $summary.StoppedBecause = $loop.StoppedBecause
    $summary.Warnings = $warnings.ToArray()
    $summary.ElapsedSeconds = $clock.Elapsed.TotalSeconds

    foreach ($line in Format-SPSLifecycleActSummary -Summary $summary) {
        Write-Information -MessageData $line
    }

    $summary
}
