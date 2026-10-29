function ConvertTo-SPSLifecyclePath {
    <#
        .SYNOPSIS
        Turns a path written in a settings file into a full path.

        .DESCRIPTION
        Both separators (backslash and slash) are accepted whatever the operating system, so that a
        file written on Windows also works on Linux and macOS. A relative path is relative to
        BaseFolder, which is the folder of the settings file, not the current folder.

        .PARAMETER Path
        The path as written in the settings file.

        .PARAMETER BaseFolder
        The folder a relative path is relative to.

        .EXAMPLE
        ConvertTo-SPSLifecyclePath -Path 'Reports\2026' -BaseFolder 'C:\Tools\SPSSiteLifecycle'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BaseFolder
    )

    $normalized = $Path.Trim() -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
    if (-not [System.IO.Path]::IsPathRooted($normalized)) {
        $normalized = Join-Path -Path $BaseFolder -ChildPath $normalized
    }

    [System.IO.Path]::GetFullPath($normalized)
}
