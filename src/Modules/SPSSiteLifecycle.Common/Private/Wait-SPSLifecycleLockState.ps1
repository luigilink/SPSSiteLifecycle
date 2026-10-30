function Wait-SPSLifecycleLockState {
    <#
        .SYNOPSIS
        Waits until a site is in the lock state that was asked for.

        .DESCRIPTION
        A change of lock state returns before the site has changed (see Set-SPSLifecycleSiteLockState), so the site is read again
        until it reports the state: 24 reads, 5 seconds apart (2 minutes), which is what the lab needed. Gives the record that was
        read when the site reports the state, so that the caller can check it again, and nothing when it does not in time. A site that
        is not there is not in the state. A read that fails is not a state: the error goes up. The state is compared as it is written
        (ReadOnly is not readonly). With SiteId, a read that gives another site (the address was reused while the tool waited) stops
        the wait with an error: the state of another site is not the state of this one.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .PARAMETER State
        The state that is waited for: Unlock or ReadOnly.

        .PARAMETER SiteId
        The ID of the site that is waited for. Default: not checked.

        .PARAMETER Tries
        The number of reads. Default: 24.

        .PARAMETER DelaySeconds
        The pause between two reads. Default: 5.

        .EXAMPLE
        Wait-SPSLifecycleLockState -Session $session -Url $url -State Unlock
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
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
        $State,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $SiteId = '',

        [Parameter()]
        [ValidateRange(1, 1000)]
        [System.Int32]
        $Tries = 24,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [System.Int32]
        $DelaySeconds = 5
    )

    for ($try = 1; $try -le $Tries; $try++) {
        $site = Get-SPSLifecycleLiveSite -Session $Session -Url $Url
        if ($null -ne $site -and $SiteId -and -not [System.String]::Equals((ConvertTo-SPSLifecycleId -Value $site.SiteId), $SiteId, [System.StringComparison]::Ordinal)) {
            throw "The address now belongs to another site (its site ID is not $SiteId): the wait for the lock state $State stops, because the state of another site is not the state of this one."
        }

        if ($null -ne $site -and [System.String]::Equals("$($site.LockState)", $State, [System.StringComparison]::Ordinal)) {
            return $site
        }

        if ($try -lt $Tries) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    $null
}
