function New-SPSLifecycleProtectedFolder {
    <#
        .SYNOPSIS
        Creates the folder of the certificate files, so that only the account that runs the tool can read what goes in it.

        .DESCRIPTION
        A folder that does not exist is created with the mode 700 (macOS and Linux) or with an access control list that gives the account
        that runs the tool alone full control (Windows), before any key is written in it. A folder that exists is left as it is: it
        is the choice of the user, and the key itself is restricted when it is written (see Protect-SPSLifecyclePrivateKey). It gives
        $true when it created the folder.

        .PARAMETER Path
        The folder.

        .EXAMPLE
        New-SPSLifecycleProtectedFolder -Path ~/.spssitelifecycle
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (Test-Path -LiteralPath $full -PathType Container) {
        return $false
    }

    if (Test-Path -LiteralPath $full) {
        throw "'$full' is a file, and the certificate files need a folder."
    }

    if (-not $PSCmdlet.ShouldProcess($full, 'Create a folder that only the current user can read')) {
        return $false
    }

    if (Test-SPSLifecycleWindowsPlatform) {
        $null = [System.IO.Directory]::CreateDirectory($full)
        Set-SPSLifecycleOwnerOnlyAccess -Path $full -Directory
    }
    else {
        $mode = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute
        $null = [System.IO.Directory]::CreateDirectory($full, $mode)
    }

    $true
}
