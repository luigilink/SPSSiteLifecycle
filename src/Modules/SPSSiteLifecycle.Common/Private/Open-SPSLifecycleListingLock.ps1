function Open-SPSLifecycleListingLock {
    <#
        .SYNOPSIS
        Takes the lock that lets one run at a time write the checkpoint of an output folder.

        .DESCRIPTION
        Two Scans that write the same checkpoint would mix their pages, and the second would resume from the first
        one's pages while it was still writing them. The lock is a file that the run keeps open, without sharing, until
        it is over: the system releases it when the process ends, even when it was killed, so that no lock is left
        behind and none has to be removed by hand.

        The folder is created when it is missing. Returns the open file: the caller disposes it when the run is over.

        .PARAMETER Folder
        The folder of the checkpoint. A relative path is relative to the location of the PowerShell session.

        .EXAMPLE
        $lock = Open-SPSLifecycleListingLock -Folder .\Reports\listing-checkpoint
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder
    )

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $null = [System.IO.Directory]::CreateDirectory($fullFolder)
    $path = Join-Path -Path $fullFolder -ChildPath 'listing.lock'
    try {
        [System.IO.File]::Open($path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        throw "Another Scan is listing the tenant with the same output folder ('$fullFolder'), or this one did not end. A checkpoint is written by one run at a time: wait for the other run, or stop it, and run again."
    }
}
