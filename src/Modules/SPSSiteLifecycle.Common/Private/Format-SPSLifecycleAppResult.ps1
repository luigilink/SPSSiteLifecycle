function Format-SPSLifecycleAppResult {
    <#
        .SYNOPSIS
        Says what was registered and what to put in the settings file, in lines.

        .DESCRIPTION
        The lines that the setup script shows at the end: the app and its ID, the lines to paste in the settings file (the tenant and the
        client ID: no secret is ever written), for the Certificate kind the thumbprint, the date it ends and where the files are, and the
        next step. The certificate settings of the sign-in come with the issue of the certificate sign-in: until then the Scan signs in
        with the client ID, and a certificate is the preparation of an unattended run.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .PARAMETER Result
        What the registration gave: ClientId, and for the Certificate kind Thumbprint, ExpiresOn, PfxPath, CerPath, KeyProtected and
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
    $lines.Add("    TenantName = '$($Plan.TenantName)'")
    $lines.Add("    ClientId   = '$($Result.ClientId)'")

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

        $lines.Add('The sign-in of the tool with this certificate is not available in this version: the Scan and the Act phase sign in with the client ID, as a person.')
    }
    else {
        $lines.Add('Next: run the Scan (pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile <your settings file> -Phase Scan). The account that signs in has to be a SharePoint administrator.')
    }

    $lines.Add('Nothing secret was written to a file of the repository or to the settings.')
    $lines.ToArray()
}
