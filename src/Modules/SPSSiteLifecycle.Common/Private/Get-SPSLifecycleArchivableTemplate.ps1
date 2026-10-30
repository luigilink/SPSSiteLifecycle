function Get-SPSLifecycleArchivableTemplate {
    <#
        .SYNOPSIS
        Returns the site templates that Microsoft 365 Archive supports.

        .DESCRIPTION
        Source: Manage Microsoft 365 Archive, section "Site templates supported"
        (https://learn.microsoft.com/microsoft-365/archive/archive-manage#site-templates-supported),
        read on 28 October 2026. Publishing sites, channel sites and some legacy templates cannot be
        archived. A template that Microsoft adds later is refused until this table is updated: the
        tool fails on the safe side.

        .EXAMPLE
        Get-SPSLifecycleArchivableTemplate | Select-Object -ExpandProperty Template
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    if ($null -eq $script:ArchivableTemplateTable) {
        $script:ArchivableTemplateTable = @(
            [PSCustomObject]@{ Template = 'STS#0'; Name = 'Team site (classic experience)' }
            [PSCustomObject]@{ Template = 'STS#1'; Name = 'Blank site' }
            [PSCustomObject]@{ Template = 'STS#2'; Name = 'Document workspace' }
            [PSCustomObject]@{ Template = 'STS#3'; Name = 'Team site' }
            [PSCustomObject]@{ Template = 'SITEPAGEPUBLISHING#0'; Name = 'Communication site' }
            [PSCustomObject]@{ Template = 'GROUP#0'; Name = 'Microsoft 365 group-connected team site' }
            [PSCustomObject]@{ Template = 'SPSNEWS#0'; Name = 'News site' }
            [PSCustomObject]@{ Template = 'SPSNHOME#0'; Name = 'News site' }
            [PSCustomObject]@{ Template = 'WIKI#0'; Name = 'Wiki site' }
            [PSCustomObject]@{ Template = 'ENTERWIKI#0'; Name = 'Enterprise wiki' }
            [PSCustomObject]@{ Template = 'BDR#0'; Name = 'Document center' }
            [PSCustomObject]@{ Template = 'OFFILE#0'; Name = 'Records center' }
            [PSCustomObject]@{ Template = 'OFFILE#1'; Name = 'Records center' }
        )
    }

    $script:ArchivableTemplateTable
}
