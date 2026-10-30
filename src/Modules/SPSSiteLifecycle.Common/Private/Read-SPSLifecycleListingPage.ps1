function Read-SPSLifecycleListingPage {
    <#
        .SYNOPSIS
        Reads a page of the checkpoint back as the records that were saved.

        .DESCRIPTION
        The page is read with the strict CSV reader (a line that is lost stops the tool and names the line), and each
        record is given back with the types that Save-SPSLifecycleListingPage was given: booleans, a whole number of
        megabytes, a UTC date, and text. A text is never turned into anything else.

        .PARAMETER Folder
        The folder of the checkpoint.

        .PARAMETER Entry
        The entry of the page in the manifest.

        .EXAMPLE
        Read-SPSLifecycleListingPage -Folder $folder -Entry $manifest.Pages[0]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Entry
    )

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $columns = @(Get-SPSLifecycleListingColumn)
    $csv = Read-SPSLifecycleStrictCsv -Path (Join-Path -Path $fullFolder -ChildPath $Entry.File) -RequiredColumn $columns
    $rows = @($csv.Rows)
    if ($rows.Count -ne $Entry.Sites) {
        throw "The page $($Entry.Number) of the checkpoint holds $($rows.Count) sites, and the manifest says $($Entry.Sites)."
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $flags = @{}
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $line = $csv.Line[$index]
        foreach ($name in 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected') {
            $text = $row.$name
            if ([System.String]::Equals($text, 'True', [System.StringComparison]::Ordinal)) {
                $flags[$name] = $true
            }
            elseif ([System.String]::Equals($text, 'False', [System.StringComparison]::Ordinal)) {
                $flags[$name] = $false
            }
            else {
                throw "The page $($Entry.Number) of the checkpoint, line $line`: '$name' is neither True nor False."
            }
        }

        $size = $null
        if ($row.StorageUsedMB -ne '') {
            $number = [System.Int64]0
            if (-not [System.Int64]::TryParse($row.StorageUsedMB, [System.Globalization.NumberStyles]::Integer, $invariant, [ref]$number)) {
                throw "The page $($Entry.Number) of the checkpoint, line $line`: 'StorageUsedMB' is not a whole number."
            }

            $size = $number
        }

        $modified = $null
        if ($row.LastContentModified -ne '') {
            $date = [System.DateTime]::MinValue
            if (-not [System.DateTime]::TryParseExact($row.LastContentModified, "yyyyMMdd'T'HHmmss.fffffff'Z'", $invariant, $styles, [ref]$date)) {
                throw "The page $($Entry.Number) of the checkpoint, line $line`: 'LastContentModified' is not a date that the checkpoint writes."
            }

            $modified = $date
        }

        [PSCustomObject][ordered]@{
            Url                     = $row.Url
            SiteId                  = $row.SiteId
            Title                   = $row.Title
            Template                = $row.Template
            LockState               = $row.LockState
            GroupId                 = $row.GroupId
            IsHubSite               = $flags.IsHubSite
            IsTeamsConnected        = $flags.IsTeamsConnected
            IsTeamsChannelConnected = $flags.IsTeamsChannelConnected
            ArchiveStatus           = $row.ArchiveStatus
            StorageUsedMB           = $size
            LastContentModified     = $modified
        }
    }
}
