function Assert-SPSLifecycleOwnerOnlyAccess {
    <#
        .SYNOPSIS
        Stops when a folder can be read by anyone but the account that runs the tool.

        .DESCRIPTION
        The key of an app is written by PnP.PowerShell, with the rights that a new file gets, before the tenant has said that the app can be
        created, and it stays there for the whole registration. What keeps it from others is the folder: this function checks it, and the
        tool does not go on when it is not as it must be. On macOS and Linux the mode must be exactly 700 (a mode with a bit for the group
        or the others is refused, and so is a mode that is not read, written and entered by the owner). On Windows the access list must be
        protected from inheritance and hold rules that allow the account that runs the tool and nobody else.

        .PARAMETER Path
        The full path of the folder.

        .EXAMPLE
        Assert-SPSLifecycleOwnerOnlyAccess -Path ~/.spssitelifecycle/SPSSiteLifecycle
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (Test-SPSLifecycleWindowsPlatform) {
        $acl = Get-Acl -LiteralPath $full -ErrorAction Stop
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $others = @($acl.Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -ne $user -or $_.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow })
        if (-not $acl.AreAccessRulesProtected -or $others.Count -gt 0 -or @($acl.Access).Count -eq 0) {
            throw "The folder '$full' can be read by more than the account that runs the tool: its access list is not for that account alone. Nothing was written in it."
        }

        return
    }

    $expected = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute
    $mode = [System.IO.File]::GetUnixFileMode($full)
    if ($mode -ne $expected) {
        throw "The folder '$full' has the mode $([System.Convert]::ToString([System.Int32]$mode, 8)), and a key must go in a folder that only its owner can read (700). Nothing was written in it."
    }
}
