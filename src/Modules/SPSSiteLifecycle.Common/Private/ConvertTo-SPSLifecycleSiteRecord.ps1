function ConvertTo-SPSLifecycleSiteRecord {
    <#
        .SYNOPSIS
        Gives a site of the tenant the record that the Scan core reads, whatever the call that listed it.

        .DESCRIPTION
        The SharePoint admin API (Tenant.GetSitePropertiesFromSharePointByFilters, called CSOM here) and
        Get-PnPTenantSite describe a site with the same properties, except the storage in use, which is
        StorageUsage for the first and StorageUsageCurrent for the second. The record has the twelve names of
        D7 (Url, SiteId, Title, Template, LockState, GroupId, IsHubSite, IsTeamsConnected,
        IsTeamsChannelConnected, ArchiveStatus, StorageUsedMB, LastContentModified) and nothing else: the owner,
        its e-mail address and the other properties are personal data, or of no use, and never leave this
        function.

        The values are given in one form, so that a record that comes back from a checkpoint is the same as one
        that comes from the tenant: the site ID and the group ID are lowercase GUID text (a value that is not a
        GUID stays as it is, so that the Scan core stops on it instead of reading "no group"), the flags are
        booleans, the storage is a whole number of megabytes, and the date of the last change of the content is
        a UTC date (the empty date of .NET is no date). A text that the call does not give is empty, and a size
        or a date that it does not give is unknown.

        A GUID or a flag is never null in the admin API. PowerShell gives $null for a .NET property that throws
        when it is read, which is what a property that the call did not load does, and a record that reads a
        missing group ID as "no group" or a missing flag as "not a hub site" would hide a safeguard: such a
        value stops this function, with the name of the property and the address of the site.

        .PARAMETER Item
        The site as the call gives it.

        .PARAMETER Source
        Csom for the admin API, Cmdlet for Get-PnPTenantSite: the name of the storage in use depends on it.

        .EXAMPLE
        $site | ConvertTo-SPSLifecycleSiteRecord -Source Csom
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [System.Object]
        $Item,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Csom', 'Cmdlet')]
        [System.String]
        $Source
    )

    process {
        if ($null -eq $Item) {
            throw 'The site that the call gave is empty (null).'
        }

        $url = "$($Item.Url)"
        $where = if ($url) { "Site '$(ConvertTo-SPSLifecycleVisibleText -Text $url)'" } else { 'A site with no address' }

        $ids = @{}
        foreach ($name in 'SiteId', 'GroupId') {
            $value = $Item.$name
            if ($null -eq $value) {
                throw "$where`: the property '$name' is null. It is never null when the call loaded it, so it was not loaded, and the Scan could not tell a site without a group from a property that was not read."
            }

            $guid = [System.Guid]::Empty
            $ids[$name] = if ($value -is [System.Guid]) { $value.ToString() } elseif ([System.Guid]::TryParse("$value".Trim(), [ref]$guid)) { $guid.ToString() } else { "$value" }
        }

        $flags = @{}
        foreach ($name in 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected') {
            $value = $Item.$name
            if ($null -eq $value) {
                throw "$where`: the property '$name' is null. It is never null when the call loaded it, so it was not loaded, and a missing flag would read as False."
            }

            if ($value -isnot [System.Boolean]) {
                throw "$where`: the property '$name' is not a boolean (it is a $($value.GetType().Name))."
            }

            $flags[$name] = $value
        }

        $storageName = if ($Source -eq 'Csom') { 'StorageUsage' } else { 'StorageUsageCurrent' }
        $storage = $Item.$storageName
        $storageMB = $null
        if ($null -ne $storage) {
            try {
                $storageMB = [System.Int64]$storage
            }
            catch {
                throw "$where`: the property '$storageName' is not a number of megabytes ('$(ConvertTo-SPSLifecycleVisibleText -Text "$storage")')."
            }
        }

        $modified = $Item.LastContentModifiedDate
        if ($modified -is [System.DateTime] -and $modified.Ticks -eq 0) {
            $modified = $null
        }

        try {
            $modified = ConvertTo-SPSLifecycleUtcDateTime -Value $modified
        }
        catch {
            throw "$where`: the property 'LastContentModifiedDate': $($_.Exception.Message)"
        }

        [PSCustomObject][ordered]@{
            Url                     = $url
            SiteId                  = $ids.SiteId
            Title                   = "$($Item.Title)"
            Template                = "$($Item.Template)"
            LockState               = "$($Item.LockState)"
            GroupId                 = $ids.GroupId
            IsHubSite               = $flags.IsHubSite
            IsTeamsConnected        = $flags.IsTeamsConnected
            IsTeamsChannelConnected = $flags.IsTeamsChannelConnected
            ArchiveStatus           = "$($Item.ArchiveStatus)"
            StorageUsedMB           = $storageMB
            LastContentModified     = $modified
        }
    }
}
