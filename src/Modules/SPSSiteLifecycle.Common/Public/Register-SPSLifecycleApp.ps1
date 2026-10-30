function Register-SPSLifecycleApp {
    <#
        .SYNOPSIS
        Registers the Microsoft Entra app that the tool signs in with: plans it, asks for a typed confirmation, then registers it with its
        permissions and its consent, and says what to put in the settings file.

        .DESCRIPTION
        In this order, and the tenant is changed only at the end:

        1. The inputs are checked: the tenant (the name of a tenant, never the Microsoft corporate tenants), the name of the app, the kind
           and the years of the certificate, and for the Certificate kind the folder that is given: the key folder, named after the app, is
           made in it, so it must not be there already (a folder, a file or a link: nothing is ever written in a place that is taken), and
           neither folder may be inside a repository or the folder of the tool, by what is written or by where it leads (a link is followed).
        2. The plan is shown as lines of information (see Format-SPSLifecycleAppPlan): the tenant, the app, the kind, the permissions with
           what the tool uses each for, the certificate, the roles that create the app and give the consent. -WhatIf stops here: nothing
           is asked and nothing is created.
        3. A person types the name of the tenant (see Confirm-SPSLifecycleAppRegistration), and, for the Certificate kind, the password of
           the private key, twice. An input that is redirected stops the function before it asks.
        4. The key folder is created, new, so that only the user can read it, and checked (the mode 700, or an access list for the account
           alone), and checked again where it really is: the tool does not go on when it is not as it must be. Then the app is registered
           by PnP.PowerShell (see Register-SPSLifecycleEntraApp): it signs in (a browser window, or a device code), stops when an app of
           that name exists, creates the app and runs the consent. The private key is restricted to the user in a finally, so that a run
           that is interrupted leaves it protected too.
        5. When the name is taken, which PnP.PowerShell says before it creates the app, the two files that it wrote (by their names) are
           removed, and the folder when it is empty. In every other failure the files are kept, a refusal of Microsoft Graph included,
           because only that message proves that no app was created, and the key may be the only copy of the one of an app that exists;
           the message says what to do. When the app was created, the files are checked (the certificate can be read and is the one that the
           app got, and the key file opens with the password, holds the private key and is the key of that certificate), the certificate
           may be added to the CurrentUser store (Windows), and the lines to paste in the settings file are shown.

        The password is never shown, logged or returned, and nothing that PnP.PowerShell writes on its streams or says in an error is passed
        on without what may be a secret taken out of it. For the Certificate kind the ID of the tenant is read from the public OpenID
        configuration of its domain (see Get-SPSLifecycleTenantId), because the certificate sign-in of the tool asks for it (TenantId): when
        it cannot be read this is a warning, and the lines for the settings file say where to find it. It returns the result: TenantName,
        ApplicationName, Kind, ClientId, and for the Certificate kind TenantId, Thumbprint, ExpiresOn, PfxPath, CerPath, KeyProtected and
        StoredInCertificateStore.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .PARAMETER ApplicationName
        The name of the app, and of the certificate files. Default: SPSSiteLifecycle.

        .PARAMETER Kind
        Interactive (a person signs in, no certificate: the default) or Certificate (the app signs in alone).

        .PARAMETER OutputFolder
        The folder in which the key folder is made (Certificate kind): the key goes in <OutputFolder>/<ApplicationName>, a new folder that only
        you can read. Default: .spssitelifecycle in the profile of the user.

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

    $keyFolder = ''
    $toolRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $script:ModuleRoot -Parent) -Parent) -Parent
    if ($isCertificate) {
        $requested = if ($OutputFolder) { $OutputFolder } else { Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)) -ChildPath '.spssitelifecycle' }
        $keyFolder = Resolve-SPSLifecycleAppFolder -Folder $requested -ApplicationName $ApplicationName -ToolRoot $toolRoot
    }

    $plan = Get-SPSLifecycleAppPlan -TenantName $TenantName -ApplicationName $ApplicationName -Kind $Kind -ValidYears $ValidYears -Folder $keyFolder -UseCertificateStore:$UseCertificateStore -DeviceLogin:$DeviceLogin -Now $Now
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
        $null = New-SPSLifecycleProtectedFolder -Path $keyFolder

        # Checked again now that it exists, where it really is: a link that was put in the way after the first check is seen here, before
        # anything is written in the folder.
        try {
            Assert-SPSLifecycleOutsideRepository -Path $keyFolder -ToolRoot $toolRoot
        }
        catch {
            $reason = $_.Exception.Message
            $null = Clear-SPSLifecycleKeyFolder -Folder $keyFolder -ApplicationName $ApplicationName -FolderOnly -Confirm:$false
            throw $reason
        }
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
            Write-Warning -Message "The registration was interrupted. The app '$ApplicationName' may have been created in the tenant: look for it in the Microsoft Entra admin center (App registrations), and delete it before you run the script again if it is there. The certificate files, if there are any, are in '$keyFolder', and were kept."
        }
    }

    $files = @(@($pfx, $cer) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($null -ne $failure) {
        $kindOfFailure = Get-SPSLifecycleAppFailureKind -Message $failure
        $removed = @()
        $notRemoved = @()
        $kept = @()
        if ($isCertificate) {
            if ($kindOfFailure -eq 'AppExists') {
                # The only failure that proves that no app was created: PnP.PowerShell says that the name is taken before it creates the app. Any other
                # message could come after the app was created, and the key that was written is then the only copy.
                $cleared = Clear-SPSLifecycleKeyFolder -Folder $keyFolder -ApplicationName $ApplicationName -Confirm:$false
                $removed = @($cleared.Removed)
                $notRemoved = @($cleared.NotRemoved)
            }
            else {
                $kept = $files
                if ($files.Count -eq 0) {
                    $null = Clear-SPSLifecycleKeyFolder -Folder $keyFolder -ApplicationName $ApplicationName -FolderOnly -Confirm:$false
                }
            }
        }

        throw (Format-SPSLifecycleAppFailure -Kind $kindOfFailure -Message $failure -Plan $plan -FilesRemoved $removed -FilesKept $kept -FilesNotRemoved $notRemoved)
    }

    if ($null -eq $record) {
        if ($isCertificate -and $files.Count -eq 0) {
            $null = Clear-SPSLifecycleKeyFolder -Folder $keyFolder -ApplicationName $ApplicationName -FolderOnly -Confirm:$false
        }

        $leftover = if ($files.Count -gt 0) { " The certificate files in '$keyFolder' were kept, because an app may exist that they belong to." } else { '' }
        throw "The registration gave nothing back: the sign-in was cancelled or did not complete, so no app was created as far as is known.$leftover Look for an app named '$ApplicationName' in the Microsoft Entra admin center (App registrations) before you run the script again."
    }

    $expires = $null
    $keyProtected = $false
    $stored = $false
    $tenantId = ''
    if ($isCertificate) {
        $created = "The app '$ApplicationName' was created (client ID $($record.ClientId)), but"
        $again = 'Delete the app in the Microsoft Entra admin center (App registrations), and run the script again.'
        foreach ($file in $pfx, $cer) {
            if (-not (Test-Path -LiteralPath $file)) {
                throw "$created PnP.PowerShell did not write '$file': the certificate that the app got has no file here, and there is no key to sign in with. $again"
            }
        }

        $info = Read-SPSLifecycleCertificateInfo -Path $cer
        if ($null -eq $info) {
            throw "$created the certificate file '$cer' cannot be read as a certificate, so it cannot be told whether it is the one that the app got. $again"
        }

        if (-not [System.String]::Equals($info.Thumbprint, $record.Thumbprint, [System.StringComparison]::Ordinal)) {
            throw "$created the certificate in '$cer' is not the one that the app got (thumbprint $($record.Thumbprint)): the key that was written is not the key of the app. $again"
        }

        $key = Read-SPSLifecycleKeyFile -Path $pfx -Password $password
        if ($null -eq $key) {
            throw "$created the key file '$pfx' cannot be opened with the password that was typed, or is not a .pfx file, so there is no key to sign in with. $again"
        }

        if (-not $key.HasPrivateKey -or -not [System.String]::Equals($key.Thumbprint, $record.Thumbprint, [System.StringComparison]::Ordinal)) {
            throw "$created the key file '$pfx' does not hold the private key of the certificate that the app got (thumbprint $($record.Thumbprint)), so there is no key to sign in with. $again"
        }

        $expires = $info.NotAfter
        $keyProtected = Protect-SPSLifecyclePrivateKey -Path $pfx
        try {
            $tenantId = Get-SPSLifecycleTenantId -TenantDomain $plan.TenantDomain
        }
        catch {
            Write-Warning -Message "The ID of the tenant could not be read ($($_.Exception.Message.Trim().TrimEnd('.'))): read it on the Overview page of the Microsoft Entra admin center, and put it in TenantId of the settings file."
        }

        if ($plan.Certificate.Store -eq 'CurrentUser') {
            try {
                $storedThumbprint = Add-SPSLifecycleCertificateToStore -Path $pfx -Password $password
                if ([System.String]::Equals("$storedThumbprint", $record.Thumbprint, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $stored = $true
                }
                else {
                    Write-Warning -Message "The certificate that was added to the CurrentUser store is not the one that the app got. Use the .pfx file, and remove what was added from the store by hand."
                }
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
        TenantId                 = $tenantId
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
