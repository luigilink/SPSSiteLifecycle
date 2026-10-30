#Requires -Version 7.4

<#
    .SYNOPSIS
    Registers the Microsoft Entra app that SPSSiteLifecycle signs in with, in one guided run: the plan first, then a typed confirmation, then the app, its permissions and its consent.

    .DESCRIPTION
    PnP.PowerShell no longer brings an app of its own, so every run of the tool needs an app registration in your tenant. This script
    makes it (with Register-PnPEntraIDAppForInteractiveLogin, or Register-PnPEntraIDApp for a certificate) and tells you what to put in
    the settings file. See the App-Registration page of the wiki, which also says how to do it by hand.

    1. It shows the plan: the tenant, the name of the app, the kind, each permission with what the tool uses it for, the certificate, and the
       roles that create the app and give the consent. With -WhatIf it stops there, and nothing is asked or created.
    2. A person types the name of the tenant. For a certificate, the password of the private key is typed too, twice, and never shown or
       saved. A tenant of Microsoft is refused, and so is a folder for the key that is inside a repository.
    3. PnP.PowerShell signs in (a browser window, or a device code), stops when an app of that name exists, creates the app and runs the
       consent. Giving consent to application permissions of Microsoft Graph needs a Privileged Role Administrator or a Global Administrator.
    4. It shows the lines for the settings file. A certificate is kept in a folder that only you can read, never in the repository, and
       never written in the settings.

    Its exit code is 0 when the app was registered (or with -WhatIf), and 1 on any error, after a message that says what was and was not
    created and what to do. The script writes what it did as information (shown by default; -InformationAction SilentlyContinue hides it).

    .PARAMETER TenantName
    The name of your tenant: contoso for contoso.sharepoint.com.

    .PARAMETER ApplicationName
    The name of the app in Microsoft Entra ID, which is also the name of the certificate files. Default: SPSSiteLifecycle.

    .PARAMETER Kind
    Interactive (a person signs in, with no certificate: the default, and what the tool uses today) or Certificate (the app signs in alone,
    for a run that nobody watches).

    .PARAMETER OutputFolder
    Certificate only: where the private key (.pfx) and the certificate (.cer) go. It is created so that only you can read it. It must be
    outside any repository and outside the folder of the tool. Default: .spssitelifecycle in your profile.

    .PARAMETER ValidYears
    Certificate only: the number of years that the certificate is valid, 1 to 30. Default: 2.

    .PARAMETER UseCertificateStore
    Certificate only, Windows only: also adds the certificate to your CurrentUser store, to sign in with its thumbprint.

    .PARAMETER DeviceLogin
    Signs in with a device code instead of a browser window, for a machine that has no browser.

    .EXAMPLE
    pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso -WhatIf

    .EXAMPLE
    pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso

    .EXAMPLE
    pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso -Kind Certificate -ValidYears 2
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $TenantName,

    [Parameter()]
    [System.String]
    $ApplicationName,

    [Parameter()]
    [ValidateSet('Interactive', 'Certificate')]
    [System.String]
    $Kind,

    [Parameter()]
    [System.String]
    $OutputFolder,

    [Parameter()]
    [ValidateRange(1, 30)]
    [System.Int32]
    $ValidYears,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $UseCertificateStore,

    [Parameter()]
    [System.Management.Automation.SwitchParameter]
    $DeviceLogin
)

$ErrorActionPreference = 'Stop'

# What the registration did is information, shown unless the person who runs it asks otherwise.
$informationAction = if ($PSBoundParameters.ContainsKey('InformationAction')) { $InformationPreference } else { 'Continue' }

try {
    # A copy of the module that is already loaded from this very folder is used as it is.
    $manifest = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1')).ProviderPath
    $moduleFolder = [System.IO.Path]::GetDirectoryName($manifest)
    $loaded = @(Get-Module -Name 'SPSSiteLifecycle.Common') | Where-Object { [System.String]::Equals($_.ModuleBase, $moduleFolder, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $loaded) {
        $loaded = Import-Module -Name $manifest -Force -PassThru
    }

    # Only what the person gave is passed on, so that the defaults are the module's, and so that a parameter that does not go with the kind is seen.
    $arguments = @{ InformationAction = $informationAction }
    foreach ($name in 'TenantName', 'ApplicationName', 'Kind', 'OutputFolder', 'ValidYears', 'UseCertificateStore', 'DeviceLogin') {
        if ($PSBoundParameters.ContainsKey($name)) {
            $arguments[$name] = $PSBoundParameters[$name]
        }
    }

    if ($WhatIfPreference) {
        $arguments['WhatIf'] = $true
    }

    $null = & $loaded.ExportedCommands['Register-SPSLifecycleApp'] @arguments
    exit 0
}
catch {
    Write-Verbose -Message "$($_.ScriptStackTrace)"
    Write-Error -Message "SPSSiteLifecycle app registration stopped: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
