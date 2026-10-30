function Register-SPSLifecycleEntraApp {
    <#
        .SYNOPSIS
        Registers the app in Microsoft Entra ID, with its permissions and its consent, and gives its client ID. This changes the tenant.

        .DESCRIPTION
        One operation, with the cmdlet of PnP.PowerShell that matches the kind of the plan: Register-PnPEntraIDAppForInteractiveLogin (an
        app that a person signs in with, with delegated permissions and no certificate), or Register-PnPEntraIDApp (an app that signs in
        alone, with application permissions and a self-signed certificate that the cmdlet makes and writes to the folder of the plan, for
        the number of years of the plan, protected by the password). Both sign in by themselves (a browser window, or a device code), ask
        Microsoft Graph whether an app of that name exists and stop if it does, create the app, and run the consent. The target is checked
        first (see Assert-SPSLifecycleAppTarget): never a tenant that the tool refuses.

        The folder is always given: without it the cmdlet writes the key in the current folder, which can be a repository. The certificate
        store is not asked of the cmdlet: it adds the certificate before it knows that the app can be created, and the setup script adds
        it itself, afterwards.

        It gives ClientId, and Thumbprint (empty for the interactive kind), or nothing when the cmdlet reported nothing (the sign-in was
        cancelled). It never gives the other things that the cmdlet reports, the whole certificate with its private key (Base64Encoded) above all.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .PARAMETER CertificatePassword
        The password of the private key (Certificate kind).

        .EXAMPLE
        Register-SPSLifecycleEntraApp -Plan $plan -CertificatePassword $password
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter()]
        [AllowNull()]
        [System.Security.SecureString]
        $CertificatePassword = $null
    )

    Assert-SPSLifecycleAppTarget -TenantName $Plan.TenantName -ApplicationName $Plan.ApplicationName
    Assert-SPSLifecyclePnPModule

    if (-not $PSCmdlet.ShouldProcess("$($Plan.ApplicationName) in $($Plan.TenantDomain)", 'Register the app in Microsoft Entra ID')) {
        return
    }

    $arguments = @{
        ApplicationName = $Plan.ApplicationName
        Tenant          = $Plan.TenantDomain
    }
    $graph = [string[]]@($Plan.Permissions | Where-Object { $_.Resource -eq 'Graph' } | ForEach-Object { $_.Name })
    $sharePoint = [string[]]@($Plan.Permissions | Where-Object { $_.Resource -eq 'SharePoint' } | ForEach-Object { $_.Name })
    if ($Plan.SignIn -eq 'DeviceCode') {
        $arguments['DeviceLogin'] = $true
    }

    try {
        if ($Plan.Kind -eq 'Certificate') {
            $arguments['GraphApplicationPermissions'] = $graph
            $arguments['SharePointApplicationPermissions'] = $sharePoint
            $arguments['OutPath'] = $Plan.Certificate.Folder
            $arguments['ValidYears'] = $Plan.Certificate.ValidYears
            $arguments['CertificatePassword'] = $CertificatePassword
            $output = @(Register-PnPEntraIDApp @arguments -ErrorAction Stop)
        }
        else {
            $arguments['GraphDelegatePermissions'] = $graph
            $arguments['SharePointDelegatePermissions'] = $sharePoint
            $output = @(Register-PnPEntraIDAppForInteractiveLogin @arguments -ErrorAction Stop)
        }
    }
    catch {
        throw $_.Exception.Message
    }

    $record = @($output | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['AzureAppId/ClientId'] } | Select-Object -Last 1)
    if ($record.Count -eq 0) {
        return
    }

    $clientText = "$($record[0].PSObject.Properties['AzureAppId/ClientId'].Value)"
    $clientId = [System.Guid]::Empty
    if (-not [System.Guid]::TryParse($clientText, [ref]$clientId) -or $clientId -eq [System.Guid]::Empty) {
        throw "The registration returned an unexpected result: '$(ConvertTo-SPSLifecycleVisibleText -Text $clientText -AsciiOnly)' is not the client ID of an app."
    }

    $thumbprint = ''
    if ($Plan.Kind -eq 'Certificate') {
        $property = $record[0].PSObject.Properties['Certificate Thumbprint']
        $text = if ($null -ne $property) { "$($property.Value)" } else { '' }
        if (-not [System.Text.RegularExpressions.Regex]::IsMatch($text, '\A[0-9A-Fa-f]{40}\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            throw 'The registration returned an unexpected result: no thumbprint of the certificate.'
        }

        $thumbprint = $text.ToUpperInvariant()
    }

    [PSCustomObject]@{
        ClientId   = $clientId.ToString()
        Thumbprint = $thumbprint
    }
}
