function Read-SPSLifecycleFileByte {
    <#
        .SYNOPSIS
        Reads the bytes of a file that a person may have open in Excel, and says what went wrong when it cannot.

        .DESCRIPTION
        The file is opened so that another program may keep it open for reading and writing: a CSV file that is
        open in Excel is still read. When it cannot be read, the message says whether the file is missing or is
        probably open in another program.

        The path is resolved against the location of the PowerShell session first (see
        Resolve-SPSLifecycleFileSystemPath).

        .PARAMETER Path
        Path of the file. A relative path is relative to the location of the PowerShell session.

        .EXAMPLE
        Read-SPSLifecycleFileByte -Path .\lock-journal.csv
    #>
    [CmdletBinding()]
    [OutputType([System.Byte[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File not found: '$fullPath'."
    }

    try {
        $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $memory = [System.IO.MemoryStream]::new()
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
        throw "File not found: '$fullPath'."
    }
    catch [System.IO.IOException] {
        throw "Cannot read '$fullPath': the file is probably open in another program (Excel?). Close it, or save a copy and use the copy. ($($_.Exception.Message))"
    }

    , $bytes
}
