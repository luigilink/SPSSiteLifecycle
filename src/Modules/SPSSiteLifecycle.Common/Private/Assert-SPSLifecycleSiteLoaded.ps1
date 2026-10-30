function Assert-SPSLifecycleSiteLoaded {
    <#
        .SYNOPSIS
        Stops when a site that a call gave does not hold a property that the Scan needs.

        .DESCRIPTION
        PowerShell hides the exception of a .NET property that cannot be read: a property of the SharePoint admin
        API that the call did not load reads as $null, as a property that really is empty does, and a Scan
        that took it for "no group" or "not a hub site" would hide a safeguard for every site of the listing. The
        properties are read here through reflection, which shows the exception, on the first site of a page: a
        property that is not loaded is not loaded for any site of the call.

        An object that is not a .NET object of the API (a test double, an object of PowerShell) is checked for the
        presence of the property only.

        .PARAMETER Item
        A site as the call gives it.

        .PARAMETER Source
        Csom for the admin API, Cmdlet for Get-PnPTenantSite: the name of the storage in use depends on it.

        .EXAMPLE
        Assert-SPSLifecycleSiteLoaded -Item $page[0] -Source Csom
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Item,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Csom', 'Cmdlet')]
        [System.String]
        $Source
    )

    if ($null -eq $Item) {
        throw 'The site that the call gave is empty (null).'
    }

    $storageName = if ($Source -eq 'Csom') { 'StorageUsage' } else { 'StorageUsageCurrent' }
    $names = @('Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', $storageName, 'LastContentModifiedDate')
    $type = $Item.GetType()
    foreach ($name in $names) {
        $property = $type.GetProperty($name)
        if ($null -ne $property) {
            try {
                $null = $property.GetValue($Item)
            }
            catch {
                $reason = $_.Exception
                while ($null -ne $reason.InnerException) {
                    $reason = $reason.InnerException
                }

                throw "The property '$name' has not been loaded by the call that listed the sites (reading it fails: $($reason.Message)). The Scan cannot use a site without it: a missing group ID would read as no group, and a missing flag as False."
            }
        }
        elseif ($null -eq $Item.PSObject.Properties[$name]) {
            throw "The site that the call gave has no property '$name'. The Scan cannot use a site without it."
        }
    }
}
