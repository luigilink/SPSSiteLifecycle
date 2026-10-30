function Format-SPSLifecycleActBanner {
    <#
        .SYNOPSIS
        Writes the banner of an Act run: what it is about to do, before anything is asked or changed.

        .DESCRIPTION
        The banner says the mode (report only, or execute: the tenant is changed), the file, the date of the oldest row and its
        age, the decisions by kind with the most that the run will do and the pause between two actions, what the Archive options
        do when a row is to be archived, and that every row is checked again. The numbers are written the same way whatever the
        culture of the machine.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleActPlan).

        .PARAMETER Setting
        The effective settings for the Act phase.

        .EXAMPLE
        Format-SPSLifecycleActBanner -Plan $plan -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $lines = [System.Collections.Generic.List[System.String]]::new()

    if ($Plan.Mode -eq 'Execute') {
        $lines.Add("Act phase on the tenant $($Setting.TenantName): EXECUTE. This run changes the tenant.")
    }
    else {
        $lines.Add("Act phase on the tenant $($Setting.TenantName): REPORT ONLY. This run changes nothing: it says what each row would get.")
    }

    $lines.Add("File: $($Plan.InputFile)")
    $lines.Add(('Generated on: {0} UTC (the oldest row of the file), {1} days ago; the limit is {2} days (MaxCsvAgeDays).' -f
            $Plan.GeneratedOn.ToString('yyyy-MM-dd HH:mm', $culture), ([System.Double]$Plan.AgeDays).ToString('N1', $culture), $Setting.Act.MaxCsvAgeDays.ToString($culture)))
    $lines.Add(('Decisions: Delete {0}, Archive {1}, Lock {2} ({3} in all). This run does at most {4} of them (MaxActions {5}), {6} s apart.' -f
            $Plan.Counts['Delete'], $Plan.Counts['Archive'], $Plan.Counts['Lock'], $Plan.DecisionCount, $Plan.PlannedActions, $Plan.MaxActions, $Plan.DelaySeconds))

    if ($Plan.HasArchive) {
        if ($Plan.UnlockBeforeArchive -and $Plan.GrantSiteAdmin) {
            $lines.Add('Archive: a read-only site is unlocked first and locked again afterwards (UnlockBeforeArchive), and the administrator who signed in is added to the site collection (GrantSiteAdmin).')
        }
        elseif ($Plan.UnlockBeforeArchive) {
            $lines.Add('Archive: a read-only site is unlocked first and locked again afterwards (UnlockBeforeArchive).')
        }
        elseif ($Plan.GrantSiteAdmin) {
            $lines.Add('Archive: the administrator who signed in is added to the site collection (GrantSiteAdmin).')
        }
        else {
            $lines.Add('Archive: no option is on (UnlockBeforeArchive, GrantSiteAdmin): the site is archived as it is.')
        }
    }

    $lines.Add("Every row is read again from the tenant right before its action, and a site that is protected, excluded, in a lock state that is not accepted, locked for less than $($Setting.MinLockedDays) days, or whose group is not active is left alone, whatever the decision.")

    $lines.ToArray()
}
