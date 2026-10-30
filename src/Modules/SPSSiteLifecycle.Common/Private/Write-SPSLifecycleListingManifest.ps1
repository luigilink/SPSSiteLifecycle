function Write-SPSLifecycleListingManifest {
    <#
        .SYNOPSIS
        Writes the manifest of a checkpoint, so that a run that stops at any moment leaves a manifest that is whole.

        .DESCRIPTION
        The manifest goes to a partial file, which takes the name manifest.json by a move, as the report does. A run
        that is killed while it writes leaves the previous manifest, which does not list the page that was being
        saved: that page is saved again.

        .PARAMETER Folder
        The folder of the checkpoint.

        .PARAMETER Manifest
        The manifest (see Initialize-SPSLifecycleListingManifest).

        .EXAMPLE
        Write-SPSLifecycleListingManifest -Folder $folder -Manifest $manifest
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Manifest
    )

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $path = Join-Path -Path $fullFolder -ChildPath 'manifest.json'
    $partial = '{0}.{1}.partial' -f $path, [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        Set-Content -LiteralPath $partial -Value (ConvertTo-Json -InputObject $Manifest -Depth 5) -Encoding utf8NoBOM
        Move-Item -LiteralPath $partial -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }
}
