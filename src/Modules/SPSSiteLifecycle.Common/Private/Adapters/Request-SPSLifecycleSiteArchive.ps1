function Request-SPSLifecycleSiteArchive {
    <#
        .SYNOPSIS
        Asks for a site to be archived with Microsoft 365 Archive, without waiting for it. This changes the tenant.

        .DESCRIPTION
        One operation: Set-PnPSiteArchiveState -ArchiveState Archived -NoWait. The archive takes place later. It needs
        Microsoft 365 Archive to be on for sites, and the signed-in administrator to be an administrator of the site collection.
        The target is checked first (see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .EXAMPLE
        Request-SPSLifecycleSiteArchive -Session $session -Url $url
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Url
    )

    Assert-SPSLifecycleWriteTarget -Session $Session -Url $Url

    if (-not $PSCmdlet.ShouldProcess($Url, 'Archive the site')) {
        return
    }

    try {
        $null = Set-PnPSiteArchiveState -Identity $Url -ArchiveState Archived -NoWait -Force -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The archive of the site '$Url' could not be requested: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }
}
