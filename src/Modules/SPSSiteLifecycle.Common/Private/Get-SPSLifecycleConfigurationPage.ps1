function Get-SPSLifecycleConfigurationPage {
    <#
        .SYNOPSIS
        Builds the text of the Configuration page of the wiki from the settings schema.

        .DESCRIPTION
        The page is generated, so that a setting cannot exist without its documentation.
        tools/Update-Documentation.ps1 writes it, and a test fails when the committed page differs
        from this text. The text uses LF line endings.

        .EXAMPLE
        Get-SPSLifecycleConfigurationPage
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $schema = @(Get-SPSLifecycleSettingSchema)
    $lines = [System.Collections.Generic.List[System.String]]::new()

    $tick = [System.Char]96
    $quote = {
        param($Values)
        ($Values | ForEach-Object { "$tick$_$tick" }) -join ', '
    }

    $typeText = {
        param($Row)
        switch ($Row.Type) {
            'String' { 'text' }
            'Guid' { 'GUID' }
            'Path' { if ($Row.Kind -eq 'Folder') { 'folder path' } else { 'file path' } }
            'PathList' { 'list of file paths' }
            'StringList' { 'list of texts' }
            'Choice' { "one of $(& $quote $Row.Values)" }
            'ChoiceList' { "list of $(& $quote $Row.Values)" }
            'Int' { "whole number, $($Row.Min) to $($Row.Max)" }
            'Double' { "number, $($Row.Min) to $($Row.Max)" }
            'Bool' { '`$true` or `$false`' }
            default { $Row.Type }
        }
    }

    $phaseText = {
        param($Phases)
        if ($Phases.Count -eq 0) { return 'no' }
        if ($Phases.Count -eq 2) { return 'Scan and Act' }
        "$($Phases[0]) only"
    }

    $lines.Add('# Configuration')
    $lines.Add('')
    $lines.Add('> This page is generated from the settings schema of the module. Do not edit it by hand: change the schema, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.')
    $lines.Add('')
    $lines.Add('SPSSiteLifecycle reads its settings from one PowerShell data file (`.psd1`). Copy [`src/config/SPSSiteLifecycle.example.psd1`](https://github.com/luigilink/SPSSiteLifecycle/blob/main/src/config/SPSSiteLifecycle.example.psd1), fill it in, and give it to the script:')
    $lines.Add('')
    $lines.Add('```powershell')
    $lines.Add('pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan')
    $lines.Add('pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Act')
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## How the file is read')
    $lines.Add('')
    $lines.Add('- The file holds data only. It is read with `Import-PowerShellDataFile`, so no code in it ever runs.')
    $lines.Add('- Shared settings are written at the top of the file. The settings of one phase are written in the `Scan` or the `Act` section.')
    $lines.Add('- The whole file is checked before anything runs, and every problem is reported at once.')
    $lines.Add('- An unknown setting stops the tool, so that a typo cannot silently disable a safeguard. The message suggests the closest name and says when a setting is in the wrong section.')
    $lines.Add('- Types are strict. A number is written `25`, not `''25''`, and a boolean is `$true` or `$false`, never `''false''` (a non-empty text would count as true).')
    $lines.Add('- A relative path is relative to the folder of the settings file, not to the current folder. Both `\` and `/` are accepted.')
    $lines.Add('- The required settings and the existence of the input files are checked for the requested phase only, so that a Scan can run before the settings of the Act section are filled in.')
    $lines.Add('- `Execute` and `MaxActions` are settings of the `Act` section. They are not command-line parameters.')
    $lines.Add('- The tool refuses the Microsoft corporate tenants (`microsoft` and `microsoftonline`) whatever the settings say. `RefusedTenants` only adds names.')

    $sections = @(
        @{ Name = 'Shared'; Title = 'Shared settings'; Intro = 'Written at the top of the file.' }
        @{ Name = 'Scan'; Title = 'Scan section'; Intro = 'Written inside `Scan = @{ ... }`. Only the Scan phase uses them.' }
        @{ Name = 'Act'; Title = 'Act section'; Intro = 'Written inside `Act = @{ ... }`. Only the Act phase uses them.' }
    )

    foreach ($section in $sections) {
        $lines.Add('')
        $lines.Add("## $($section.Title)")
        $lines.Add('')
        $lines.Add($section.Intro)
        $lines.Add('')
        $lines.Add('| Setting | Type | Default | Required in | Used by | Description |')
        $lines.Add('|---------|------|---------|-------------|---------|-------------|')
        foreach ($row in @($schema | Where-Object { $_.Section -eq $section.Name })) {
            $required = & $phaseText @($row.RequiredIn)
            $used = & $phaseText @($row.UsedIn)
            $lines.Add("| ``$($row.Name)`` | $(& $typeText $row) | $($row.DefaultText) | $required | $used | $($row.Description) |")
        }
    }

    $lines.Add('')
    $lines.Add('## Checks across settings')
    $lines.Add('')
    $lines.Add('- The Scan phase needs at least one activity report (`SharePointUsageReport`, `TeamsActivityReport` or `GroupsActivityReport`). Without one, the tool cannot tell which sites are inactive.')
    $lines.Add('- `GrantSiteAdmin` requires `UnlockBeforeArchive`, because a read-only site refuses a change of owners.')
    $lines.Add('- `TenantName` must not be a refused tenant.')
    $lines.Add('')

    $lines -join "`n"
}
