function Resolve-SPSLifecycleAppFolder {
    <#
        .SYNOPSIS
        Gives the full path of the folder for the certificate files, and stops when the files would not be safe or would replace others.

        .DESCRIPTION
        The folder is where the private key (.pfx) and the certificate (.cer) go. It must be outside any repository (a folder that holds a
        .git entry, at any level above it) and outside the folder of the tool, because a key next to the code can be committed by mistake. It
        may exist or not (resolving it creates nothing), it must not be a file, and no <name>.pfx or <name>.cer may be in it: a key that
        is there may be the one of an earlier app, and it is never replaced. A relative path is resolved against the location of the
        PowerShell session, as a cmdlet does (see Resolve-SPSLifecycleFileSystemPath).

        .PARAMETER Folder
        The folder, as the user typed it.

        .PARAMETER ApplicationName
        The name of the app: the name of the files.

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
    $full = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecycleFileSystemPath -Path $Folder))
    if ([System.String]::Equals([System.IO.Path]::GetPathRoot($full), $full, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The folder '$full' is the root of a drive or of a share: choose a folder of its own."
    }

    $repository = Find-SPSLifecycleRepositoryRoot -Path $full
    if ($repository) {
        throw "The folder '$full' is inside a repository ('$repository' holds a .git entry): a private key must never be next to the code, where a commit could take it. Choose a folder outside it."
    }

    if ($ToolRoot) {
        $root = [System.IO.Path]::TrimEndingDirectorySeparator((Resolve-SPSLifecycleFileSystemPath -Path $ToolRoot))
        $separators = @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $inside = [System.String]::Equals($full, $root, [System.StringComparison]::OrdinalIgnoreCase)
        foreach ($separator in $separators) {
            if ($full.StartsWith("$root$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
                $inside = $true
            }
        }

        if ($inside) {
            throw "The folder '$full' is inside the folder of the tool ('$root'): a private key must never be next to the code. Choose a folder outside it."
        }
    }

    if (Test-Path -LiteralPath $full -PathType Leaf) {
        throw "'$full' is a file, and the certificate files need a folder."
    }

    foreach ($extension in 'pfx', 'cer') {
        $file = Join-Path -Path $full -ChildPath "$ApplicationName.$extension"
        if (Test-Path -LiteralPath $file) {
            throw "The file '$file' is already there, and it may hold the key of an earlier app, so it is never replaced. Move it away, or choose another folder or another application name."
        }
    }

    $full
}
