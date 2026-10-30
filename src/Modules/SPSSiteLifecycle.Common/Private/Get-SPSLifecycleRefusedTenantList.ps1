function Get-SPSLifecycleRefusedTenantList {
    <#
        .SYNOPSIS
        Gives the tenants that the tool refuses to run on: the Microsoft corporate tenants and the ones of the settings.

        .DESCRIPTION
        microsoft and microsoftonline are always refused, and cannot be removed. The tenants of the RefusedTenants
        setting come after them, in lowercase (the invariant one: a tenant name is ASCII, and the Turkish rules turn a
        capital I into a letter that is not an i), once each.

        .PARAMETER RefusedTenant
        The tenants of the RefusedTenants setting.

        .EXAMPLE
        Get-SPSLifecycleRefusedTenantList -RefusedTenant 'fabrikam'
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $RefusedTenant = @()
    )

    $list = [System.Collections.Generic.List[System.String]]::new()
    foreach ($name in @('microsoft', 'microsoftonline') + @($RefusedTenant | ForEach-Object { "$_".Trim().ToLowerInvariant() })) {
        if ($name -and -not $list.Contains($name)) {
            $list.Add($name)
        }
    }

    $list.ToArray()
}
