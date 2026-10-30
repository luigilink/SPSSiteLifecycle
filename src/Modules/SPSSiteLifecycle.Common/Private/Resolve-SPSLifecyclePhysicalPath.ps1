function Resolve-SPSLifecyclePhysicalPath {
    <#
        .SYNOPSIS
        Gives the path that a path really leads to: every link in it (a symbolic link, a junction) is followed, wherever it is in the path.

        .DESCRIPTION
        A check on the text of a path says nothing of where the path leads: a folder that is not in a repository can be a link to a folder
        that is, and a key written there lands in the repository. This function walks the path from its root, component by component, and
        replaces a component that is a link by its target (a relative target is read from the folder of the link), and goes on with what is
        left of the path, up to the first component that does not exist, which it keeps as it is with everything after it. A path that goes
        through more than 32 links is refused, which also stops a loop. The path must be a full path (see Resolve-SPSLifecycleFileSystemPath).

        .PARAMETER Path
        The full path.

        .PARAMETER Depth
        The number of links followed so far (the function calls itself).

        .EXAMPLE
        Resolve-SPSLifecyclePhysicalPath -Path /home/me/keys/app
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Int32]
        $Depth = 0
    )

    if ($Depth -gt 32) {
        throw "The path '$Path' goes through too many links (or through a loop of them): the tool cannot tell where it leads."
    }

    $full = Resolve-SPSLifecycleFileSystemPath -Path $Path
    $root = [System.IO.Path]::GetPathRoot($full)
    $separators = [System.Char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $parts = @($full.Substring($root.Length).Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries))
    $current = $root
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $candidate = [System.IO.Path]::Combine($current, $parts[$index])
        $entry = [System.IO.DirectoryInfo]::new($candidate)
        $link = $entry.LinkTarget
        if ($null -eq $link) {
            $current = $candidate
            continue
        }

        try {
            $final = $entry.ResolveLinkTarget($true)
        }
        catch {
            throw "The path '$Path' goes through too many links (or a loop of them), or through a link that cannot be read: the tool cannot tell where it leads."
        }

        $base = if ($null -ne $final) { $final.FullName } else { [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($current, $link)) }
        $next = $base
        foreach ($rest in @($parts | Select-Object -Skip ($index + 1))) {
            $next = [System.IO.Path]::Combine($next, $rest)
        }

        return (Resolve-SPSLifecyclePhysicalPath -Path $next -Depth ($Depth + 1))
    }

    $current
}
