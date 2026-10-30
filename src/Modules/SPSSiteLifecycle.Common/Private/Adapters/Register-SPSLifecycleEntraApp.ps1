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

        This is the last barrier before the tenant, so it trusts nothing of the plan but what it can rebuild: the plan is made again from
        the tenant, the name, the kind, the folder, the years and the sign-in (see Get-SPSLifecycleAppPlan), and the plan that was given
        must be that plan (the domain that the sign-in goes to, the kind and the permissions): a plan that names one tenant and another
        domain, or other permissions, is refused, and what goes to the cmdlet is what the tool would have planned.

        It gives ClientId, and Thumbprint (empty for the interactive kind), or nothing when the cmdlet reported nothing (the sign-in was
        cancelled). It never gives the other things that the cmdlet reports, the whole certificate with its private key (Base64Encoded) above all.
        What the cmdlet writes on the warning, verbose, debug and information streams is not passed on, and the text of a failure is told only
        with what may be a secret taken out of it (see ConvertTo-SPSLifecycleSecretFreeText), the original error being taken out of $Error.

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

    $isCertificate = [System.String]::Equals("$($Plan.Kind)", 'Certificate', [System.StringComparison]::Ordinal)
    $years = if ($isCertificate) { [System.Int32]$Plan.Certificate.ValidYears } else { 2 }
    $folder = if ($isCertificate) { "$($Plan.Certificate.Folder)" } else { '' }
    $canonical = Get-SPSLifecycleAppPlan -TenantName $Plan.TenantName -ApplicationName $Plan.ApplicationName -Kind "$($Plan.Kind)" -ValidYears $years -Folder $folder -DeviceLogin:([System.String]::Equals("$($Plan.SignIn)", 'DeviceCode', [System.StringComparison]::Ordinal))
    $given = @($Plan.Permissions | ForEach-Object { "$($_.Resource)|$($_.Name)|$($_.Type)" } | Sort-Object)
    $expected = @($canonical.Permissions | ForEach-Object { "$($_.Resource)|$($_.Name)|$($_.Type)" } | Sort-Object)
    if (-not [System.String]::Equals("$($Plan.TenantDomain)", $canonical.TenantDomain, [System.StringComparison]::Ordinal) -or ($given -join ',') -ne ($expected -join ',')) {
        throw "The plan is not the plan of the tenant '$($canonical.TenantName)' (the domain of the sign-in is '$(ConvertTo-SPSLifecycleVisibleText -Text "$($Plan.TenantDomain)" -AsciiOnly)', and the permissions are not the ones of the $($canonical.Kind) kind): nothing was registered."
    }

    $Plan = $canonical
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
            $output = @(Register-PnPEntraIDApp @arguments -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null)
        }
        else {
            $arguments['GraphDelegatePermissions'] = $graph
            $arguments['SharePointDelegatePermissions'] = $sharePoint
            $output = @(Register-PnPEntraIDAppForInteractiveLogin @arguments -ErrorAction Stop 3>$null 4>$null 5>$null 6>$null)
        }
    }
    catch {
        $original = $_
        $secrets = @()
        if ($null -ne $CertificatePassword) {
            $secrets = @([System.Net.NetworkCredential]::new('', $CertificatePassword).Password)
        }

        $message = ConvertTo-SPSLifecycleSecretFreeText -Text $original.Exception.Message -Secret $secrets

        # The $Error of a module is not the one of the session, which is the one that a person reads, so it is the global one that is cleaned,
        # and the record that it keeps is not always the object that the catch got, so it is found by its exception.
        for ($index = $global:Error.Count - 1; $index -ge 0; $index--) {
            if ([System.Object]::ReferenceEquals($global:Error[$index].Exception, $original.Exception)) {
                $global:Error.RemoveAt($index)
            }
        }

        throw $message
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
