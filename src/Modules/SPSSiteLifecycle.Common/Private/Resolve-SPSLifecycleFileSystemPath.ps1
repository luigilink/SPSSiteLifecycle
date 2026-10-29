function Resolve-SPSLifecycleFileSystemPath {
    <#
        .SYNOPSIS
        Turns a path typed in PowerShell into a full path of the file system, the way a cmdlet does.

        .DESCRIPTION
        The .NET file methods (File.Open, Directory.CreateDirectory, Path.GetFullPath) resolve a relative path
        against the working directory of the process. Set-Location changes the location of the PowerShell
        session and not that directory, so a relative path that Test-Path finds can lead a .NET method to another
        file, or to a file that is not there. A file the tool reads or writes is a file the user chose: every path
        goes through this function first, so that the check and the file method are about the same file.

        The path is taken literally (a bracket or an asterisk is a character of the name, not a wildcard), may
        start with ~ or with a drive of the session, may name something that does not exist yet, and is
        normalized (the dots are resolved). A path of another provider (Env:, Variable:, a registry key) is
        refused: the tool only works with files.

        .PARAMETER Path
        The path as the user typed it.

        .EXAMPLE
        Resolve-SPSLifecycleFileSystemPath -Path .\Reports
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path
    )

    $provider = $null
    $drive = $null
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') {
        throw "'$Path' is not a path of the file system (it belongs to the $($provider.Name) provider)."
    }

    $full
}
