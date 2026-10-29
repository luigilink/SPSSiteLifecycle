BeforeAll {
    $script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common'
    $script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:ManifestPath -Force -PassThru
}

Describe 'The SPSSiteLifecycle.Common module' {
    Context 'Manifest' {
        It 'is a valid manifest' {
            { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'has a version number' {
            $data = Import-PowerShellDataFile -Path $script:ManifestPath
            { [System.Version]$data.ModuleVersion } | Should -Not -Throw
        }

        It 'requires PowerShell 7.4, as PnP.PowerShell 3.x does' {
            $data = Import-PowerShellDataFile -Path $script:ManifestPath
            $data.PowerShellVersion | Should -Be '7.4'
        }
    }

    Context 'Exports' {
        It 'exports exactly the functions of the Public folder' {
            $publicNames = @(Get-ChildItem -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Public') -Filter '*.ps1' -Recurse | ForEach-Object { $_.BaseName } | Sort-Object)
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $listed = @($manifest.FunctionsToExport | Sort-Object)
            $exported = @(Get-Command -Module $script:Module.Name | ForEach-Object { $_.Name } | Sort-Object)

            ($listed -join ',') | Should -Be ($publicNames -join ',')
            ($exported -join ',') | Should -Be ($publicNames -join ',')
        }

        It 'does not export private functions' {
            Get-Command -Name 'ConvertTo-SPSLifecycleDate' -Module $script:Module.Name -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Function files' {
        BeforeAll {
            $script:Files = @(Get-ChildItem -Path $script:ModuleRoot -Filter '*.ps1' -Recurse)
        }

        It 'has function files' {
            $script:Files.Count | Should -BeGreaterThan 0
        }

        It 'holds one function per file, named like the file' {
            $problems = foreach ($file in $script:Files) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
                if ($errors.Count -gt 0) {
                    "$($file.Name): syntax error"
                }
                elseif ($functions.Count -ne 1 -or $functions[0].Name -ne $file.BaseName) {
                    "$($file.Name): expected one function named $($file.BaseName)"
                }
            }

            @($problems) | Should -HaveCount 0
        }

        It 'lets only the adapter functions reach the tenant (PnP.PowerShell, Microsoft Graph, web calls)' {
            $forbidden = '^(.+-PnP.+|.+-Mg.+|Connect-.+|Invoke-RestMethod|Invoke-WebRequest)$'
            $offenders = foreach ($file in $script:Files) {
                if ($file.FullName -match '[\\/]Private[\\/]Adapters[\\/]') {
                    continue
                }

                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($command in $commands) {
                    $name = $command.GetCommandName()
                    if ($name -and $name -match $forbidden) {
                        "$($file.Name): $name"
                    }
                }
            }

            @($offenders) | Should -HaveCount 0
        }
    }

    Context 'Paths' {
        It 'resolves a path in PowerShell before a .NET file method uses it, because those methods ignore Set-Location' {
            $files = @($script:Files) + @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../tools') -Filter '*.ps1')
            $typed = '^(System\.)?IO\.(File|Directory|FileInfo|DirectoryInfo|FileStream|StreamReader|StreamWriter)$'
            $path = '^(System\.)?IO\.Path$'
            $offenders = foreach ($file in $files) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
                $calls = @($ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                            $node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                            ($node.Expression.TypeName.FullName -match $typed -or
                            ($node.Expression.TypeName.FullName -match $path -and $node.Member.Extent.Text -eq 'GetFullPath'))
                        }, $true))
                $resolvers = @($ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Resolve-SPSLifecycleFileSystemPath'
                        }, $true))
                if ($calls.Count -gt 0 -and $resolvers.Count -eq 0) {
                    "$($file.Name): $($calls[0].Extent.Text)"
                }
            }

            @($offenders) | Should -HaveCount 0 -Because 'a relative path must go through Resolve-SPSLifecycleFileSystemPath first'
        }
    }

    Context 'Offline loading' {
        It 'loads without PnP.PowerShell or Microsoft Graph' {
            $pwsh = Join-Path -Path $PSHOME -ChildPath 'pwsh'
            $command = "Import-Module -Name '$($script:ManifestPath)' -Force; @(Get-Module | Where-Object { `$_.Name -like 'PnP*' -or `$_.Name -like 'Microsoft.Graph*' }).Count"
            $output = & $pwsh -NoProfile -NonInteractive -Command $command

            $LASTEXITCODE | Should -Be 0
            "$output".Trim() | Should -Be '0'
        }
    }
}
