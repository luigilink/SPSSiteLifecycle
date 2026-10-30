function Assert-SPSLifecyclePnPModule {
    <#
        .SYNOPSIS
        Loads PnP.PowerShell, or stops and says how to install it.

        .DESCRIPTION
        The module of the tool loads without PnP.PowerShell (the tests, the settings and the reports do not need it), and
        only the adapters call it. They load it here, when a Scan needs the tenant. Version 3.0 or later is needed: it is
        the one that runs on PowerShell 7.4 and that the SharePoint admin calls of the tool were checked against. A
        version that is already loaded is used as it is, and refused when it is too old.

        .EXAMPLE
        Assert-SPSLifecyclePnPModule
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param ()

    $minimum = [System.Version]'3.0.0'
    $module = @(Get-Module -Name 'PnP.PowerShell') | Select-Object -First 1
    if ($null -eq $module) {
        $available = @(Get-Module -Name 'PnP.PowerShell' -ListAvailable | Sort-Object -Property Version -Descending)
        if ($available.Count -eq 0) {
            throw 'PnP.PowerShell is not installed. Install version 3 or later with: Install-Module -Name PnP.PowerShell -Scope CurrentUser (it needs PowerShell 7.4 or later).'
        }

        if ($available[0].Version -lt $minimum) {
            throw "PnP.PowerShell $($available[0].Version) is too old: the tool needs version $minimum or later. Update it with: Update-Module -Name PnP.PowerShell"
        }

        $module = Import-Module -Name 'PnP.PowerShell' -MinimumVersion $minimum -PassThru -ErrorAction Stop
    }

    if ($module.Version -lt $minimum) {
        throw "PnP.PowerShell $($module.Version) is loaded, and the tool needs version $minimum or later. Start a new PowerShell session after updating it with: Update-Module -Name PnP.PowerShell"
    }
}
