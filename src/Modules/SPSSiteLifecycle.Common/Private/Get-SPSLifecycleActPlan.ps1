function Get-SPSLifecycleActPlan {
    <#
        .SYNOPSIS
        Says what an Act run will do, from the reviewed report and the settings: the banner and the confirmation read it.

        .DESCRIPTION
        Nothing is read from the tenant. The plan has:

        - Mode: Execute when the setting Act.Execute is exactly $true, and ReportOnly otherwise (a text, a number or nothing is
          not a yes).
        - InputFile, GeneratedOn (the oldest row of the file) and AgeDays.
        - Counts (Delete, Archive, Lock), DecisionCount (the rows that have a decision), MaxActions, DelaySeconds, and
          PlannedActions, the most that the run will do: the smaller of the two. A row that gets a SKIP- or a REVIEW- verdict
          is not an action and does not count, so the run may do fewer.
        - Phrase, the words that a person types to start an Execute run, which carry that number: DELETE n when every decision
          is a deletion, ARCHIVE n when every one is an archive, and APPLY n otherwise (a mix, or locks).
        - UnlockBeforeArchive, GrantSiteAdmin and HasArchive (whether a row is to be archived), for the banner.

        .PARAMETER Import
        The reviewed report (see Import-SPSLifecycleReviewedReport).

        .PARAMETER Setting
        The effective settings for the Act phase.

        .EXAMPLE
        Get-SPSLifecycleActPlan -Import $import -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Import,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    $act = $Setting.Act
    $decisions = [System.Int32]$Import.ActionCount
    $maxActions = [System.Int32]$act.MaxActions
    $planned = [System.Math]::Min($decisions, $maxActions)
    $delete = [System.Int32]$Import.Counts['Delete']
    $archive = [System.Int32]$Import.Counts['Archive']
    $lock = [System.Int32]$Import.Counts['Lock']

    $word = 'APPLY'
    if ($decisions -gt 0 -and $delete -eq $decisions) {
        $word = 'DELETE'
    }
    elseif ($decisions -gt 0 -and $archive -eq $decisions) {
        $word = 'ARCHIVE'
    }

    [PSCustomObject][ordered]@{
        Mode                = if ($act.Execute -is [System.Boolean] -and $act.Execute) { 'Execute' } else { 'ReportOnly' }
        InputFile           = $Import.Path
        GeneratedOn         = $Import.GeneratedOn
        AgeDays             = $Import.AgeDays
        Counts              = [ordered]@{ Delete = $delete; Archive = $archive; Lock = $lock }
        DecisionCount       = $decisions
        MaxActions          = $maxActions
        DelaySeconds        = [System.Int32]$act.DelaySeconds
        PlannedActions      = $planned
        Phrase              = '{0} {1}' -f $word, $planned.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        UnlockBeforeArchive = $act.UnlockBeforeArchive -eq $true
        GrantSiteAdmin      = $act.GrantSiteAdmin -eq $true
        HasArchive          = $archive -gt 0
    }
}
