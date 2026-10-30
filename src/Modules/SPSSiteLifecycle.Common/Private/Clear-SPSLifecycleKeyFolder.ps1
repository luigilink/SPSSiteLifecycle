function Clear-SPSLifecycleKeyFolder {
    <#
        .SYNOPSIS
        Removes what a registration that created no app left in the key folder, and the folder when it is empty: only the two files of the app, by their names.

        .DESCRIPTION
        PnP.PowerShell writes the private key and the certificate before it asks the tenant whether the app can be created. When the answer
        is that the name is taken, no app uses them and nothing else is in the folder, which the tool created a moment ago: the files
        <name>.pfx and <name>.cer are removed, a link of that name is not followed (it is reported as not removed), and the folder is removed
        when nothing else is in it (nothing is ever removed with -Recurse). It never throws: it gives Removed, NotRemoved and
        FolderRemoved. With nothing to remove it removes the folder when it is empty, which is what a registration that wrote nothing leaves.

        .PARAMETER Folder
        The key folder.

        .PARAMETER ApplicationName
        The name of the app: the name of the files.

        .PARAMETER FolderOnly
        Removes the folder when it is empty, and no file: for a registration that wrote nothing.

        .EXAMPLE
        Clear-SPSLifecycleKeyFolder -Folder $folder -ApplicationName SPSSiteLifecycle
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ApplicationName,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $FolderOnly
    )

    $removed = [System.Collections.Generic.List[System.String]]::new()
    $notRemoved = [System.Collections.Generic.List[System.String]]::new()
    $folderRemoved = $false
    try {
        $full = Resolve-SPSLifecycleFileSystemPath -Path $Folder
        foreach ($extension in $(if ($FolderOnly) { @() } else { @('pfx', 'cer') })) {
            $file = Join-Path -Path $full -ChildPath "$ApplicationName.$extension"
            $entry = [System.IO.FileInfo]::new($file)
            if ($null -ne $entry.LinkTarget) {
                $notRemoved.Add($file)
                continue
            }

            if (Test-Path -LiteralPath $file -PathType Container) {
                $notRemoved.Add($file)
                continue
            }

            if (-not $entry.Exists) {
                continue
            }

            try {
                if ($PSCmdlet.ShouldProcess($file, 'Remove a file that no app uses')) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                    $removed.Add($file)
                }
            }
            catch {
                $notRemoved.Add($file)
            }
        }

        $directory = [System.IO.DirectoryInfo]::new($full)
        if ($directory.Exists -and $null -eq $directory.LinkTarget -and @($directory.EnumerateFileSystemInfos()).Count -eq 0) {
            if ($PSCmdlet.ShouldProcess($full, 'Remove the empty key folder')) {
                [System.IO.Directory]::Delete($full, $false)
                $folderRemoved = $true
            }
        }
    }
    catch {
        $null = $_
    }

    [PSCustomObject][ordered]@{
        Removed       = $removed.ToArray()
        NotRemoved    = $notRemoved.ToArray()
        FolderRemoved = $folderRemoved
    }
}
