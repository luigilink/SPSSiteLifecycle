function Format-SPSLifecycleAppResult {
    <#
        .SYNOPSIS
        Says what was registered and what to put in the settings file, in lines.

        .DESCRIPTION
        The lines that the setup script shows at the end: the app and its ID, the lines to paste in the settings file (no secret is ever
        written), and the next step. For the Certificate kind they are the way to sign in, the ID of the tenant (or where to read it), and
        the certificate: the thumbprint when it is in the store of Windows, and the file otherwise, with the variable that may hold its
        password; and the thumbprint, the date it ends and where the files are.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .PARAMETER Result
        What the registration gave: ClientId, and for the Certificate kind TenantId, Thumbprint, ExpiresOn, PfxPath, CerPath, KeyProtected and
        StoredInCertificateStore.

        .EXAMPLE
        Format-SPSLifecycleAppResult -Plan $plan -Result $result
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Result
    )

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add("The app '$($Plan.ApplicationName)' is registered in the tenant $($Plan.TenantName), and the consent was given.")
    $lines.Add('Put this in your settings file:')
    if ($Plan.Kind -eq 'Certificate') {
        $lines.Add("    TenantName     = '$($Plan.TenantName)'")
        $lines.Add("    ClientId       = '$($Result.ClientId)'")
        $lines.Add("    Authentication = 'Certificate'")
        $tenantId = if ($Result.TenantId) { $Result.TenantId } else { '<the Tenant ID of the Overview page of the Microsoft Entra admin center>' }
        $lines.Add("    TenantId       = '$tenantId'")
        if ($Result.StoredInCertificateStore) {
            $lines.Add("    CertificateThumbprint = '$($Result.Thumbprint)'")
        }
        else {
            $lines.Add("    CertificatePath = '$($Result.PfxPath)'")
            $lines.Add("    # CertificatePasswordVariable = 'SPSSITELIFECYCLE_PFX_PASSWORD'   # the environment variable that holds the password; without it the tool asks for it")
        }
    }
    else {
        $lines.Add("    TenantName = '$($Plan.TenantName)'")
        $lines.Add("    ClientId   = '$($Result.ClientId)'")
    }

    if ($Plan.Kind -eq 'Certificate') {
        $until = $Result.ExpiresOn.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $lines.Add("The certificate has the thumbprint $($Result.Thumbprint), and it ends on ${until}: add a new certificate to the app before then (see the App-Registration page of the wiki).")
        $lines.Add("    Private key (.pfx): $($Result.PfxPath)")
        $lines.Add("    Public key (.cer):  $($Result.CerPath)")
        if ($Result.KeyProtected) {
            $lines.Add('The private key can be read by your account only. Keep it, and its password, in a safe place: nobody can give them back.')
        }
        else {
            $lines.Add('The private key could not be restricted to your account: do it by hand, and keep it, and its password, in a safe place.')
        }

        if ($Result.StoredInCertificateStore) {
            $lines.Add("The certificate is also in the CurrentUser store of Windows: Cert:\CurrentUser\My\$($Result.Thumbprint).")
        }

        $lines.Add('A run that nobody watches (a scheduled task) signs in with it: the tool reads its dates before it signs in, stops when it has expired and warns 30 days before it ends. The Act phase with Execute still needs a person to type its confirmation.')
    }
    else {
        $lines.Add('Next: run the Scan (pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile <your settings file> -Phase Scan). The account that signs in has to be a SharePoint administrator.')
    }

    $lines.Add('Nothing secret was written to a file of the repository or to the settings.')
    $lines.ToArray()
}
