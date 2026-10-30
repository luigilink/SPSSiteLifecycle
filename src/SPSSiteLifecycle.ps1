#Requires -Version 7.4

<#
    .SYNOPSIS
    SPSSiteLifecycle: finds the SharePoint Online sites that are read-only or inactive, writes a report that a person reviews, and applies what the person decided.

    .DESCRIPTION
    Two phases, with a CSV file that a person reviews between them (see wiki/Design-Decisions.md):

    - Scan reads the tenant and the reports of the settings, gives each site a verdict, and writes the CSV report in the output
      folder. It only reads: nothing is changed in the tenant. A sign-in window opens (interactive sign-in of PnP.PowerShell,
      with the app registration of the settings), once the settings and the files have been checked.
    - Act applies the decisions that a person wrote in the Decision column of that CSV (Delete, Archive or Lock), after the person has
      filtered the report, filled in the column and saved it as CSV (Act.InputFile of the settings). It reads each site again right
      before its action. It only says what it would do unless Act.Execute is $true, and then it asks for the name of the tenant and for
      a phrase that carries the number of actions. It writes its own report (act-<time>.csv) as it goes.

    Everything else is a setting, in the settings file (see the Configuration page of the wiki and
    src/config/SPSSiteLifecycle.example.psd1): the script has no other parameter, so that what a run can do is written
    in a file that can be reviewed.

    The script writes what it did as information (shown by default; -InformationAction SilentlyContinue hides it). Its exit code is:

    - 0 when the phase ended as planned (an Act run in which some rows are skipped or to be reviewed is as planned);
    - 1 on any error, after a message that says what stopped it (the settings, a file, the sign-in, the confirmation, a tenant that
      does not answer): for the Scan, nothing was changed in the tenant;
    - 2 (Act only) when the run ended but at least one row failed or could not be read, or when it stopped after 3 errors in a row:
      a scheduler can tell it from a run that ended as planned, and the Act report says which rows.

    .PARAMETER ConfigFile
    The settings file (.psd1). A relative path in it is relative to the folder of this file.

    .PARAMETER Phase
    Scan or Act.

    .EXAMPLE
    pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan

    .EXAMPLE
    pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Act
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
    # A copy of the module that is already loaded from this very folder is used as it is.
    $manifest = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1')).ProviderPath
    $moduleFolder = [System.IO.Path]::GetDirectoryName($manifest)
    $loaded = @(Get-Module -Name 'SPSSiteLifecycle.Common') | Where-Object { [System.String]::Equals($_.ModuleBase, $moduleFolder, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $loaded) {
        $loaded = Import-Module -Name $manifest -Force -PassThru
    }

    if ($Phase -eq 'Scan') {
        $null = & $loaded.ExportedCommands['Invoke-SPSLifecycleScan'] -ConfigFile $ConfigFile -InformationAction $informationAction
        exit 0
    }

    $summary = & $loaded.ExportedCommands['Invoke-SPSLifecycleAct'] -ConfigFile $ConfigFile -InformationAction $informationAction
    $failed = [System.Int64]$summary.Counts['Failed'] + [System.Int64]$summary.Counts['ReadError']
    if ($failed -gt 0 -or $summary.StoppedBecause) {
        $what = if ($summary.StoppedBecause) { "stopped after 3 errors in a row, with $failed $(if ($failed -eq 1) { 'row' } else { 'rows' }) that failed or could not be read" } else { "ended, but $failed $(if ($failed -eq 1) { 'row' } else { 'rows' }) failed or could not be read" }
        Write-Warning -Message "SPSSiteLifecycle: the Act run $what. Read the Act report: $($summary.ReportPath)"
        exit 2
    }

    exit 0
}
catch {
    Write-Verbose -Message "$($_.ScriptStackTrace)"
    $hint = if ($Phase -eq 'Scan') { ' Nothing was changed in the tenant: the Scan only reads. Fix the problem and run it again.' } else { ' The Act report in the output folder, if it exists, says what was done before the error.' }
    Write-Error -Message "SPSSiteLifecycle stopped: $($_.Exception.Message)$hint" -ErrorAction Continue
    exit 1
}
