function Format-SPSLifecycleAppFailure {
    <#
        .SYNOPSIS
        Says in a sentence or two why the registration stopped, what was and was not created, and what the person does next.

        .DESCRIPTION
        The message that the setup script stops with. It says what became of the app (see Get-SPSLifecycleAppFailureKind), what became of
        the certificate files (removed when no app was created, kept otherwise, because the key may be the one of an app that exists),
        and the next step: another name, an administrator, the consent in the Microsoft Entra admin center, or a look at the list of apps.
        The message of the error is told as it is, without its end.

        .PARAMETER Kind
        AppExists, Forbidden, Consent or Unknown.

        .PARAMETER Message
        The message of the error.

        .PARAMETER Plan
        The plan (see Get-SPSLifecycleAppPlan).

        .PARAMETER FilesRemoved
        The files that were removed.

        .PARAMETER FilesKept
        The files that were kept.

        .PARAMETER FilesNotRemoved
        The files that should have been removed and could not be.

        .EXAMPLE
        Format-SPSLifecycleAppFailure -Kind AppExists -Message $text -Plan $plan
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('AppExists', 'Forbidden', 'Consent', 'Unknown')]
        [System.String]
        $Kind,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Message,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Plan,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $FilesRemoved = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $FilesKept = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $FilesNotRemoved = @()
    )

    $name = $Plan.ApplicationName
    $reason = "$Message".Trim().TrimEnd('.')

    $files = [System.Collections.Generic.List[System.String]]::new()
    if (@($FilesRemoved).Count -gt 0) {
        $files.Add('The certificate files that this run had written were removed, since no app uses them.')
    }

    if (@($FilesNotRemoved).Count -gt 0) {
        $files.Add("The certificate files that this run had written could not be removed (delete them by hand, no app uses them): $(@($FilesNotRemoved) -join ', ').")
    }

    if (@($FilesKept).Count -gt 0) {
        $files.Add("The certificate files were kept ($(@($FilesKept) -join ', ')): the key may be the one of an app that exists.")
    }

    $suffix = if ($files.Count -gt 0) { ' ' + ($files -join ' ') } else { '' }

    switch ($Kind) {
        'AppExists' {
            "An application named '$name' already exists in this tenant, so nothing was created.$suffix Choose another name with -ApplicationName, or delete the existing app in the Microsoft Entra admin center (App registrations) if it is yours and you do not need it any more."
        }

        'Forbidden' {
            "Your account is not allowed to create an app registration in this tenant ($reason). Nothing was created.$suffix Ask an administrator who is allowed to (the tenant may allow every user to register applications, or the account needs a role such as Application Developer, Application Administrator, Cloud Application Administrator or Global Administrator), and run the script again."
        }

        'Consent' {
            "The registration stopped at the sign-in or at the consent: $reason. The app '$name' may have been created, with its permissions requested and the consent not given.$suffix Look for it in the Microsoft Entra admin center (App registrations), and ask $($Plan.ConsentRoles) to grant the admin consent (the app, API permissions, Grant admin consent), or open https://login.microsoftonline.com/$($Plan.TenantDomain)/adminconsent?client_id=<the Application (client) ID of the Overview page> as that administrator."
        }

        default {
            "The registration stopped: $reason. The app '$name' may or may not exist in the tenant.$suffix Look for it in the Microsoft Entra admin center (App registrations), and delete it before you run the script again if it is there."
        }
    }
}
