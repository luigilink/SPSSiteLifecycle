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

        # What names the site in a message is built only when there is a message: this runs once for each site of the tenant.
        $record = $null
        try {
            # Each property is read once. PowerShell hides the exception of a property that the call did not load and gives $null,
            # as it does for a property that is really empty, so a $null is never taken for what it looks like: it sends the site
            # to the reflection check, which tells a property that was not loaded from one that is empty. This is done for every
            # site, not for the first of a page, because a missing date or a missing flag takes a protection away from the site.
            $storageName = if ($Source -eq 'Csom') { 'StorageUsage' } else { 'StorageUsageCurrent' }
            $url = $Item.Url
            $siteId = $Item.SiteId
            $title = $Item.Title
            $template = $Item.Template
            $lockState = $Item.LockState
            $groupId = $Item.GroupId
            $isHubSite = $Item.IsHubSite
            $isTeamsConnected = $Item.IsTeamsConnected
            $isTeamsChannelConnected = $Item.IsTeamsChannelConnected
            $archiveStatus = $Item.ArchiveStatus
            $storage = $Item.$storageName
            $modified = $Item.LastContentModifiedDate
            if ($null -eq $url -or $null -eq $siteId -or $null -eq $title -or $null -eq $template -or $null -eq $lockState -or
                $null -eq $groupId -or $null -eq $isHubSite -or $null -eq $isTeamsConnected -or $null -eq $isTeamsChannelConnected -or
                $null -eq $archiveStatus -or $null -eq $storage -or $null -eq $modified) {
                Assert-SPSLifecycleSiteLoaded -Item $Item -Source $Source
            }

            if ($null -eq $siteId) {
                throw "the property 'SiteId' is null. It is never null when the call loaded it, so it was not loaded."
            }

            if ($null -eq $groupId) {
                throw "the property 'GroupId' is null. It is never null when the call loaded it, so it was not loaded, and the Scan could not tell a site without a group from a property that was not read."
            }

            $siteIdText = if ($siteId -is [System.Guid]) { $siteId.ToString() } else { "$siteId" }
            $groupIdText = if ($groupId -is [System.Guid]) { $groupId.ToString() } else { "$groupId" }
            $guid = [System.Guid]::Empty
            if ($siteId -isnot [System.Guid] -and [System.Guid]::TryParse($siteIdText.Trim(), [ref]$guid)) {
                $siteIdText = $guid.ToString()
            }

            if ($groupId -isnot [System.Guid] -and [System.Guid]::TryParse($groupIdText.Trim(), [ref]$guid)) {
                $groupIdText = $guid.ToString()
            }

            if ($siteIdText -eq '00000000-0000-0000-0000-000000000000') {
                throw "the property 'SiteId' is empty (all zeros). A site with no identity cannot be matched with anything, and the listing would take every such site for one."
            }

            foreach ($entry in @(@('IsHubSite', $isHubSite), @('IsTeamsConnected', $isTeamsConnected), @('IsTeamsChannelConnected', $isTeamsChannelConnected))) {
                if ($null -eq $entry[1]) {
                    throw "the property '$($entry[0])' is null. It is never null when the call loaded it, so it was not loaded, and a missing flag would read as False."
                }

                if ($entry[1] -isnot [System.Boolean]) {
                    throw "the property '$($entry[0])' is not a boolean (it is a $($entry[1].GetType().Name))."
                }
            }

            # A size is a whole number of megabytes, or unknown when it is blank. PowerShell turns '' and $false into 0, 1.5 into 2
            # and $true into 1 when it is asked for an Int64: a size that is not known would read as an empty site.
            $storageMB = $null
            $notNumber = $false
            if ($null -ne $storage) {
                if ($storage -is [System.String]) {
                    $sizeText = $storage.Trim()
                    if ($sizeText -ne '') {
                        $number = [System.Int64]0
                        if ([System.Int64]::TryParse($sizeText, [System.Globalization.NumberStyles]::AllowLeadingSign, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                            $storageMB = $number
                        }
                        else {
                            $notNumber = $true
                        }
                    }
                }
                elseif ($storage -is [System.Int64] -or $storage -is [System.Int32] -or $storage -is [System.Int16] -or $storage -is [System.SByte] -or
                    $storage -is [System.Byte] -or $storage -is [System.UInt16] -or $storage -is [System.UInt32]) {
                    $storageMB = [System.Int64]$storage
                }
                elseif ($storage -is [System.UInt64]) {
                    if ($storage -gt [System.UInt64][System.Int64]::MaxValue) {
                        $notNumber = $true
                    }
                    else {
                        $storageMB = [System.Int64]$storage
                    }
                }
                elseif ($storage -is [System.Decimal]) {
                    if ([System.Decimal]::Truncate($storage) -eq $storage -and [System.Math]::Abs($storage) -le [System.Int64]::MaxValue) {
                        $storageMB = [System.Int64]$storage
                    }
                    else {
                        $notNumber = $true
                    }
                }
                elseif ($storage -is [System.Double] -or $storage -is [System.Single]) {
                    if (-not [System.Double]::IsNaN($storage) -and -not [System.Double]::IsInfinity($storage) -and [System.Math]::Truncate($storage) -eq $storage -and [System.Math]::Abs($storage) -lt 9.2e18) {
                        $storageMB = [System.Int64]$storage
                    }
                    else {
                        $notNumber = $true
                    }
                }
                else {
                    $notNumber = $true
                }

                if ($notNumber) {
                    throw "the property '$storageName' is not a number of megabytes ('$(ConvertTo-SPSLifecycleVisibleText -Text "$storage")')."
                }

                if ($null -ne $storageMB -and $storageMB -lt 0) {
                    throw "the property '$storageName' is below zero ($storageMB). No site has a size below zero, so the value is not a size."
                }
            }

            if ($modified -is [System.DateTime] -and $modified.Ticks -eq 0) {
                $modified = $null
            }

            try {
                $modified = ConvertTo-SPSLifecycleUtcDateTime -Value $modified
            }
            catch {
                throw "the property 'LastContentModifiedDate': $($_.Exception.Message)"
            }

            $record = [PSCustomObject][ordered]@{
                Url                     = "$url"
                SiteId                  = $siteIdText
                Title                   = "$title"
                Template                = "$template"
                LockState               = "$lockState"
                GroupId                 = $groupIdText
                IsHubSite               = $isHubSite
                IsTeamsConnected        = $isTeamsConnected
                IsTeamsChannelConnected = $isTeamsChannelConnected
                ArchiveStatus           = "$archiveStatus"
                StorageUsedMB           = $storageMB
                LastContentModified     = $modified
            }
        }
        catch {
            $address = "$($Item.Url)"
            $where = if ($address) { "Site '$(ConvertTo-SPSLifecycleVisibleText -Text $address)'" } else { 'A site with no address' }
            throw "$where`: $($_.Exception.Message)"
        }

        $record
    }
}
