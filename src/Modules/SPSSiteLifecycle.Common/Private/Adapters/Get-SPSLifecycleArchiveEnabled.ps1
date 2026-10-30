function Get-SPSLifecycleArchiveEnabled {
    <#
        .SYNOPSIS
        Reads whether Microsoft 365 Archive is on for sites in the tenant.

        .DESCRIPTION
        A read: Get-PnPTenant, and its EnableSiteArchive property. Gives $true or $false, or $null when the tenant does not say (no
        such property in this version of PnP.PowerShell, or a value that is not a boolean). It throws when the tenant could not
        be read.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .EXAMPLE
        Get-SPSLifecycleArchiveEnabled -Session $session
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session
    )

    try {
        $tenant = Get-PnPTenant -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "Whether Microsoft 365 Archive is on for sites could not be read: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }

    $flag = $tenant.EnableSiteArchive
    if ($flag -is [System.Boolean]) {
        return $flag
    }

    $null
}
