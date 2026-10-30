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
        4. The row is read again from the tenant right before its action and given its verdict (Get-SPSLifecycleActVerdict). A read that
           fails is ReadError. A SKIP- verdict is Skipped, a REVIEW- one is Review (with the meaning of the verdict as the detail). An
           action verdict is WouldDo in report-only mode, and with Execute the action is done (Invoke-SPSLifecycleSiteAction): Done,
           or Failed with the message.
        5. The row goes in the Act report at once, whatever its outcome (see Add-SPSLifecycleActReportRow). A run that stops half-way
           (an error that nobody expected goes up) leaves the record of what was done.

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

        .PARAMETER HomeSiteUrl
        The address of the home site, which is protected.

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
        $HomeSiteUrl = '',

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
    $meaning = @{}
    foreach ($entry in Get-SPSLifecycleVerdictCatalog) {
        $meaning[$entry.Verdict] = $entry.Meaning
    }

    $wouldDo = @{
        'LOCK'             = 'make the site read-only and write its date in the lock journal'
        'ARCHIVE'          = 'request the archive of the site'
        'DELETE-SITE'      = 'delete the site'
        'DELETE-VIA-GROUP' = 'delete the group of the site, and SharePoint would delete the site some time later'
    }

    $attempted = 0
    $consecutive = 0
    $stopped = ''
    $pause = $false
    $reportFile = $ReportPath
    $fixedTime = $Now

    $record = {
        param($Item, [System.String]$Verdict, [System.String]$Outcome, [System.String]$Detail, [System.DateTime]$Time)

        $counts[$Outcome]++
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
        $result = Get-SPSLifecycleActVerdict -Row $item -Session $Session -Setting $Setting -LockDateIndex $LockDateIndex -ExclusionIndex $ExclusionIndex -HomeSiteUrl $HomeSiteUrl -Now $time

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
            try {
                $detail = Invoke-SPSLifecycleSiteAction -Session $Session -Setting $Setting -Verdict $verdict -Site $result.Site -Account $Account -Now (& $clock)
                & $record $item $verdict 'Done' $detail (& $clock)
                $consecutive = 0
            }
            catch {
                & $record $item $verdict 'Failed' $_.Exception.Message (& $clock)
                $consecutive++
                if ($consecutive -ge $maxErrors) {
                    $stopped = 'ConsecutiveErrors'
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
