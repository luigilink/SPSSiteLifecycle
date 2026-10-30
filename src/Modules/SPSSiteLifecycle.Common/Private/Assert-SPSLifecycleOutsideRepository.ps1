function Assert-SPSLifecycleOutsideRepository {
    <#
        .SYNOPSIS
        Stops when a folder is, or really leads to, a place inside a repository or inside the folder of the tool.

        .DESCRIPTION
        A private key must never be written inside a repository (a folder with a .git entry at any level above it, a worktree included) or
        inside the folder of the tool, where a commit could take it. The folder is judged twice, by what is written (the full path) and by
        where it leads (every link in it followed, see Resolve-SPSLifecyclePhysicalPath), because a link outside a repository to a folder inside
        one passes the first and not the second. The folder need not exist. The comparison with the folder of the tool ignores the case,
        which a file system may not make.

        .PARAMETER Path
        The full path of the folder.

        .PARAMETER ToolRoot
        The folder of the tool: nothing may be written inside it. Empty: not checked.

        .EXAMPLE
        Assert-SPSLifecycleOutsideRepository -Path /home/me/keys -ToolRoot /home/me/SPSSiteLifecycle
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $ToolRoot = ''
    )

    $roots = [System.Collections.Generic.List[System.String]]::new()
    if ($ToolRoot) {
        $written = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecycleFileSystemPath -Path $ToolRoot))
        $roots.Add($written)
        $physicalRoot = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecyclePhysicalPath -Path $written))
        if (-not $roots.Contains($physicalRoot)) {
            $roots.Add($physicalRoot)
        }
    }

    $places = [System.Collections.Generic.List[System.String]]::new()
    $places.Add($Path)
    $physical = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecyclePhysicalPath -Path $Path))
    if (-not [System.String]::Equals($physical, $Path, [System.StringComparison]::Ordinal)) {
        $places.Add($physical)
    }

    foreach ($place in $places) {
        $repository = Find-SPSLifecycleRepositoryRoot -Path $place
        if ($repository) {
            throw "The folder '$Path' is inside a repository ('$repository' holds a .git entry$(if ($place -ne $Path) { ", and the folder leads there: '$place'" })): a private key must never be next to the code, where a commit could take it. Choose a folder outside it."
        }

        foreach ($root in $roots) {
            $inside = [System.String]::Equals($place, $root, [System.StringComparison]::OrdinalIgnoreCase)
            foreach ($separator in @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) {
                if ($place.StartsWith("$root$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $inside = $true
                }
            }

            if ($inside) {
                throw "The folder '$Path' is inside the folder of the tool ('$root'$(if ($place -ne $Path) { ", and the folder leads there: '$place'" })): a private key must never be next to the code. Choose a folder outside it."
            }
        }
    }
}
