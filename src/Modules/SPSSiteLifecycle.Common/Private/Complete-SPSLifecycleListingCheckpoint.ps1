function Complete-SPSLifecycleListingCheckpoint {
    <#
        .SYNOPSIS
        Marks the checkpoint of a listing that is over: the pages are deleted and the manifest says when it finished.

        .DESCRIPTION
        Once every page has been given to the Scan, the pages are of no use, and a listing is never reused to answer
        a new Scan (see Read-SPSLifecycleListingCheckpoint). The manifest stays, so that the next run can say that the
        previous listing finished.

        .PARAMETER Folder
        The folder of the checkpoint.

        .PARAMETER Manifest
        The manifest of the listing, which must be complete.

        .PARAMETER Now
        The time of the end.

        .EXAMPLE
        Complete-SPSLifecycleListingCheckpoint -Folder $folder -Manifest $manifest -Now ([System.DateTime]::UtcNow)
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
        $Manifest,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Now
    )

    if (-not $Manifest.ListingComplete) {
        throw 'The listing is not complete: the last page that was read has a token to go on with.'
    }

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $stamp = ConvertTo-SPSLifecycleCheckpointDate -Value $Now
    $Manifest.State = 'Completed'
    $Manifest.UpdatedOn = $stamp
    $Manifest.FinishedOn = $stamp
    $pages = @($Manifest.Pages)
    $Manifest.Pages.Clear()
    Write-SPSLifecycleListingManifest -Folder $fullFolder -Manifest $Manifest

    foreach ($page in $pages) {
        Remove-Item -LiteralPath (Join-Path -Path $fullFolder -ChildPath $page.File) -Force -ErrorAction SilentlyContinue
    }
}
