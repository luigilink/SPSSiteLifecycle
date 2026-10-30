function Find-SPSLifecycleRepositoryRoot {
    <#
        .SYNOPSIS
        Gives the nearest folder at or above a path that holds a .git entry (a folder, or the file of a worktree or a submodule).

        .DESCRIPTION
        A private key must never be written inside a repository, where a commit could take it. The path need not exist: the walk starts at
        the path itself, so that a folder that is about to be created is judged by its parents. It gives nothing when no folder above
        holds a .git entry.

        .PARAMETER Path
        The full path of a folder.

        .EXAMPLE
        Find-SPSLifecycleRepositoryRoot -Path /home/me/work/keys
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $directory = $Path
    while ($directory) {
        if (Test-Path -LiteralPath (Join-Path -Path $directory -ChildPath '.git')) {
            return $directory
        }

        $parent = [System.IO.Path]::GetDirectoryName($directory)
        if ([System.String]::IsNullOrEmpty($parent) -or [System.String]::Equals($parent, $directory, [System.StringComparison]::Ordinal)) {
            break
        }

        $directory = $parent
    }
}
