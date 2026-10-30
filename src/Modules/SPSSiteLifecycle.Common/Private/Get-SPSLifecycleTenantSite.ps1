function Get-SPSLifecycleTenantSite {
    <#
        .SYNOPSIS
        Lists the sites of the tenant for the Scan: signs in, lists them page by page, and takes up an interrupted listing.

        .DESCRIPTION
        This is the one call that the Scan makes to read the tenant. It does, in this order: it turns the lock states of the
        settings into the server filter (see Get-SPSLifecycleListingFilter), signs in (the refused tenants are checked
        again right before, see Open-SPSLifecycleTenantSession), chooses the call, and gives the records to the pipeline
        as Invoke-SPSLifecycleSiteListing reads them (paged, with a checkpoint in the listing-checkpoint folder of
        OutputFolder, resumed when it was interrupted). The session ends when the listing does, whatever the way.

        The call is the paged one of the SharePoint admin API when this PnP.PowerShell has it, which the listing is
        resumable with, and Get-PnPTenantSite otherwise (Source Auto), which gives the whole listing in one page and
        cannot be resumed. The summary says which was used, and why not the paged one. The OneDrive sites are left out by
        the server (D12), and the ones that come anyway are dropped and counted.

        A progress line is shown while the listing goes on (sites, page, time and rate), unless the caller gives its own
        OnProgress.

        .PARAMETER Setting
        The settings (TenantName, AdminUrl, ClientId, RefusedTenants, OutputFolder and Scan.LockStates), as
        Get-SPSLifecycleSetting gives them for the Scan.

        .PARAMETER Summary
        The summary of the listing (see Initialize-SPSLifecycleListingSummary).

        .PARAMETER Source
        Auto (the default), Csom for the paged call only, or Cmdlet for Get-PnPTenantSite.

        .PARAMETER Restart
        Ignores the checkpoint of an interrupted listing and starts again.

        .PARAMETER OnProgress
        A script block that is given an object after each page (see Invoke-SPSLifecycleSiteListing).

        .PARAMETER Now
        The time of the run, in UTC. Default: now.

        .EXAMPLE
        Get-SPSLifecycleTenantSite -Setting $setting -Summary $summary | ConvertTo-SPSLifecycleScanRow @parameters
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Summary,

        [Parameter()]
        [ValidateSet('Auto', 'Csom', 'Cmdlet')]
        [System.String]
        $Source = 'Auto',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Restart,

        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $filter = Get-SPSLifecycleListingFilter -LockState @($Setting.Scan.LockStates)
    $session = $null
    $activity = 'Listing the sites of the tenant'
    try {
        $session = Open-SPSLifecycleTenantSession -Setting $Setting

        $resolved = 'Cmdlet'
        $Summary.FallbackReason = ''
        if ($Source -eq 'Cmdlet') {
            $Summary.FallbackReason = 'The cmdlet was asked for (Source Cmdlet).'
        }
        else {
            $api = Test-SPSLifecycleListingApi
            if ($api.Available) {
                $resolved = 'Csom'
            }
            elseif ($Source -eq 'Csom') {
                throw "The paged listing was asked for and cannot be used: $($api.Reason)"
            }
            else {
                $Summary.FallbackReason = $api.Reason
            }
        }

        $Summary.Source = $resolved
        $Summary.PersonalSites = 'Excluded'

        $progressHandler = $OnProgress
        if ($null -eq $progressHandler) {
            $progressHandler = {
                param($Progress)
                Write-Progress -Activity 'Listing the sites of the tenant' -Status ('{0:n0} sites, page {1}, {2:n0} s, {3:n0} sites/s' -f $Progress.SitesReturned, $Progress.Pages, $Progress.ElapsedSeconds, $Progress.SitesPerSecond) -PercentComplete -1
            }
        }

        $pageSource = {
            param([System.String]$StartIndex, $Context)
            Get-SPSLifecycleTenantSitePage -Session $Context.Session -Source $Context.Source -StartIndex $StartIndex -Filter $Context.Filter
        }

        $parameters = @{
            PageSource         = $pageSource
            PageSourceArgument = [PSCustomObject]@{ Session = $session; Source = $resolved; Filter = $filter }
            CheckpointFolder   = Join-Path -Path $Setting.OutputFolder -ChildPath 'listing-checkpoint'
            Tenant             = $Setting.TenantName
            Filter             = $filter
            Options            = "Source=$resolved;PersonalSites=Excluded"
            Summary            = $Summary
            Restart            = $Restart
            Now                = $Now
            OnProgress         = $progressHandler
        }
        Invoke-SPSLifecycleSiteListing @parameters
    }
    finally {
        Write-Progress -Activity $activity -Completed
        if ($null -ne $session) {
            Close-SPSLifecycleTenantSession -Session $session
        }
    }
}
