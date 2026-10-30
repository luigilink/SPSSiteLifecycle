function ConvertTo-SPSLifecycleScanRow {
    <#
        .SYNOPSIS
        The Scan core: gives each site of the listing its verdict, and one row with the columns of the report.

        .DESCRIPTION
        The pieces exist apart (the settings, the importers, the lock date index, the verdict engine). This function
        assembles them, and it reads nothing and changes nothing: it takes the site records that the listing gave, the
        indexes that were read, and returns what to write. The whole Scan logic is tested offline this way, and the
        listing of the tenant (see the adapters) can change without touching it.

        The records come from the pipeline, and each row goes down the pipeline as soon as it is made, so that a
        report of 260,000 sites needs no more memory than one of 100 when the rows go straight to
        Export-SPSLifecycleReport. What was done is counted into the summary (Initialize-SPSLifecycleScanSummary), which
        the caller reads when the pipeline is done.

        For each record:

        1. A OneDrive site, or a site whose address is not in the form that SharePoint gives (nothing can say what it
           is), is left out and counted, never listed (D12), and so is a site whose lock state is not one
           that the Scan asks for (the Scan.LockStates setting): the listing may not have been filtered by the server.
        2. A record that cannot be used stops the Scan and names its number and its address: a record without an
           address or a usable site ID (a site that cannot be matched with the reports and the lock dates, and that the
           Act phase could not confirm), a group ID that is neither empty nor a GUID (the Teams and groups activity of
           the site would be left out), a hub flag or a channel flag that is not True or False, a template that is
           empty, or a content change that is not a date. In each case a safeguard would silently not apply. These are
           defects of what reads the tenant, and a verdict that looks plausible would hide them.
        3. The lock date is found by the ID of the site, then by its address (Find-SPSLifecycleLockDate), the activity
           in the SharePoint, Teams and groups reports (Find-SPSLifecycleActivity), and the exclusion by the canonical
           form of the address.
        4. The verdict engine gives the verdict (Action Suggest), and the suggested action follows from it: Lock,
           Archive or Delete for an action, nothing for a SKIP- or a REVIEW- verdict. Decision stays empty: the tool
           never decides in the place of a person.

        The row has the columns of Get-SPSLifecycleReportColumn, in that order. The dates are UTC dates and the time of
        the run is the same on every row. InactiveDays is a whole number of days, and empty when no report gives a date.
        A column that the tool does not know stays empty, as the report writer expects: an unknown size is never zero.

        .PARAMETER Site
        The site records of the listing (see the adapters): Url, SiteId, Title, Template, LockState, GroupId, IsHubSite,
        IsTeamsConnected, IsTeamsChannelConnected, ArchiveStatus, StorageUsedMB and LastContentModified.

        .PARAMETER Setting
        The effective settings (see Get-SPSLifecycleSetting).

        .PARAMETER ActivityReport
        The imports of the activity reports that were given (Import-SPSLifecycleActivityReport): at most one of each kind,
        and at least one.

        .PARAMETER LockDateIndex
        The index of the lock dates (Get-SPSLifecycleLockDateIndex).

        .PARAMETER ExclusionIndex
        The index of the exclusion lists (Get-SPSLifecycleExclusionIndex).

        .PARAMETER Summary
        The summary to count into (Initialize-SPSLifecycleScanSummary).

        .PARAMETER Now
        The time of the run. It is converted to UTC, and written as GeneratedOn: give the report writer the same time.

        .PARAMETER HomeSiteUrl
        The address of the SharePoint home site, when it is known: it is protected.

        .PARAMETER HomeSiteUrlSource
        A script block that gives the address of the home site, for a caller that reads it from the tenant while the pipeline
        runs: the pipeline binds the parameters before the listing signs in, so the address is not there yet. The block is
        called once, when the first record comes (never when there is none), and gives a text, empty when the tenant has no
        home site. A failure of the block, or an answer that is not a text, stops the Scan before any row: a home site that
        is not known would be suggested like the others. It cannot be given together with HomeSiteUrl.

        .EXAMPLE
        $summary = Initialize-SPSLifecycleScanSummary
        $sites | ConvertTo-SPSLifecycleScanRow -Setting $setting -ActivityReport $reports -LockDateIndex $locks -ExclusionIndex $exclusions -Summary $summary | Export-SPSLifecycleReport -OutputFolder .\Reports
    #>
    [CmdletBinding(DefaultParameterSetName = 'Value')]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Value')]
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Source')]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Site,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Management.Automation.PSObject[]]
        $ActivityReport,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $LockDateIndex,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $ExclusionIndex,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Summary,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow,

        [Parameter(ParameterSetName = 'Value')]
        [AllowEmptyString()]
        [System.String]
        $HomeSiteUrl = '',

        [Parameter(Mandatory = $true, ParameterSetName = 'Source')]
        [System.Management.Automation.ScriptBlock]
        $HomeSiteUrlSource
    )

    begin {
        $missing = [System.Collections.Generic.List[System.String]]::new()
        foreach ($name in 'TenantName', 'TenantUrl', 'AcceptedLockStates', 'MinLockedDays', 'DeleteMaxSizeGB') {
            if ($null -eq $Setting.PSObject.Properties[$name] -or $null -eq $Setting.$name) {
                $missing.Add($name)
            }
        }

        if ($null -eq $Setting.PSObject.Properties['Scan'] -or $null -eq $Setting.Scan) {
            $missing.Add('Scan')
        }
        else {
            foreach ($name in 'InactiveDays', 'LockStates') {
                if ($null -eq $Setting.Scan.PSObject.Properties[$name] -or $null -eq $Setting.Scan.$name) {
                    $missing.Add("Scan.$name")
                }
            }
        }

        if ($missing.Count -gt 0) {
            throw "The settings lack $($missing -join ', '). Read them with Get-SPSLifecycleSetting."
        }

        $lockStates = @($Setting.Scan.LockStates)
        if ($lockStates.Count -eq 0) {
            throw 'The setting Scan.LockStates lists no lock state, so the Scan would list no site.'
        }

        $sharePoint = $null
        $teams = $null
        $groups = $null
        foreach ($report in @($ActivityReport)) {
            switch ($report.Kind) {
                'SharePoint' {
                    if ($null -ne $sharePoint) {
                        throw "The SharePoint activity report was given twice ('$($sharePoint.Name)' and '$($report.Name)'): give one report of each kind."
                    }

                    $sharePoint = $report
                }

                'Teams' {
                    if ($null -ne $teams) {
                        throw "The Teams activity report was given twice ('$($teams.Name)' and '$($report.Name)'): give one report of each kind."
                    }

                    $teams = $report
                }

                'Groups' {
                    if ($null -ne $groups) {
                        throw "The Groups activity report was given twice ('$($groups.Name)' and '$($report.Name)'): give one report of each kind."
                    }

                    $groups = $report
                }

                default {
                    throw "An activity report of the kind '$($report.Kind)' is not one that the Scan reads (SharePoint, Teams or Groups)."
                }
            }
        }

        if ($null -eq $sharePoint -and $null -eq $teams -and $null -eq $groups) {
            throw 'No activity report was given: nothing could say that a site is inactive. Give the SharePoint, the Teams or the Groups activity report.'
        }

        $runTime = ConvertTo-SPSLifecycleUtcDateTime -Value $Now
        $exclusions = $ExclusionIndex.Keys
        $number = 0
        $homeSiteKnown = $PSCmdlet.ParameterSetName -ne 'Source'
    }

    process {
        # A null that is piped is bound as $null, and foreach over $null visits nothing: it must still be a record.
        $records = $Site
        if ($null -eq $records) {
            $records = @($null)
        }

        foreach ($record in $records) {
            if (-not $homeSiteKnown) {
                $answer = @(& $HomeSiteUrlSource)
                if ($answer.Count -gt 1 -or ($answer.Count -eq 1 -and $null -ne $answer[0] -and $answer[0] -isnot [System.String])) {
                    throw 'The source of the address of the home site gave something that is not a text, so the home site could not be protected: the Scan stops.'
                }

                $HomeSiteUrl = if ($answer.Count -eq 1) { "$($answer[0])" } else { '' }
                $homeSiteKnown = $true
            }

            $number++
            $url = ''
            try {
                if ($null -eq $record) {
                    throw 'the record is empty.'
                }

                $Summary.SitesRead++
                $url = "$($record.Url)".Trim()

                if (Test-SPSLifecycleOneDrive -Site $record -TenantName $Setting.TenantName) {
                    $Summary.LeftOutOneDrive++
                    continue
                }

                $lockState = "$($record.LockState)"
                if ($lockStates -notcontains $lockState) {
                    $Summary.LeftOutLockState++
                    continue
                }

                if (-not $url) {
                    throw 'the record has no address (Url).'
                }

                $siteId = ConvertTo-SPSLifecycleId -Value $record.SiteId
                if (-not $siteId) {
                    throw "the record has no usable site ID (SiteId '$(ConvertTo-SPSLifecycleVisibleText -Text "$($record.SiteId)")'): it cannot be matched with the reports and the lock dates, and the Act phase could not confirm the site."
                }

                # An empty group ID, and the all-zero one that the tenant gives to a site without a group, say that there is no group.
                # Any other value that is not a GUID is not "no group": the Teams and groups activity of the site would be left out
                # without a message, and a site that is active there could be suggested for deletion.
                $groupId = ConvertTo-SPSLifecycleId -Value $record.GroupId
                if (-not $groupId) {
                    # ConvertTo-SPSLifecycleId gives an empty text for a GUID that is all zeros too, and only for that one.
                    $groupText = "$($record.GroupId)".Trim()
                    $zero = [System.Guid]::Empty
                    if ($groupText -and -not [System.Guid]::TryParse($groupText, [ref]$zero)) {
                        throw "the record has a group ID that is not a GUID (GroupId '$(ConvertTo-SPSLifecycleVisibleText -Text $groupText)'): the activity of its Teams and Microsoft 365 group cannot be found, and the site could look inactive."
                    }
                }

                # The safeguards read these three values, and a value that is missing reads as "not protected".
                if ($record.IsHubSite -isnot [System.Boolean]) {
                    throw 'the record does not say whether the site is a hub site (IsHubSite must be True or False): a hub site would not be protected.'
                }

                if ($record.IsTeamsChannelConnected -isnot [System.Boolean]) {
                    throw 'the record does not say whether the site is a Teams channel site (IsTeamsChannelConnected must be True or False): a channel site would not be protected.'
                }

                if ($record.Template -isnot [System.String] -or -not $record.Template.Trim()) {
                    throw 'the record has no template, or a template that is not a text (Template): a system site would not be recognized.'
                }


                try {
                    $modified = ConvertTo-SPSLifecycleUtcDateTime -Value $record.LastContentModified
                }
                catch {
                    throw "LastContentModified: $($_.Exception.Message)"
                }

                $lock = Find-SPSLifecycleLockDate -Index $LockDateIndex -SiteId $siteId -Url $url
                $activity = Find-SPSLifecycleActivity -SharePoint $sharePoint -Teams $teams -Groups $groups -SiteId $siteId -Url $url -GroupId $groupId
                $excluded = $exclusions.ContainsKey((ConvertTo-SPSLifecycleUrlKey -Url $url))

                $verdictSite = [PSCustomObject]@{
                    Url                     = $url
                    Template                = $record.Template
                    LockState               = $lockState
                    GroupId                 = $groupId
                    IsHubSite               = $record.IsHubSite
                    IsTeamsChannelConnected = $record.IsTeamsChannelConnected
                    ArchiveStatus           = $record.ArchiveStatus
                    StorageUsedMB           = $record.StorageUsedMB
                    LastContentModified     = $modified
                }

                $verdictParameters = @{
                    Site        = $verdictSite
                    Setting     = $Setting
                    Action      = 'Suggest'
                    Now         = $runTime
                    Excluded    = $excluded
                    Activity    = $activity
                    HomeSiteUrl = $HomeSiteUrl
                }

                if ($null -ne $lock) {
                    $verdictParameters.LockedOn = $lock.LockedOn
                }

                $verdict = Get-SPSLifecycleVerdict @verdictParameters
                $action = switch ($verdict) {
                    'LOCK' { 'Lock' }
                    'ARCHIVE' { 'Archive' }
                    'DELETE-SITE' { 'Delete' }
                    'DELETE-VIA-GROUP' { 'Delete' }
                    default { '' }
                }

                $inactiveDays = $null
                if ($null -ne $activity.LastActivity) {
                    $inactiveDays = [System.Math]::Max(0, [System.Int32][System.Math]::Floor(($runTime - $activity.LastActivity).TotalDays))
                }

                $Summary.SitesListed++
                $Summary.ByVerdict[$verdict] = 1 + [System.Int32]$Summary.ByVerdict[$verdict]
                $actionKey = if ($action) { $action } else { 'None' }
                $Summary.ByAction[$actionKey] = 1 + [System.Int32]$Summary.ByAction[$actionKey]

                [PSCustomObject]([ordered]@{
                        Url                = $url
                        Verdict            = $verdict
                        SuggestedAction    = $action
                        Decision           = ''
                        SiteId             = $siteId
                        Title              = $record.Title
                        Template           = $record.Template.Trim()
                        GroupId            = $groupId
                        IsTeamsConnected   = $record.IsTeamsConnected
                        LockState          = $lockState
                        ArchiveStatus      = $record.ArchiveStatus
                        StorageUsedMB      = $record.StorageUsedMB
                        LastActivity       = $activity.LastActivity
                        LastActivitySource = $activity.LastActivitySource
                        InactiveDays       = $inactiveDays
                        SharePointActivity = $activity.SharePoint
                        TeamsActivity      = $activity.Teams
                        GroupActivity      = $activity.Groups
                        ContentModified    = $modified
                        LockedOn           = if ($null -ne $lock) { $lock.LockedOn } else { $null }
                        LockedOnSource     = if ($null -ne $lock) { $lock.Source } else { $null }
                        GeneratedOn        = $runTime
                    })
            }
            catch {
                $where = if ($url) { " ($url)" } else { '' }
                throw "Scan record $number$where`: $($_.Exception.Message)"
            }
        }
    }
}
