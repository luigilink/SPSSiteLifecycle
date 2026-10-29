<#
    .SYNOPSIS
    Regenerates the Configuration and Verdicts pages of the wiki.

    .DESCRIPTION
    Both pages are built from data of the module: the settings schema and the verdict catalog.
    A test fails when a committed page differs from what this script writes, so run it after any
    change to the schema or the catalog, and commit the result.

    .PARAMETER WikiFolder
    The folder that holds the wiki pages. Default: the wiki folder of the repository.

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
}

$encoding = [System.Text.UTF8Encoding]::new($false)
$folder = [System.IO.Path]::GetFullPath($WikiFolder)
foreach ($name in $pages.Keys) {
    $path = Join-Path -Path $folder -ChildPath $name
    [System.IO.File]::WriteAllText($path, $pages[$name], $encoding)
    Write-Output "Wrote $path"
}
