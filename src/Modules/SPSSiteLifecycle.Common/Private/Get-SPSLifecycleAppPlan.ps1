function Get-SPSLifecycleAppPlan {
    <#
        .SYNOPSIS
        Builds the plan of the registration of the Microsoft Entra app: what the setup script is going to do, before it does anything.

        .DESCRIPTION
        The plan is data, and Format-SPSLifecycleAppPlan says it in words. It names the tenant (in lowercase) and the domain that the
        sign-in goes to (<tenant>.onmicrosoft.com), the application, the kind of app, how the person signs in, the permissions with their
        reasons (see Get-SPSLifecycleAppPermission), the certificate for the Certificate kind (its validity, the date it ends, the files and
        whether it also goes to the certificate store of the user), and the roles that create the app and give the consent (from
        Microsoft Learn: an Application Administrator cannot consent to the application permissions of Microsoft Graph).

        The function checks nothing about the names: see Assert-SPSLifecycleAppTarget and Resolve-SPSLifecycleAppFolder, which stop the
        script before the plan is shown.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .PARAMETER ApplicationName
        The name of the app in Microsoft Entra ID, which is also the name of the certificate files.

        .PARAMETER Kind
        Interactive (a person signs in, no certificate) or Certificate (the app signs in alone).

        .PARAMETER ValidYears
        The number of years that the certificate is valid. Default: 2.

        .PARAMETER Folder
        The folder of the certificate files: needed for the Certificate kind.

        .PARAMETER UseCertificateStore
        Also puts the certificate in the CurrentUser store (Windows).

        .PARAMETER DeviceLogin
        Signs in with a device code instead of a browser window.

        .PARAMETER Now
        The time of the run, in UTC. Default: now.

        .EXAMPLE
        Get-SPSLifecycleAppPlan -TenantName contoso -ApplicationName SPSSiteLifecycle -Kind Interactive
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TenantName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ApplicationName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Interactive', 'Certificate')]
        [System.String]
        $Kind,

        [Parameter()]
        [System.Int32]
        $ValidYears = 2,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $Folder = '',

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

    $tenant = $TenantName.Trim().ToLowerInvariant()
    $permissions = @(Get-SPSLifecycleAppPermission | Where-Object { [System.String]::Equals($_.Kind, $Kind, [System.StringComparison]::Ordinal) })

    if ($Kind -eq 'Certificate' -and -not $Folder) {
        throw 'The folder of the certificate files is not given, so the plan cannot say where the private key goes.'
    }

    $certificate = if ($Kind -eq 'Certificate') {
        [PSCustomObject][ordered]@{
            ValidYears = $ValidYears
            ExpiresOn  = (ConvertTo-SPSLifecycleUtcDateTime -Value $Now).Date.AddYears($ValidYears)
            Folder     = $Folder
            PfxPath    = Join-Path -Path $Folder -ChildPath "$ApplicationName.pfx"
            CerPath    = Join-Path -Path $Folder -ChildPath "$ApplicationName.cer"
            Store      = if ($UseCertificateStore) { 'CurrentUser' } else { 'None' }
        }
    }
    else {
        $null
    }

    $consentRoles = if ($Kind -eq 'Certificate') {
        'Privileged Role Administrator or Global Administrator: an Application Administrator or a Cloud Application Administrator is not enough to consent to the application permissions of Microsoft Graph'
    }
    else {
        'Application Administrator, Cloud Application Administrator, Privileged Role Administrator or Global Administrator, for delegated permissions'
    }

    [PSCustomObject][ordered]@{
        TenantName      = $tenant
        TenantDomain    = "$tenant.onmicrosoft.com"
        ApplicationName = $ApplicationName
        Kind            = $Kind
        SignIn          = if ($DeviceLogin) { 'DeviceCode' } else { 'Browser' }
        Permissions     = $permissions
        Certificate     = $certificate
        CreatorRoles    = 'a user who is allowed to register applications (the tenant may allow every user to, or the account needs a role such as Application Developer, Application Administrator, Cloud Application Administrator or Global Administrator)'
        ConsentRoles    = $consentRoles
    }
}
