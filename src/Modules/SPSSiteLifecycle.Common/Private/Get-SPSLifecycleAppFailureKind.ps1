function Get-SPSLifecycleAppFailureKind {
    <#
        .SYNOPSIS
        Tells, from the message of a registration that failed, whether the app was surely not created, or may have been.

        .DESCRIPTION
        Register-PnPEntraIDApp signs in first (a sign-in that fails returns nothing), then writes the certificate files, then asks
        Microsoft Graph whether an app of that name exists, creates the app, and finally runs the consent. So:

        - AppExists: "The application with name ... already exists": the name is taken, and PnP.PowerShell says so before it creates the
          app, so no app was created. It is the only kind that proves it, and the only one for which the files that were written are removed;
        - Forbidden: Microsoft Graph refused the account (Authorization_RequestDenied, Forbidden, Unauthorized, access denied): most likely
          before the app was created, but the same words can come from a later call, so it proves nothing and the files are kept;
        - Consent: a Microsoft Entra sign-in error (AADSTS...), which comes at the consent, after the app was created, as far as is known;
        - Unknown: anything else: nobody can tell whether the app exists.

        The kinds that are checked first win: a message that says both is read as the first.

        .PARAMETER Message
        The message of the error.

        .EXAMPLE
        Get-SPSLifecycleAppFailureKind -Message 'The application with name X already exists.'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Message
    )

    $text = "$Message"
    $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    if ([System.Text.RegularExpressions.Regex]::IsMatch($text, 'The application with name .+ already exists', $options)) {
        return 'AppExists'
    }

    if ([System.Text.RegularExpressions.Regex]::IsMatch($text, 'Authorization_RequestDenied|Insufficient privileges to complete the operation|\((Forbidden|Unauthorized)\)|"code"\s*:\s*"(Forbidden|Unauthorized|AccessDenied|ErrorAccessDenied|InvalidAuthenticationToken|Authentication_MissingOrMalformed)"', $options)) {
        return 'Forbidden'
    }

    if ([System.Text.RegularExpressions.Regex]::IsMatch($text, 'AADSTS\d+', $options)) {
        return 'Consent'
    }

    'Unknown'
}
