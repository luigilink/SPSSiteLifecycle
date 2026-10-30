function Get-SPSLifecycleSignInPassword {
    <#
        .SYNOPSIS
        Gives the password of the .pfx file that the app signs in with, as a SecureString, or nothing when there is none to give.

        .DESCRIPTION
        Nothing for an interactive sign-in and for a certificate of the store: they have no password. For a .pfx file: the value of the
        environment variable that the settings name (CertificatePasswordVariable), and a variable that is not set, or is empty, stops
        the tool, because a run that nobody watches cannot be asked. Without a variable the person is asked, typed and never shown, and a
        password that is left empty is a file that has none. The tool stops when it has to ask and the input is redirected. A password
        never goes in the settings file, and it is never in a message.

        .PARAMETER Setting
        The settings (Authentication, CertificatePath, CertificatePasswordVariable).

        .EXAMPLE
        $password = Get-SPSLifecycleSignInPassword -Setting $setting
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting
    )

    if (-not [System.String]::Equals("$($Setting.Authentication)", 'Certificate', [System.StringComparison]::Ordinal) -or -not "$($Setting.CertificatePath)".Trim()) {
        return
    }

    $leaf = Split-Path -Path "$($Setting.CertificatePath)".Trim() -Leaf
    $name = "$($Setting.CertificatePasswordVariable)".Trim()
    if ($name) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if ([System.String]::IsNullOrEmpty($value)) {
            throw "The environment variable '$name' is not set, or is empty, and it should hold the password of '$leaf'. Set it in the account that runs the tool: a password never goes in the settings file."
        }

        $secure = [System.Security.SecureString]::new()
        foreach ($character in $value.ToCharArray()) {
            $secure.AppendChar($character)
        }

        $secure.MakeReadOnly()
        return $secure
    }

    if (Test-SPSLifecycleInputRedirected) {
        throw "The password of '$leaf' is needed, and there is no one to type it (the input is redirected). Name an environment variable that holds it in CertificatePasswordVariable."
    }

    $typed = Read-Host -Prompt "Password of $leaf (empty if the file has none)" -AsSecureString
    if ($typed.Length -eq 0) {
        return
    }

    $typed
}
