function Set-SPSLifecycleOwnerOnlyAccess {
    <#
        .SYNOPSIS
        On Windows, restricts a file or a folder to the account that runs the tool: no inheritance, one rule, full control.

        .DESCRIPTION
        The access rules that the file or the folder inherited are removed, and so are the ones it had of its own, and the account that
        runs the tool is the only one that is given access (for a folder, to what is created in it too). The rule uses the SID of the
        account, which does not depend on the language of Windows. Administrators can still take ownership, as they always can.
        Windows only: it throws on another system.

        .PARAMETER Path
        The full path of the file or the folder.

        .PARAMETER Directory
        The path is a folder: the rule is inherited by what is created in it.

        .EXAMPLE
        Set-SPSLifecycleOwnerOnlyAccess -Path C:\Users\me\.spssitelifecycle\SPSSiteLifecycle.pfx
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Directory
    )

    if (-not (Test-SPSLifecycleWindowsPlatform)) {
        throw 'Access control lists exist on Windows only.'
    }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Restrict access to the current user')) {
        return
    }

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        $null = $acl.RemoveAccessRule($rule)
    }

    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $inheritance = if ($Directory) { [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit } else { [System.Security.AccessControl.InheritanceFlags]::None }
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($user, [System.Security.AccessControl.FileSystemRights]::FullControl, $inheritance, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
