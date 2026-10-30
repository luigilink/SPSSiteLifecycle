function Confirm-SPSLifecycleAppRegistration {
    <#
        .SYNOPSIS
        Asks a person to type the name of the tenant before the app is registered in it.

        .DESCRIPTION
        The barrier before the change, as for an Act run (see Confirm-SPSLifecycleAct): the plan has been shown, and a person types the
        name of the tenant (in any case, spaces around it do not count). Anything else stops the script with nothing changed, and so does
        an input that is redirected, before it asks: a confirmation that a script gave is not a person's.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .EXAMPLE
        Confirm-SPSLifecycleAppRegistration -Plan $plan
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan
    )

    if (Test-SPSLifecycleInputRedirected) {
        throw 'The input is redirected, so no person can type the confirmation, and the app is not registered. Nothing was changed.'
    }

    $typed = "$(Read-Host -Prompt 'Type the name of the tenant to register the app in it')".Trim()
    if (-not [System.String]::Equals($typed, $Plan.TenantName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "What was typed does not match the tenant ($($Plan.TenantName)). Nothing was changed."
    }
}
