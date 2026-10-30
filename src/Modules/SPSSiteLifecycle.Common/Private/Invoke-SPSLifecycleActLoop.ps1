function Invoke-SPSLifecycleActLoop {
    <#
        .SYNOPSIS
        Goes through the rows of the reviewed report that have a decision, reads each one again, and does what its verdict says (or
        says what it would do), with the safeguards of D6.

        .DESCRIPTION
        For each row, in the order of the file:

        1. The run stops after 3 errors in a row (fixed, not a setting): a site that cannot be read and an action that fails are
           errors, and a row that is not an error (an action done, a skip, a review) starts the count again. The rows that follow
           are NotRun, with the reason, and are not read.
        2. With Execute, once MaxActions actions have been tried (an action that failed counts, a row that is not an action does
           not), the rows that follow are NotRun and are not read. In report-only mode every row is read and gets its verdict, and the
           rows past the cap are NotRun with their verdict: a real run would not do them.
        3. With Execute, the pause between two actions (DelaySeconds) comes before the next row is read, so that the read and the action
           of a row are not apart.
        4. The row is read again from the tenant right before its action, with the home site (which is read for each row, since the
           assignment can change during a run), and given its verdict (Get-SPSLifecycleActVerdict). A read that fails, the home
           site's included, is ReadError. A SKIP- verdict is Skipped, a REVIEW- one is Review (with the meaning of the verdict as the detail). An
           action verdict is WouldDo in report-only mode, and with Execute the action is done (Invoke-SPSLifecycleSiteAction): Done,
           or Failed with the message.
        5. The row goes in the Act report at once, whatever its outcome (see Add-SPSLifecycleActReportRow). A run that stops half-way
           (an error that nobody expected goes up) leaves the record of what was done.
        6. With Execute, a row InProgress is written to the report, and so to the disk, right before the tenant is touched for a row,
           and the tool does not act when it cannot be written. The row of the outcome follows it. When the run is killed, or the
           machine goes down, during the action, nothing else can be written, and the row InProgress with no outcome after it is the
           trace: a person looks at the site. When the run is interrupted (Ctrl+C), a row Interrupted is written after it. Neither
           is an outcome: they are not counted.

        Report only never calls an adapter that changes the tenant. The function returns the counts of the outcomes, the number of
        actions that were tried, and why the run stopped, if it did (ConsecutiveErrors).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Setting
        The effective settings for the Act phase.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleActPlan): the mode.

        .PARAMETER Row
        The rows of the reviewed report that have a decision (see Import-SPSLifecycleReviewedReport).

        .PARAMETER LockDateIndex
        The index of the lock dates (Get-SPSLifecycleLockDateIndex).

        .PARAMETER ExclusionIndex
        The index of the exclusion lists (Get-SPSLifecycleExclusionIndex).

        .PARAMETER Account
        The account of the signed-in administrator, for GrantSiteAdmin.

        .PARAMETER ReportPath
        The path of the Act report (see Initialize-SPSLifecycleActReport).

        .PARAMETER Now
        The time of the run, for the tests. Default: the time of each row.

        .EXAMPLE
        Invoke-SPSLifecycleActLoop -Session $session -Setting $setting -Plan $plan -Row $import.Rows -LockDateIndex $locks -ExclusionIndex $exclusions -ReportPath $path
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Row,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $LockDateIndex,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $ExclusionIndex,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Account = '',

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReportPath,

        [Parameter()]
        [AllowNull()]
        [System.Nullable[System.DateTime]]
        $Now = $null
    )

    $maxErrors = 3
    $execute = $Plan.Mode -eq 'Execute'
    $maxActions = [System.Int32]$Setting.Act.MaxActions
    $delay = [System.Int32]$Setting.Act.DelaySeconds
    $counts = [ordered]@{ Done = 0; Failed = 0; WouldDo = 0; Skipped = 0; Review = 0; ReadError = 0; NotRun = 0 }
    # The words of a verdict are compared as they are written: a hashtable ignores the case, and a verdict that is not exact is not an action.
    $meaning = [System.Collections.Generic.Dictionary[System.String, System.String]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in Get-SPSLifecycleVerdictCatalog) {
        $meaning[$entry.Verdict] = $entry.Meaning
    }

    $wouldDo = [System.Collections.Generic.Dictionary[System.String, System.String]]::new([System.StringComparer]::Ordinal)
    $wouldDo['LOCK'] = 'make the site read-only and write its date in the lock journal'
    $wouldDo['ARCHIVE'] = 'request the archive of the site'
    $wouldDo['DELETE-SITE'] = 'delete the site'
    $wouldDo['DELETE-VIA-GROUP'] = 'delete the group of the site, and SharePoint would delete the site some time later'

    $attempted = 0
    $consecutive = 0
    $stopped = ''
    $pause = $false
    $reportFile = $ReportPath
    $fixedTime = $Now

    $write = {
        param($Item, [System.String]$Verdict, [System.String]$Outcome, [System.String]$Detail, [System.DateTime]$Time)

        Add-SPSLifecycleActReportRow -Path $reportFile -Delimiter $Setting.CsvDelimiterChar -Row ([PSCustomObject][ordered]@{
                Line        = $Item.Line
                Url         = $Item.Url
                SiteId      = $Item.SiteId
                Decision    = $Item.Decision
                Verdict     = $Verdict
                Outcome     = $Outcome
                Detail      = $Detail
                ProcessedOn = $Time
            })
    }
    $record = {
        param($Item, [System.String]$Verdict, [System.String]$Outcome, [System.String]$Detail, [System.DateTime]$Time)

        $counts[$Outcome]++
        & $write $Item $Verdict $Outcome $Detail $Time
    }
    $clock = {
        if ($null -ne $fixedTime) { $fixedTime } else { [System.DateTime]::UtcNow }
    }

    foreach ($item in $Row) {
        if ($stopped) {
            & $record $item '' 'NotRun' "The run stopped after $maxErrors errors in a row ($stopped): this row was not read." (& $clock)
            continue
        }

        if ($execute -and $attempted -ge $maxActions) {
            & $record $item '' 'NotRun' "MaxActions ($maxActions) was reached before this row: it was not read." (& $clock)
            continue
        }

        if ($execute -and $pause -and $delay -gt 0) {
            Start-Sleep -Seconds $delay
        }

        $pause = $false
        $time = & $clock

        # The home site is read for each row, with the site: the assignment can change during a run that lasts, and the safeguard is a live one.
        $homeSiteUrl = ''
        $result = $null
        try {
            $homeSiteUrl = Get-SPSLifecycleHomeSiteUrl -Session $Session
        }
        catch {
            $result = [PSCustomObject]@{ Verdict = ''; ReadError = $_.Exception.Message }
        }

        if ($null -eq $result) {
            $result = Get-SPSLifecycleActVerdict -Row $item -Session $Session -Setting $Setting -LockDateIndex $LockDateIndex -ExclusionIndex $ExclusionIndex -HomeSiteUrl $homeSiteUrl -Now $time
        }

        if ($result.ReadError) {
            & $record $item '' 'ReadError' $result.ReadError $time
            $consecutive++
            if ($consecutive -ge $maxErrors) {
                $stopped = 'ConsecutiveErrors'
            }

            continue
        }

        $verdict = "$($result.Verdict)"
        if ($wouldDo.ContainsKey($verdict)) {
            if (-not $execute) {
                if ($attempted -ge $maxActions) {
                    & $record $item $verdict 'NotRun' "MaxActions ($maxActions) would be reached before this row: a real run would not do it." $time
                }
                else {
                    $attempted++
                    & $record $item $verdict 'WouldDo' "Report only: nothing was changed. The tool would $($wouldDo[$verdict])." $time
                }

                $consecutive = 0
                continue
            }

            $attempted++
            $pause = $true

            # On the disk before the tenant is touched, and outside the try: when it cannot be written, nothing is done that is not on record.
            & $write $item $verdict 'InProgress' 'Started. If no later row of this site says how it ended, the run stopped during the action (it was killed, or the machine went down): the tenant may have been changed, and the site may still be unlocked. Check the site.' (& $clock)

            $recorded = $false
            try {
                $detail = Invoke-SPSLifecycleSiteAction -Session $Session -Setting $Setting -Verdict $verdict -Site $result.Site -Account $Account -Now (& $clock)
                & $record $item $verdict 'Done' $detail (& $clock)
                $recorded = $true
                $consecutive = 0
            }
            catch {
                & $record $item $verdict 'Failed' $_.Exception.Message (& $clock)
                $recorded = $true
                $consecutive++
                if ($consecutive -ge $maxErrors) {
                    $stopped = 'ConsecutiveErrors'
                }
            }
            finally {
                # Ctrl+C is not caught by a catch, so only a finally leaves the trace of an interrupted action. It is tried only, since the report may be
                # what failed, and what it says is what can be said of both cases.
                if (-not $recorded) {
                    try {
                        & $write $item $verdict 'Interrupted' 'The run ended during the action, before its outcome was recorded (it was interrupted, or the report could not be written): the tenant may have been changed. Check the site, and whether it is still unlocked.' (& $clock)
                    }
                    catch {
                        $null = $_
                    }
                }
            }

            continue
        }

        $detail = if ($meaning.ContainsKey($verdict)) { $meaning[$verdict] } else { '' }
        if ($verdict.StartsWith('SKIP-', [System.StringComparison]::Ordinal)) {
            & $record $item $verdict 'Skipped' $detail $time
        }
        elseif ($verdict.StartsWith('REVIEW-', [System.StringComparison]::Ordinal)) {
            & $record $item $verdict 'Review' $detail $time
        }
        else {
            throw "The row at line $($item.Line) got the verdict '$(ConvertTo-SPSLifecycleVisibleText -Text $verdict -AsciiOnly)', which is not one that the Act phase knows: the tool stops instead of guessing."
        }

        $consecutive = 0
    }

    [PSCustomObject][ordered]@{
        Counts           = $counts
        ActionsAttempted = $attempted
        StoppedBecause   = $stopped
    }
}
