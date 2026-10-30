function Confirm-SPSLifecycleAct {
    <#
        .SYNOPSIS
        Asks a person to confirm an Execute run: the name of the tenant, then a phrase that carries the number of actions.

        .DESCRIPTION
        This is the barrier before any change (D2, D6), and it is typed, not set: the banner has been shown, and a person types
        the name of the tenant (in any case, spaces around it do not count), then the phrase of the plan (DELETE n, ARCHIVE n or
        APPLY n, exactly, spaces around it do not count). Anything else stops the tool, with nothing changed, and asks nothing
        more. The tool also stops, before it asks anything, when the input is redirected: a confirmation that a script gave is
        not a person's.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleActPlan).

        .PARAMETER Setting
        The effective settings for the Act phase.

        .EXAMPLE
        Confirm-SPSLifecycleAct -Plan $plan -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    if (Test-SPSLifecycleInputRedirected) {
        throw 'The input is redirected, so no person can type the confirmation, and the Act phase cannot run with Execute on. Nothing was changed.'
    }

    $tenant = "$($Setting.TenantName)".Trim()
    $typedTenant = "$(Read-Host -Prompt 'Type the name of the tenant to go on')".Trim()
    if (-not [System.String]::Equals($typedTenant, $tenant, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "What was typed does not match the tenant ($tenant). Nothing was changed."
    }

    $typedPhrase = "$(Read-Host -Prompt "Type $($Plan.Phrase) to start: the tenant is changed as soon as you do")".Trim()
    if (-not [System.String]::Equals($typedPhrase, $Plan.Phrase, [System.StringComparison]::Ordinal)) {
        throw "What was typed is not the phrase '$($Plan.Phrase)'. Nothing was changed."
    }
}
