function Protect-SPSLifecyclePrivateKey {
    <#
        .SYNOPSIS
        Restricts a private key file to the account that runs the tool, and says whether it did.

        .DESCRIPTION
        The mode 600 on macOS and Linux, an access control list that gives the account alone full control on Windows. It never throws:
        it runs in a finally, after a registration that failed or that was interrupted, and a key that could not be restricted is a
        warning that tells the person to do it by hand. It gives $false for a file that is not there.

        .PARAMETER Path
        The key file.

        .EXAMPLE
        Protect-SPSLifecyclePrivateKey -Path ~/.spssitelifecycle/SPSSiteLifecycle.pfx
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    try {
        $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return $false
        }

        if (Test-SPSLifecycleWindowsPlatform) {
            Set-SPSLifecycleOwnerOnlyAccess -Path $full -Confirm:$false
        }
        else {
            [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        }

        $true
    }
    catch {
        Write-Warning -Message "The access rights of '$Path' could not be restricted to your account: $($_.Exception.Message.Trim().TrimEnd('.')). Restrict them by hand."
        $false
    }
}
