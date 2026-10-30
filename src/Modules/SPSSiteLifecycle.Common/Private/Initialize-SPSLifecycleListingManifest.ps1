function Initialize-SPSLifecycleListingManifest {
    <#
        .SYNOPSIS
        Gives the manifest of a listing that starts: what is listed, how, and since when.

        .DESCRIPTION
        The manifest is the record of a checkpoint: the tenant, the filter and the options that say what the pages
        hold, when the listing started (a listing is only true for 24 hours, and the first pages are the oldest), the
        token to ask the next page with, and the pages that are saved with a hash of each. It is written to
        manifest.json next to the pages (see Write-SPSLifecycleListingManifest). The tool never reads a manifest
        that it did not write: any property that is not here, or of another type, is a damaged checkpoint.

        .PARAMETER Tenant
        The name of the tenant.

        .PARAMETER Filter
        The server filter of the listing, empty for none.

        .PARAMETER Options
        The other things that change what the pages hold (the call that is used, what is asked about OneDrive
        sites), as one text. A checkpoint is reused only when this text is the same.

        .PARAMETER Now
        The time of the start.

        .EXAMPLE
        Initialize-SPSLifecycleListingManifest -Tenant contoso -Filter '' -Options 'Source=Csom' -Now ([System.DateTime]::UtcNow)
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Tenant,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Filter,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Options,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Now
    )

    $started = ConvertTo-SPSLifecycleCheckpointDate -Value $Now

    [PSCustomObject][ordered]@{
        Version         = 1
        State           = 'Running'
        Tenant          = $Tenant
        Filter          = $Filter
        Options         = $Options
        StartedOn       = $started
        UpdatedOn       = $started
        FinishedOn      = ''
        ListingComplete = $false
        NextToken       = ''
        Pages           = [System.Collections.Generic.List[System.Object]]::new()
    }
}
