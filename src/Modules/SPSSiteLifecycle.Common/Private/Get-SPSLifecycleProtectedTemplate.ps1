function Get-SPSLifecycleProtectedTemplate {
    <#
        .SYNOPSIS
        Returns the site templates that the tool never touches, with the reason.

        .DESCRIPTION
        These are system sites. Most of them come from the list of templates that the Active sites
        page of the SharePoint admin center leaves out
        (https://learn.microsoft.com/sharepoint/manage-sites-in-new-admin-center, read on
        28 October 2026). APPCATALOG, EDISC and SRCHCEN are not on that list; they are protected as
        well, because deleting them would break a service.

        OneDrive (SPSPERS) and Teams channel sites (TEAMCHANNEL) have their own verdicts.
        The patterns are wildcards for the -like operator.

        .EXAMPLE
        Get-SPSLifecycleProtectedTemplate | Where-Object { 'APPCATALOG#0' -like $_.Pattern }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    @(
        [PSCustomObject]@{ Pattern = 'APPCATALOG#*'; Reason = 'App catalog site' }
        [PSCustomObject]@{ Pattern = 'CENTRALADMIN#*'; Reason = 'Central admin site' }
        [PSCustomObject]@{ Pattern = 'CSPCONTAINER#*'; Reason = 'CSP container (SharePoint Embedded)' }
        [PSCustomObject]@{ Pattern = 'EDISC#*'; Reason = 'eDiscovery center' }
        [PSCustomObject]@{ Pattern = 'FunSite#*'; Reason = 'SharePoint tenant fundamental site' }
        [PSCustomObject]@{ Pattern = 'POINTPUBLISHING*'; Reason = 'PointPublishing hub, personal blog and topic sites' }
        [PSCustomObject]@{ Pattern = 'POLICYCTR#*'; Reason = 'Compliance policy center' }
        [PSCustomObject]@{ Pattern = 'REDIRECTSITE#*'; Reason = 'Redirect site' }
        [PSCustomObject]@{ Pattern = 'REVIEWCTR#*'; Reason = 'Review center' }
        [PSCustomObject]@{ Pattern = 'SPSMSITEHOST#*'; Reason = 'My Site host' }
        [PSCustomObject]@{ Pattern = 'SRCHCEN#*'; Reason = 'Search center' }
        [PSCustomObject]@{ Pattern = 'TENANTADMIN#*'; Reason = 'Tenant admin site' }
        [PSCustomObject]@{ Pattern = 'TestSite#*'; Reason = 'Test site' }
    )
}
