function Invoke-SPSLifecycleSiteListing {
    <#
        .SYNOPSIS
        Lists the sites of the tenant page by page, with a checkpoint after each page, and takes up an interrupted
        listing where it stopped.

        .DESCRIPTION
        The pages come from a source that the caller gives (the adapter of the SharePoint admin API, or a test double),
        so that all the logic of the listing is tested without a tenant. The source is a script block that is given the
        token of the page to read (empty for the first) and gives an object with Items (the site records, see
        ConvertTo-SPSLifecycleSiteRecord) and NextStartIndex (the token of the next page, empty after the last).

        Each page is saved in the checkpoint (see Read-SPSLifecycleListingCheckpoint) before its sites are given to the
        pipeline, and the next page is not asked for before they were taken, so that a report of 260,000 sites needs no
        more memory than one of 100 and a run that stops loses at most the page that it was reading. A listing that is
        interrupted is taken up by the next run, which gives the saved pages first and asks only for the pages that are
        missing. It starts again, and says why, when the checkpoint is for another tenant, filter or way of asking, is
        older than 24 hours, is damaged, belongs to a listing that finished, or when Restart is given.

        A page that cannot be read is asked again (PageAttempts times, waiting longer each time) before the listing
        stops. It also stops when the next token is one that was already asked (a listing that does not advance would
        never end) or after MaxPages pages.

        The OneDrive sites that the call gave although it was asked not to (D12) are dropped and counted, with the sites
        whose address is not in the form that SharePoint gives (see Test-SPSLifecycleOneDrive), and so is a site that
        comes twice. What the listing did goes into Summary (see Initialize-SPSLifecycleListingSummary). Only one run at
        a time writes a checkpoint (see Open-SPSLifecycleListingLock).

        When the listing is over, the pages are deleted and the manifest says that it finished. A run that is stopped
        before that, by an error or by the one who reads the sites, leaves the checkpoint for the next run.

        .PARAMETER PageSource
        The script block that gives a page for a token.

        .PARAMETER CheckpointFolder
        The folder of the checkpoint, which is created. A relative path is relative to the location of the PowerShell
        session.

        .PARAMETER Tenant
        The name of the tenant, for the checkpoint and for the OneDrive host.

        .PARAMETER Filter
        The server filter that the source applies, empty for none. A checkpoint is reused only for the same one.

        .PARAMETER Options
        The other things that change what the pages hold, as one text. A checkpoint is reused only for the same one.

        .PARAMETER Summary
        The summary to write into (see Initialize-SPSLifecycleListingSummary).

        .PARAMETER Restart
        Ignores any checkpoint and starts again.

        .PARAMETER Now
        The time of the run, in UTC. Default: now.

        .PARAMETER MaxCheckpointAgeHours
        The age beyond which a checkpoint is not taken up. Default: 24.

        .PARAMETER PageAttempts
        How many times a page is asked before the listing stops. Default: 3.

        .PARAMETER RetryDelaySeconds
        The wait before the second attempt, doubled for the next ones. Default: 5.

        .PARAMETER MaxPages
        The number of pages beyond which the listing stops. Default: 100,000.

        .PARAMETER OnProgress
        A script block that is given an object after each page (Pages, SitesReturned, SitesRead, ElapsedSeconds,
        SitesPerSecond, PageSeconds, FromCheckpoint), and after each page that is taken from the checkpoint.

        .EXAMPLE
        Invoke-SPSLifecycleSiteListing -PageSource $source -CheckpointFolder .\Reports\listing-checkpoint -Tenant contoso -Summary $summary
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ScriptBlock]
        $PageSource,

        [Parameter(Mandatory = $true)]
        [System.String]
        $CheckpointFolder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Tenant,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Filter = '',

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Options = '',

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Summary,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Restart,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow,

        [Parameter()]
        [ValidateRange(0.001, 8760)]
        [System.Double]
        $MaxCheckpointAgeHours = 24,

        [Parameter()]
        [ValidateRange(1, 20)]
        [System.Int32]
        $PageAttempts = 3,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [System.Double]
        $RetryDelaySeconds = 5,

        [Parameter()]
        [ValidateRange(1, 1000000)]
        [System.Int32]
        $MaxPages = 100000,

        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    begin {
        $lock = $null
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    end {
        try {
            $runStart = $Now.ToUniversalTime()
            $Summary.StartedOn = $runStart
            $Summary.Filter = $Filter

            $folder = Resolve-SPSLifecycleFileSystemPath -Path $CheckpointFolder
            $lock = Open-SPSLifecycleListingLock -Folder $folder

            $manifest = $null
            if ($Restart) {
                $Summary.StartReason = 'A new listing was asked for (Restart).'
            }
            else {
                $state = Read-SPSLifecycleListingCheckpoint -Folder $folder -Tenant $Tenant -Filter $Filter -Options $Options -Now $runStart -MaxAgeHours $MaxCheckpointAgeHours
                if ($state.Usable) {
                    $manifest = $state.Manifest
                }
                elseif ($state.Exists) {
                    $Summary.StartReason = $state.Reason
                    if ($state.Finished) {
                        Write-Verbose -Message $state.Reason
                    }
                    else {
                        Write-Warning -Message "The listing starts again from the first page. $($state.Reason)"
                    }
                }
            }

            $resumed = $null -ne $manifest
            if (-not $resumed) {
                Clear-SPSLifecycleListingCheckpoint -Folder $folder
                $manifest = Initialize-SPSLifecycleListingManifest -Tenant $Tenant -Filter $Filter -Options $Options -Now $runStart
            }

            $Summary.Resumed = $resumed
            $seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
            $tokens = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)

            $progressHandler = $OnProgress
            $report = {
                param($FromCheckpoint, $PageSeconds)
                if ($null -ne $progressHandler) {
                    $rate = if ($Summary.PageSecondsTotal -gt 0) { $Summary.SitesRead / $Summary.PageSecondsTotal } else { 0.0 }
                    & $progressHandler ([PSCustomObject][ordered]@{
                            Pages          = $Summary.PagesFromCheckpoint + $Summary.PagesRead
                            SitesReturned  = $Summary.SitesReturned
                            SitesRead      = $Summary.SitesRead
                            ElapsedSeconds = $watch.Elapsed.TotalSeconds
                            SitesPerSecond = $rate
                            PageSeconds    = $PageSeconds
                            FromCheckpoint = $FromCheckpoint
                        })
                }
            }

            if ($resumed) {
                foreach ($entry in $manifest.Pages) {
                    $saved = @(Read-SPSLifecycleListingPage -Folder $folder -Entry $entry)
                    foreach ($site in $saved) {
                        if ($site.SiteId) {
                            $null = $seen.Add($site.SiteId)
                        }
                    }

                    $null = $tokens.Add($entry.Token)
                    $Summary.PagesFromCheckpoint++
                    $Summary.SitesFromCheckpoint += $saved.Count
                    $Summary.SitesReturned += $saved.Count
                    $saved
                    & $report $true 0.0
                }
            }

            $token = if ($resumed) { $manifest.NextToken } else { '' }
            $more = -not ($resumed -and $manifest.ListingComplete)
            while ($more) {
                $pageNumber = $manifest.Pages.Count + 1
                if ($pageNumber -gt $MaxPages) {
                    throw "The listing did not end after $MaxPages pages, which is the most that it may have: it is asked again and again without reaching its end."
                }

                if (-not $tokens.Add($token)) {
                    throw "The listing does not advance: the token '$(ConvertTo-SPSLifecycleVisibleText -Text $token)' was already asked, and asking it again would never end."
                }

                $pageWatch = [System.Diagnostics.Stopwatch]::StartNew()
                $attempt = 0
                $page = $null
                while ($true) {
                    $attempt++
                    try {
                        $page = & $PageSource $token
                        break
                    }
                    catch {
                        if ($attempt -ge $PageAttempts) {
                            $times = if ($attempt -eq 1) { '1 attempt' } else { "$attempt attempts" }
                            throw [System.InvalidOperationException]::new("Page $pageNumber of the listing could not be read after $times`: $($_.Exception.Message)", $_.Exception)
                        }

                        $Summary.Retries++
                        Write-Verbose -Message "Page $pageNumber could not be read ($($_.Exception.Message)): attempt $($attempt + 1) of $PageAttempts."
                        if ($RetryDelaySeconds -gt 0) {
                            Start-Sleep -Seconds ($RetryDelaySeconds * [System.Math]::Pow(2, $attempt - 1))
                        }
                    }
                }

                if ($null -eq $page -or $page -is [System.Array] -or $null -eq $page.PSObject.Properties['Items']) {
                    throw "The page source gave no page for the token '$(ConvertTo-SPSLifecycleVisibleText -Text $token)': it must give one object with Items (the sites) and NextStartIndex (the token of the next page)."
                }

                $items = @($page.Items)
                $nextToken = "$($page.NextStartIndex)"
                $keep = [System.Collections.Generic.List[System.Object]]::new($items.Count)
                foreach ($site in $items) {
                    if (Test-SPSLifecycleOneDrive -Site $site -TenantName $Tenant) {
                        $Summary.OneDriveDropped++
                        continue
                    }

                    if ($site.SiteId -and -not $seen.Add($site.SiteId)) {
                        $Summary.DuplicatesDropped++
                        continue
                    }

                    $keep.Add($site)
                }

                $pageSeconds = $pageWatch.Elapsed.TotalSeconds
                $null = Save-SPSLifecycleListingPage -Folder $folder -Manifest $manifest -Record $keep.ToArray() -Token $token -NextToken $nextToken -Read $items.Count -Seconds $pageSeconds -Now $runStart.AddSeconds($watch.Elapsed.TotalSeconds)

                $Summary.PagesRead++
                $Summary.SitesRead += $items.Count
                $Summary.SitesReturned += $keep.Count
                $Summary.PageSecondsTotal += $pageSeconds
                if ($pageSeconds -gt $Summary.PageSecondsMax) {
                    $Summary.PageSecondsMax = $pageSeconds
                }

                Write-Verbose -Message ('Page {0}: {1} sites in {2} s ({3} kept).' -f $pageNumber, $items.Count, $pageSeconds.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture), $keep.Count)
                $keep
                & $report $false $pageSeconds

                $token = $nextToken
                $more = [bool]$token
            }

            Complete-SPSLifecycleListingCheckpoint -Folder $folder -Manifest $manifest -Now $runStart.AddSeconds($watch.Elapsed.TotalSeconds)
            $Summary.FinishedOn = $runStart.AddSeconds($watch.Elapsed.TotalSeconds)
        }
        finally {
            $Summary.ElapsedSeconds = $watch.Elapsed.TotalSeconds
        }
    }

    clean {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}
