#Requires -Version 7.4

<#
    .SYNOPSIS
    SPSSiteLifecycle: finds the SharePoint Online sites that are read-only or inactive, and writes a report that a person reviews.

    .DESCRIPTION
    Two phases, with a CSV file that a person reviews between them (see wiki/Design-Decisions.md):

    - Scan reads the tenant and the reports of the settings, gives each site a verdict, and writes the CSV report in the output
      folder. It only reads: nothing is changed in the tenant. A sign-in window opens (interactive sign-in of PnP.PowerShell,
      with the app registration of the settings), once the settings and the files have been checked.
    - Act applies the decisions that a person wrote in the CSV. It is not available in this version.

    Everything else is a setting, in the settings file (see the Configuration page of the wiki and
    src/config/SPSSiteLifecycle.example.psd1): the script has no other parameter, so that what a run can do is written
    in a file that can be reviewed.

    The script writes what it did as information (shown by default; -InformationAction SilentlyContinue hides it), and
    exits with 0 when the phase ended, and with 1 on any error, after a message that says what stopped it.

    .PARAMETER ConfigFile
    The settings file (.psd1). A relative path in it is relative to the folder of this file.

    .PARAMETER Phase
    Scan or Act.

    .EXAMPLE
    pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $ConfigFile,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Scan', 'Act')]
    [System.String]
    $Phase
)

$ErrorActionPreference = 'Stop'

# What a run did is information, shown unless the person who runs it asks otherwise.
$informationAction = if ($PSBoundParameters.ContainsKey('InformationAction')) { $InformationPreference } else { 'Continue' }

try {
    if ($Phase -eq 'Act') {
        throw 'The Act phase is not available in this version. Run -Phase Scan: it writes the report that the Act phase will read.'
    }

    # A copy of the module that is already loaded from this very folder is used as it is.
    $manifest = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1')).ProviderPath
    $moduleFolder = [System.IO.Path]::GetDirectoryName($manifest)
    $loaded = @(Get-Module -Name 'SPSSiteLifecycle.Common') | Where-Object { [System.String]::Equals($_.ModuleBase, $moduleFolder, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $loaded) {
        $loaded = Import-Module -Name $manifest -Force -PassThru
    }

    $null = & $loaded.ExportedCommands['Invoke-SPSLifecycleScan'] -ConfigFile $ConfigFile -InformationAction $informationAction
    exit 0
}
catch {
    Write-Verbose -Message "$($_.ScriptStackTrace)"
    $hint = if ($Phase -eq 'Scan') { ' Nothing was changed in the tenant: the Scan only reads. Fix the problem and run it again.' } else { '' }
    Write-Error -Message "SPSSiteLifecycle stopped: $($_.Exception.Message)$hint" -ErrorAction Continue
    exit 1
}
