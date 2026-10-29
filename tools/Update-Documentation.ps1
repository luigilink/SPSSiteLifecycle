<#
    .SYNOPSIS
    Regenerates the Configuration, Verdicts and Report pages of the wiki.

    .DESCRIPTION
    The pages are built from data of the module: the settings schema, the verdict catalog and the table
    of the report columns.
    A test fails when a committed page differs from what this script writes, so run it after any
    change to the schema or the catalog, and commit the result.

    .PARAMETER WikiFolder
    The folder that holds the wiki pages. A relative folder is relative to the location of the PowerShell
    session. Default: the wiki folder of the repository.

    .EXAMPLE
    ./tools/Update-Documentation.ps1
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $WikiFolder = (Join-Path -Path $PSScriptRoot -ChildPath '../wiki')
)

$ErrorActionPreference = 'Stop'

$manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
$module = Import-Module -Name $manifest -Force -PassThru

$pages = [ordered]@{
    'Configuration.md' = & $module { Get-SPSLifecycleConfigurationPage }
    'Verdicts.md'      = & $module { Get-SPSLifecycleVerdictPage }
    'Report.md'        = & $module { Get-SPSLifecycleReportPage }
}

$encoding = [System.Text.UTF8Encoding]::new($false)
$folder = & $module { param($path) Resolve-SPSLifecycleFileSystemPath -Path $path } $WikiFolder
foreach ($name in $pages.Keys) {
    $path = Join-Path -Path $folder -ChildPath $name
    [System.IO.File]::WriteAllText($path, $pages[$name], $encoding)
    Write-Output "Wrote $path"
}
