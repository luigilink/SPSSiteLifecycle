function Get-SPSLifecycleVerdictPage {
    <#
        .SYNOPSIS
        Builds the text of the Verdicts page of the wiki from the verdict catalog.

        .DESCRIPTION
        The page is generated, so that a verdict cannot exist without its documentation.
        tools/Update-Documentation.ps1 writes it, and a test fails when the committed page differs
        from this text. The text uses LF line endings.

        .EXAMPLE
        Get-SPSLifecycleVerdictPage
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $lines = [System.Collections.Generic.List[System.String]]::new()

    $phaseText = {
        param($Phases)
        if ($Phases.Count -eq 2) { return 'Scan and Act' }
        "$($Phases[0]) only"
    }

    $lines.Add('# Verdicts')
    $lines.Add('')
    $lines.Add('> This page is generated from the verdict catalog of the module. Do not edit it by hand: change the catalog, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.')
    $lines.Add('')
    $lines.Add('Every site gets one verdict, in the `Verdict` column of the CSV and in the summary. The gates are checked in the order of the table below, and the first one that matches decides.')
    $lines.Add('')
    $lines.Add('- **`SKIP-`**: the tool leaves the site alone, whatever the decision. A decision never lifts a safeguard.')
    $lines.Add('- **`REVIEW-`**: a person has to look. The tool does nothing to the site.')
    $lines.Add('- **An action** (`LOCK`, `ARCHIVE`, `DELETE-SITE`, `DELETE-VIA-GROUP`): what the Scan phase suggests, and what the Act phase does after the typed confirmation, when `Execute` is `$true`.')
    $lines.Add('')
    $lines.Add('## All verdicts')
    $lines.Add('')
    $lines.Add('| Verdict | Kind | Phase | Meaning |')
    $lines.Add('|---------|------|-------|---------|')
    foreach ($row in @(Get-SPSLifecycleVerdictCatalog)) {
        $lines.Add("| ``$($row.Verdict)`` | $($row.Kind) | $(& $phaseText @($row.Phases)) | $($row.Meaning) |")
    }

    $lines.Add('')
    $lines.Add('## System sites that are never touched')
    $lines.Add('')
    $lines.Add('A site with one of these templates or paths gets `SKIP-PROTECTED`. The lists follow [Manage sites in the SharePoint admin center](https://learn.microsoft.com/sharepoint/manage-sites-in-new-admin-center), plus a few sites that would break a service if they were deleted. The root site, hub sites and the home site are protected as well.')
    $lines.Add('')
    $lines.Add('| Template | Site |')
    $lines.Add('|----------|------|')
    foreach ($row in @(Get-SPSLifecycleProtectedTemplate)) {
        $lines.Add("| ``$($row.Pattern)`` | $($row.Reason) |")
    }

    $lines.Add('')
    $lines.Add('| Path | Site |')
    $lines.Add('|------|------|')
    foreach ($row in @(Get-SPSLifecycleProtectedPath)) {
        $lines.Add("| ``$($row.Path)`` | $($row.Reason) |")
    }

    $lines.Add('')
    $lines.Add('OneDrive sites (`SPSPERS#*`) get `SKIP-ONEDRIVE`, and Teams channel sites (`TEAMCHANNEL#*`) get `SKIP-CHANNEL-SITE`.')
    $lines.Add('')
    $lines.Add('## Templates that Microsoft 365 Archive supports')
    $lines.Add('')
    $lines.Add('Only these templates can get the `ARCHIVE` verdict. The table follows [Manage Microsoft 365 Archive](https://learn.microsoft.com/microsoft-365/archive/archive-manage#site-templates-supported). A template that Microsoft adds later is refused (`SKIP-NOT-ARCHIVABLE`) until the table of the module is updated.')
    $lines.Add('')
    $lines.Add('| Template | Site |')
    $lines.Add('|----------|------|')
    foreach ($row in @(Get-SPSLifecycleArchivableTemplate)) {
        $lines.Add("| ``$($row.Template)`` | $($row.Name) |")
    }

    $lines.Add('')

    $lines -join "`n"
}
