function Open-SPSLifecycleTenantSession {
    <#
        .SYNOPSIS
        Signs in to the admin site of the tenant, and gives the session that the other adapters use.

        .DESCRIPTION
        Right before the sign-in, the tool checks again that the tenant is not refused and that the admin address is the
        one of that tenant (see Assert-SPSLifecycleTenantAllowed): the sign-in is the point after which nothing can be
        taken back. The sign-in is interactive, with the ClientId of the settings (the app registration of the tenant;
        certificate sign-in comes with #9). The connection is kept in the session and not made the current one of the
        PowerShell session, so that a connection that the user already has is left as it is.

        Returns the session: the connection and the tenant it is for.

        .PARAMETER Setting
        The settings (TenantName, AdminUrl, ClientId, RefusedTenants), as Get-SPSLifecycleSetting gives them.

        .EXAMPLE
        $session = Open-SPSLifecycleTenantSession -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    Assert-SPSLifecycleTenantAllowed -Setting $Setting

    $clientId = "$($Setting.ClientId)".Trim()
    if (-not $clientId) {
        throw 'ClientId: the sign-in needs the application (client) ID of the app registration of the tenant.'
    }

    Assert-SPSLifecyclePnPModule

    $tenantName = "$($Setting.TenantName)".Trim().ToLowerInvariant()
    try {
        $connection = Connect-PnPOnline -Url $Setting.AdminUrl -Interactive -ClientId $clientId -Tenant "$tenantName.onmicrosoft.com" -ReturnConnection -ErrorAction Stop
    }
    catch {
        throw "The sign-in to the admin site of the tenant failed: $($_.Exception.Message)"
    }

    if ($null -eq $connection) {
        throw 'The sign-in to the admin site of the tenant gave no connection. The calls that follow would use the connection that this PowerShell session already holds, which may be the one of another tenant, so the tool stops.'
    }

    [PSCustomObject][ordered]@{
        Connection = $connection
        TenantName = $tenantName
        AdminUrl   = "$($Setting.AdminUrl)"
    }
}
