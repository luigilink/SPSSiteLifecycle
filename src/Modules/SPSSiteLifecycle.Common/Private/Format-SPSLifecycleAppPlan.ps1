function Format-SPSLifecycleAppPlan {
    <#
        .SYNOPSIS
        Says the plan of the registration of the app in words: the lines that the setup script shows before it asks for anything.

        .DESCRIPTION
        One line for each thing, with no wrapping, so that a person can read it and a test can find each permission, its reason, the files
        and the roles. It says first that nothing has been changed yet.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .EXAMPLE
        Format-SPSLifecycleAppPlan -Plan $plan | ForEach-Object { Write-Information -MessageData $_ }
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan
    )

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add('App registration plan (nothing has been changed yet):')
    $lines.Add("  Tenant:       $($Plan.TenantName) ($($Plan.TenantDomain))")
    $lines.Add("  App name:     $($Plan.ApplicationName)")
    if ($Plan.Kind -eq 'Certificate') {
        $lines.Add('  Kind:         Certificate: the app signs in alone, with a certificate, for a run that nobody watches.')
    }
    else {
        $lines.Add('  Kind:         Interactive: a person signs in to run the tool, and there is no certificate.')
    }

    if ($Plan.SignIn -eq 'DeviceCode') {
        $lines.Add('  Sign-in:      a device code is shown, for a machine without a browser: it is entered on another device, once to sign in and once more for the consent.')
    }
    else {
        $lines.Add('  Sign-in:      a browser window opens, once to sign in and once more for the consent.')
    }

    $type = if ($Plan.Kind -eq 'Certificate') { 'Application' } else { 'Delegated' }
    $lines.Add("  Permissions:  $type permissions requested, each with what the tool uses it for:")
    foreach ($permission in $Plan.Permissions) {
        $lines.Add("    - $($permission.Resource) $($permission.Name) ($($permission.UsedBy)): $($permission.Reason)")
    }

    if ($null -ne $Plan.Certificate) {
        $until = $Plan.Certificate.ExpiresOn.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $years = if ($Plan.Certificate.ValidYears -eq 1) { '1 year' } else { "$($Plan.Certificate.ValidYears) years" }
        $lines.Add("  Certificate:  self-signed, valid $years (until about $until), protected by a password that is asked next.")
        $lines.Add("    Private key: $($Plan.Certificate.PfxPath) (only you can read it: the folder and the file are restricted to your account)")
        $lines.Add("    Public key:  $($Plan.Certificate.CerPath)")
        if ($Plan.Certificate.Store -eq 'CurrentUser') {
            $lines.Add('    It is also added to the CurrentUser certificate store of Windows, so that it can be used by its thumbprint.')
        }
    }

    $lines.Add("  Roles:        to create the app, $($Plan.CreatorRoles). To give the consent, $($Plan.ConsentRoles).")
    $lines.Add('                When the consent cannot be given, the app is created all the same: ask one of those administrators to grant it in the Microsoft Entra admin center (App registrations, the app, API permissions, Grant admin consent).')
    $lines.Add('  Not done:     no secret is written to the settings file or to the repository, and the tool touches no site.')

    $lines.ToArray()
}
