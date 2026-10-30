function Set-SPSLifecycleSiteLockState {
    <#
        .SYNOPSIS
        Unlocks a site or makes it read-only. This changes the tenant.

        .DESCRIPTION
        One operation: Set-PnPTenantSite -LockState. The request returns before the site has changed state, and the caller waits
        for it (see Wait-SPSLifecycleLockState). Only Unlock and ReadOnly are possible: the tool never sets NoAccess. The target is
        checked first (see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .PARAMETER State
        Unlock or ReadOnly.

        .EXAMPLE
        Set-SPSLifecycleSiteLockState -Session $session -Url $url -State ReadOnly
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
        $Url,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Unlock', 'ReadOnly')]
        [System.String]
        $State
    )

    Assert-SPSLifecycleWriteTarget -Session $Session -Url $Url

    if (-not $PSCmdlet.ShouldProcess($Url, "Set the lock state to $State")) {
        return
    }

    try {
        $null = Set-PnPTenantSite -Identity $Url -LockState $State -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The lock state of the site '$Url' could not be set to $State`: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }
}
