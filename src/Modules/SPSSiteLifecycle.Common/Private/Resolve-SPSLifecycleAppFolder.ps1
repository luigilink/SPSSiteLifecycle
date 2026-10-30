function Resolve-SPSLifecycleAppFolder {
    <#
        .SYNOPSIS
        Gives the full path of the folder that the key of the app goes in, and stops when that is not safe.

        .DESCRIPTION
        The folder that a person gives is the one that the key folder goes in: the key of an app goes in a folder named after the app, which
        the tool creates (see New-SPSLifecycleProtectedFolder) so that it is new, and so that only its owner can read it whatever the folder
        around it is. This function checks, before anything is created, that:

        - the folder is not the root of a drive and not a file;
        - neither it nor the key folder is inside a repository or inside the folder of the tool, by what is written and by where it
          leads (a link to a folder of a repository is refused, see Assert-SPSLifecycleOutsideRepository);
        - nothing is at the place of the key folder, a file, a folder or a link, even one that leads nowhere: a key that is there may be
          the one of an earlier app, and nothing is ever replaced.

        It creates nothing. A relative path is resolved against the location of the PowerShell session, as a cmdlet does (see
        Resolve-SPSLifecycleFileSystemPath).

        .PARAMETER Folder
        The folder, as the user typed it.

        .PARAMETER ApplicationName
        The name of the app: the name of the key folder and of the files.

        .PARAMETER ToolRoot
        The folder of the tool: nothing may be written inside it. Empty: not checked.

        .EXAMPLE
        Resolve-SPSLifecycleAppFolder -Folder ~/.spssitelifecycle -ApplicationName SPSSiteLifecycle -ToolRoot $root
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Folder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ApplicationName,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $ToolRoot = ''
    )

    # A root keeps its separator (C:\ is a drive, and C: is the current folder of that drive).
    $parent = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecycleFileSystemPath -Path $Folder))
    if ([System.String]::Equals([System.IO.Path]::GetPathRoot($parent), $parent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The folder '$parent' is the root of a drive or of a share: choose a folder of its own."
    }

    if (Test-Path -LiteralPath $parent -PathType Leaf) {
        throw "'$parent' is a file, and the key of the app needs a folder."
    }

    Assert-SPSLifecycleOutsideRepository -Path $parent -ToolRoot $ToolRoot

    $keyFolder = Join-Path -Path $parent -ChildPath $ApplicationName
    Assert-SPSLifecycleOutsideRepository -Path $keyFolder -ToolRoot $ToolRoot
    if ((Test-Path -LiteralPath $keyFolder) -or $null -ne [System.IO.DirectoryInfo]::new($keyFolder).LinkTarget) {
        throw "'$keyFolder' is already there, and it may hold the key of an earlier app, so nothing is written in it and nothing in it is replaced. Move it away, or choose another folder or another application name."
    }

    $keyFolder
}
