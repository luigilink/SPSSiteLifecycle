function New-SPSLifecycleProtectedFolder {
    <#
        .SYNOPSIS
        Creates the new folder that the key of an app goes in, so that only the account that runs the tool can read what goes in it, and checks it.

        .DESCRIPTION
        PnP.PowerShell writes the key with the rights that a new file gets, and before the tenant has said that the app can be created, so it
        is the folder that keeps the key from others, and it is made before the key is. The folder must not exist (a folder that exists may
        be anyone's, and a link may lead anywhere): it is created with the mode 700 (macOS and Linux) or with an access control list that
        gives the account that runs the tool alone full control (Windows), and then checked (see Assert-SPSLifecycleOwnerOnlyAccess). A folder that
        is not as it must be is removed, and the function stops, so that nothing is written in it. The folders above it are created with
        the same rights when they do not exist. It gives $true when it created the folder.

        .PARAMETER Path
        The folder.

        .EXAMPLE
        New-SPSLifecycleProtectedFolder -Path ~/.spssitelifecycle/SPSSiteLifecycle
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
    if ((Test-Path -LiteralPath $full) -or $null -ne [System.IO.DirectoryInfo]::new($full).LinkTarget) {
        throw "'$full' is already there: the key of an app goes in a folder that the tool creates, and never in one that exists."
    }

    if (-not $PSCmdlet.ShouldProcess($full, 'Create a folder that only the current user can read')) {
        return $false
    }

    if (Test-SPSLifecycleWindowsPlatform) {
        $null = [System.IO.Directory]::CreateDirectory($full)
        Set-SPSLifecycleOwnerOnlyAccess -Path $full -Directory -Confirm:$false
    }
    else {
        $mode = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute
        $null = [System.IO.Directory]::CreateDirectory($full, $mode)
    }

    try {
        Assert-SPSLifecycleOwnerOnlyAccess -Path $full
    }
    catch {
        $reason = $_.Exception.Message
        try {
            [System.IO.Directory]::Delete($full, $false)
        }
        catch {
            $null = $_
        }

        throw $reason
    }

    $true
}
