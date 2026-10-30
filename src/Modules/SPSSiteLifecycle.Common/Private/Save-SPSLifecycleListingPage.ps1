function Save-SPSLifecycleListingPage {
    <#
        .SYNOPSIS
        Saves a page of the listing in the checkpoint, and records it in the manifest.

        .DESCRIPTION
        The records of the page go to page-000001.csv (the number of the page, on six digits): one line for each site,
        every cell in double quotes, so that any text of the tenant (a comma, a quote, a line break, a text that looks
        like a date) reads back as it was written. The file goes to a partial file that takes its name by a move, a hash
        of it is taken, and only then does the manifest list the page and give the token that the next page is asked
        with. A run that stops between the two leaves a page that no manifest lists, which is written again.

        The manifest that is given is changed (the page is added) and written. Returns the entry of the page.

        The cells are quoted here and not with ConvertTo-SPSLifecycleCsvField, which is a call for each cell: the
        listing of 259,000 sites would take three minutes more (see D9 on the cost of a function call).

        .PARAMETER Folder
        The folder of the checkpoint.

        .PARAMETER Manifest
        The manifest of the listing.

        .PARAMETER Record
        The records of the page (see ConvertTo-SPSLifecycleSiteRecord), possibly none.

        .PARAMETER Token
        The token that the page was asked with, empty for the first page.

        .PARAMETER NextToken
        The token to ask the next page with, empty when this was the last page.

        .PARAMETER Read
        The number of sites that the tenant gave in this page, before the ones that were dropped.

        .PARAMETER Seconds
        The time that the page took.

        .PARAMETER Now
        The time of the save.

        .EXAMPLE
        Save-SPSLifecycleListingPage -Folder $folder -Manifest $manifest -Record $records -Token '' -NextToken $next -Read 1500 -Seconds 2.4 -Now $now
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
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Record,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Token,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $NextToken,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2147483647)]
        [System.Int32]
        $Read,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 1.7976931348623157E+308)]
        [System.Double]
        $Seconds,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Now
    )

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $null = [System.IO.Directory]::CreateDirectory($fullFolder)
    $number = $Manifest.Pages.Count + 1
    $file = 'page-{0}.csv' -f $number.ToString('D6', [System.Globalization.CultureInfo]::InvariantCulture)
    $path = Join-Path -Path $fullFolder -ChildPath $file
    $partial = '{0}.{1}.partial' -f $path, [System.Guid]::NewGuid().ToString('N').Substring(0, 8)

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $lines = [System.Collections.Generic.List[System.String]]::new($Record.Count + 1)
    $lines.Add(((Get-SPSLifecycleListingColumn) -join ','))
    $cells = [System.String[]]::new(12)
    foreach ($site in $Record) {
        $cells[0] = "$($site.Url)"
        $cells[1] = "$($site.SiteId)"
        $cells[2] = "$($site.Title)"
        $cells[3] = "$($site.Template)"
        $cells[4] = "$($site.LockState)"
        $cells[5] = "$($site.GroupId)"
        $cells[6] = "$($site.IsHubSite)"
        $cells[7] = "$($site.IsTeamsConnected)"
        $cells[8] = "$($site.IsTeamsChannelConnected)"
        $cells[9] = "$($site.ArchiveStatus)"
        $cells[10] = if ($null -eq $site.StorageUsedMB) { '' } else { ([System.Int64]$site.StorageUsedMB).ToString($invariant) }
        $cells[11] = if ($null -eq $site.LastContentModified) { '' } else { ([System.DateTime]$site.LastContentModified).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss.fffffff'Z'", $invariant) }
        for ($i = 0; $i -lt 12; $i++) {
            $cells[$i] = '"' + $cells[$i].Replace('"', '""') + '"'
        }

        $lines.Add(($cells -join ','))
    }

    try {
        Set-Content -LiteralPath $partial -Value (($lines -join "`r`n") + "`r`n") -Encoding utf8NoBOM -NoNewline
        $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
        Move-Item -LiteralPath $partial -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }

    $entry = [PSCustomObject][ordered]@{
        Number  = $number
        File    = $file
        Token   = $Token
        Read    = $Read
        Sites   = $Record.Count
        Sha256  = $hash
        Seconds = $Seconds
    }

    $Manifest.Pages.Add($entry)
    $Manifest.NextToken = $NextToken
    $Manifest.ListingComplete = -not $NextToken
    $Manifest.UpdatedOn = ConvertTo-SPSLifecycleCheckpointDate -Value $Now
    Write-SPSLifecycleListingManifest -Folder $fullFolder -Manifest $Manifest

    $entry
}
