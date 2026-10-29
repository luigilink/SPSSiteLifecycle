# Runs one case of the diagnosis under the external monitor.
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('full', 'file', 'test', 'scaling', 'raw', 'others', 'import')]
    [string]
    $Case
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
Set-Location -LiteralPath $root

$logPath = Join-Path -Path $env:RUNNER_TEMP -ChildPath 'monitor.log'
$arguments = @('-NoProfile', '-File', (Join-Path -Path $PSScriptRoot -ChildPath 'monitor.ps1'), '-TargetPid', $PID, '-Label', $Case, '-LogPath', $logPath)
$monitor = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -PassThru -NoNewWindow

if ($Case -in 'scaling', 'raw', 'others', 'import') {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'scaling.ps1') -Stage $Case
    exit 0
}

Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = if ($Case -eq 'full') { './tests' } else { './tests/StrictCsv.Tests.ps1' }
if ($Case -eq 'test') {
    $config.Filter.FullName = '*reads 260,000 records*'
}

$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
