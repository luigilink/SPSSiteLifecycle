function Get-SPSLifecycleListingColumn {
    <#
        .SYNOPSIS
        Gives the names of the twelve properties of a site record, in the order of the checkpoint pages.

        .DESCRIPTION
        They are the names of D7 that ConvertTo-SPSLifecycleSiteRecord gives and that the Scan core reads. The pages of
        a checkpoint have one column for each, in this order, and a page whose header is not this one is refused.

        .EXAMPLE
        Get-SPSLifecycleListingColumn
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param ()

    if ($null -eq $script:ListingColumnTable) {
        $script:ListingColumnTable = @('Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified')
    }

    $script:ListingColumnTable
}
