function Remove-SPSLifecycleSite {
    <#
        .SYNOPSIS
        Deletes a site that has no Microsoft 365 group, into the recycle bin of the deleted sites. This changes the tenant.

        .DESCRIPTION
        One operation: Remove-PnPTenantSite. The site goes to the recycle bin and stays restorable while the retention lasts: the
        tool never skips the recycle bin. A read-only site refuses a direct deletion (access denied), and the caller unlocks it
        first. The target is checked first (see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .EXAMPLE
        Remove-SPSLifecycleSite -Session $session -Url $url
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

    if (-not $PSCmdlet.ShouldProcess($Url, 'Delete the site')) {
        return
    }

    try {
        $null = Remove-PnPTenantSite -Url $Url -Force -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The site '$Url' could not be deleted: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }
}
