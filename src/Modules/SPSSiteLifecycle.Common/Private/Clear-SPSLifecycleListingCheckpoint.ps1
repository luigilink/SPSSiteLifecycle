function Clear-SPSLifecycleListingCheckpoint {
    <#
        .SYNOPSIS
        Deletes what a checkpoint holds: the manifest, the pages and the partial files, and nothing else.

        .DESCRIPTION
        Used before a listing starts again. The lock file stays (the run holds it), and so does any other file that
        someone put in the folder.

        .PARAMETER Folder
        The folder of the checkpoint. A folder that does not exist is a checkpoint that is already gone.

        .EXAMPLE
        Clear-SPSLifecycleListingCheckpoint -Folder $folder
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder
    )

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    if (-not (Test-Path -LiteralPath $fullFolder -PathType Container)) {
        return
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $fullFolder -File)) {
        if ($file.Name -cmatch '\A(manifest\.json|page-[0-9]{6}\.csv)(\.[0-9a-f]{8}\.partial)?\z') {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}
