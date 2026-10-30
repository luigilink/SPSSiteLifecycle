function Register-SPSLifecycleApp {
    <#
        .SYNOPSIS
        Registers the Microsoft Entra app that the tool signs in with: plans it, asks for a typed confirmation, then registers it with its
        permissions and its consent, and says what to put in the settings file.

        .DESCRIPTION
        In this order, and the tenant is changed only at the end:

        1. The inputs are checked: the tenant (the name of a tenant, never the Microsoft corporate tenants), the name of the app, the kind
           and the years of the certificate, and for the Certificate kind the folder of the files (outside any repository and the folder of
           the tool, with no key or certificate of that name in it).
        2. The plan is shown as lines of information (see Format-SPSLifecycleAppPlan): the tenant, the app, the kind, the permissions with
           what the tool uses each for, the certificate, the roles that create the app and give the consent. -WhatIf stops here: nothing
           is asked and nothing is created.
        3. A person types the name of the tenant (see Confirm-SPSLifecycleAppRegistration), and, for the Certificate kind, the password of
           the private key, twice. An input that is redirected stops the function before it asks.
        4. The folder of the files is created so that only the user can read it, and the app is registered by PnP.PowerShell (see
           Register-SPSLifecycleEntraApp): it signs in (a browser window, or a device code), stops when an app of that name exists, creates
           the app and runs the consent. The private key is restricted to the user in a finally, so that a run that is interrupted
           leaves it protected too.
        5. When no app was created (the name is taken, the account is not allowed) the files that the run wrote are removed, and in every
           other failure they are kept, because the key may be the one of an app that exists; the message says what to do. When the app was
           created, the files and the certificate are checked, the certificate may be added to the CurrentUser store (Windows), and the
           lines to paste in the settings file are shown.

        The password is never shown, logged or returned. It returns the result: TenantName, ApplicationName, Kind, ClientId, and for the
        Certificate kind Thumbprint, ExpiresOn, PfxPath, CerPath, KeyProtected and StoredInCertificateStore.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .PARAMETER ApplicationName
        The name of the app, and of the certificate files. Default: SPSSiteLifecycle.

        .PARAMETER Kind
        Interactive (a person signs in, no certificate: the default) or Certificate (the app signs in alone).

        .PARAMETER OutputFolder
        The folder of the certificate files (Certificate kind). Default: .spssitelifecycle in the profile of the user.

        .PARAMETER ValidYears
        The number of years that the certificate is valid, 1 to 30 (Certificate kind). Default: 2.

        .PARAMETER UseCertificateStore
        Also adds the certificate to the CurrentUser store (Windows, Certificate kind).

        .PARAMETER DeviceLogin
        Signs in with a device code, for a machine without a browser.

        .PARAMETER Now
        The time of the run, in UTC, for the date the certificate ends in the plan. Default: now.

        .EXAMPLE
        Register-SPSLifecycleApp -TenantName contoso -WhatIf

        .EXAMPLE
        Register-SPSLifecycleApp -TenantName contoso -Kind Certificate -InformationAction Continue
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TenantName,

        [Parameter()]
        [System.String]
        $ApplicationName = 'SPSSiteLifecycle',

        [Parameter()]
        [ValidateSet('Interactive', 'Certificate')]
        [System.String]
        $Kind = 'Interactive',

        [Parameter()]
        [System.String]
        $OutputFolder = '',

        [Parameter()]
        [ValidateRange(1, 30)]
        [System.Int32]
        $ValidYears = 2,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $UseCertificateStore,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $DeviceLogin,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    Assert-SPSLifecycleAppTarget -TenantName $TenantName -ApplicationName $ApplicationName

    $isCertificate = $Kind -eq 'Certificate'
    if (-not $isCertificate) {
        foreach ($name in 'OutputFolder', 'ValidYears', 'UseCertificateStore') {
            if ($PSBoundParameters.ContainsKey($name)) {
                throw "-$name is for the Certificate kind: the Interactive kind has no certificate, so there is nothing to give it to."
            }
        }
    }
    elseif ($UseCertificateStore -and -not (Test-SPSLifecycleWindowsPlatform)) {
        throw '-UseCertificateStore is available on Windows only: macOS and Linux have no certificate store, and use the .pfx file.'
    }

    $folder = ''
    if ($isCertificate) {
        $requested = if ($OutputFolder) { $OutputFolder } else { Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)) -ChildPath '.spssitelifecycle' }
        $toolRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $script:ModuleRoot -Parent) -Parent) -Parent
        $folder = Resolve-SPSLifecycleAppFolder -Folder $requested -ApplicationName $ApplicationName -ToolRoot $toolRoot
    }

    $plan = Get-SPSLifecycleAppPlan -TenantName $TenantName -ApplicationName $ApplicationName -Kind $Kind -ValidYears $ValidYears -Folder $folder -UseCertificateStore:$UseCertificateStore -DeviceLogin:$DeviceLogin -Now $Now
    foreach ($line in Format-SPSLifecycleAppPlan -Plan $plan) {
        Write-Information -MessageData $line
    }

    if (-not $PSCmdlet.ShouldProcess("the tenant $($plan.TenantName)", "Register the app $($plan.ApplicationName)")) {
        return
    }

    Assert-SPSLifecyclePnPModule
    Confirm-SPSLifecycleAppRegistration -Plan $plan

    $password = $null
    $pfx = ''
    $cer = ''
    if ($isCertificate) {
        $pfx = $plan.Certificate.PfxPath
        $cer = $plan.Certificate.CerPath
        $password = Read-SPSLifecycleCertificatePassword
        $null = New-SPSLifecycleProtectedFolder -Path $folder
    }

    $record = $null
    $failure = $null
    $finished = $false
    try {
        try {
            $record = Register-SPSLifecycleEntraApp -Plan $plan -CertificatePassword $password
        }
        catch {
            $failure = $_.Exception.Message
        }

        $finished = $true
    }
    finally {
        # Ctrl+C is not caught by a catch, so the key is restricted here, whatever became of the registration.
        if ($isCertificate) {
            $null = Protect-SPSLifecyclePrivateKey -Path $pfx
        }

        if (-not $finished) {
            Write-Warning -Message "The registration was interrupted. The app '$ApplicationName' may have been created in the tenant: look for it in the Microsoft Entra admin center (App registrations), and delete it before you run the script again if it is there. The certificate files, if there are any, are in '$folder', and were kept."
        }
    }

    $files = @(@($pfx, $cer) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($null -ne $failure) {
        $kindOfFailure = Get-SPSLifecycleAppFailureKind -Message $failure
        $removed = [System.Collections.Generic.List[System.String]]::new()
        $notRemoved = [System.Collections.Generic.List[System.String]]::new()
        $kept = @()
        if ($kindOfFailure -eq 'AppExists' -or $kindOfFailure -eq 'Forbidden') {
            foreach ($file in $files) {
                try {
                    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                    $removed.Add($file)
                }
                catch {
                    $notRemoved.Add($file)
                }
            }
        }
        else {
            $kept = $files
        }

        throw (Format-SPSLifecycleAppFailure -Kind $kindOfFailure -Message $failure -Plan $plan -FilesRemoved $removed.ToArray() -FilesKept $kept -FilesNotRemoved $notRemoved.ToArray())
    }

    if ($null -eq $record) {
        $leftover = if ($files.Count -gt 0) { " The certificate files in '$folder' were kept, because an app may exist that they belong to." } else { '' }
        throw "The registration gave nothing back: the sign-in was cancelled or did not complete, so no app was created as far as is known.$leftover Look for an app named '$ApplicationName' in the Microsoft Entra admin center (App registrations) before you run the script again."
    }

    $expires = $null
    $keyProtected = $false
    $stored = $false
    if ($isCertificate) {
        foreach ($file in $pfx, $cer) {
            if (-not (Test-Path -LiteralPath $file)) {
                throw "The app '$ApplicationName' was created (client ID $($record.ClientId)), but PnP.PowerShell did not write '$file': the certificate that the app got has no file here, and there is no key to sign in with. Delete the app in the Microsoft Entra admin center (App registrations), and run the script again."
            }
        }

        $info = Read-SPSLifecycleCertificateInfo -Path $cer
        if ($null -ne $info -and -not [System.String]::Equals($info.Thumbprint, $record.Thumbprint, [System.StringComparison]::Ordinal)) {
            throw "The app '$ApplicationName' was created (client ID $($record.ClientId)), but the certificate in '$cer' is not the one that the app got (thumbprint $($record.Thumbprint)): the key that was written is not the key of the app. Delete the app in the Microsoft Entra admin center (App registrations), and run the script again."
        }

        $expires = if ($null -ne $info) { $info.NotAfter } else { $plan.Certificate.ExpiresOn }
        $keyProtected = Protect-SPSLifecyclePrivateKey -Path $pfx
        if ($plan.Certificate.Store -eq 'CurrentUser') {
            try {
                $null = Add-SPSLifecycleCertificateToStore -Path $pfx -Password $password
                $stored = $true
            }
            catch {
                Write-Warning -Message "The certificate could not be added to the CurrentUser store ($($_.Exception.Message.Trim().TrimEnd('.'))). Use the .pfx file, or import it by hand."
            }
        }
    }

    $result = [PSCustomObject][ordered]@{
        TenantName               = $plan.TenantName
        ApplicationName          = $plan.ApplicationName
        Kind                     = $plan.Kind
        ClientId                 = $record.ClientId
        Thumbprint               = $record.Thumbprint
        ExpiresOn                = $expires
        PfxPath                  = $pfx
        CerPath                  = $cer
        KeyProtected             = $keyProtected
        StoredInCertificateStore = $stored
    }

    foreach ($line in Format-SPSLifecycleAppResult -Plan $plan -Result $result) {
        Write-Information -MessageData $line
    }

    $result
}
