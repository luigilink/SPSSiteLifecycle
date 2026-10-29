function Get-SPSLifecycleProtectedPath {
    <#
        .SYNOPSIS
        Returns the site paths that the tool never touches, with the reason.

        .DESCRIPTION
        These URLs are the ones that the Active sites page of the SharePoint admin center leaves out
        (https://learn.microsoft.com/sharepoint/manage-sites-in-new-admin-center, read on
        28 October 2026), except /personal/, which is OneDrive and has its own verdict. A path is
        compared with the path of the site URL, without the case and the trailing slash.

        .EXAMPLE
        Get-SPSLifecycleProtectedPath | Select-Object -ExpandProperty Path
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    @(
        [PSCustomObject]@{ Path = '/sites/contenttypehub'; Reason = 'Content type hub: holds the content types shared by the whole tenant' }
        [PSCustomObject]@{ Path = '/sites/compliancepolicycenter'; Reason = 'Compliance policy center' }
        [PSCustomObject]@{ Path = '/portal/hub'; Reason = 'PointPublishing hub' }
        [PSCustomObject]@{ Path = '/search'; Reason = 'Search site' }
    )
}
