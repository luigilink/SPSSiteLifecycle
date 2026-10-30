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

    Context 'Calls that a name does not show' {
        BeforeAll {
            # What the structure test above cannot see: a command that is built at run time. In the files that are not adapters, a
            # command is called by its name, or through a variable that holds a script block that is written in the same file or
            # given as a parameter typed [ScriptBlock], and nothing evaluates text (Invoke-Expression, Invoke-Command,
            # [ScriptBlock]::Create, InvokeScript). This reads the syntax: it does not follow a value from one function to another,
            # so a caller that hands a text to a parameter typed [ScriptBlock] is not seen, and code review has to look at the
            # callers of the functions that take a script block (the pager and its progress handler).
            function script:Find-DynamicCall {
                param([string]$Text)

                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)

                # What holds a script block is kept for each function, and for what is outside the functions: a name that holds one in a
                # function says nothing about the same name in another. A scope is told by where its function starts, and by -1 outside
                # the functions. A script block that a function writes belongs to that function.
                $scopeOf = {
                    param($node)
                    for ($parent = $node.Parent; $null -ne $parent; $parent = $parent.Parent) {
                        if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                            return $parent.Extent.StartOffset
                        }
                    }

                    -1
                }

                # The names that hold a script block: parameters typed [ScriptBlock], variables that are given a script block that is
                # written in the file, and copies of those. A name that is also given anything else is not trusted.
                $blockNames = @{}
                foreach ($parameter in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
                    foreach ($attribute in $parameter.Attributes) {
                        if ($attribute -is [System.Management.Automation.Language.TypeConstraintAst] -and $attribute.TypeName.FullName -match '^(System\.Management\.Automation\.)?ScriptBlock$') {
                            $key = & $scopeOf $parameter
                            if (-not $blockNames.ContainsKey($key)) {
                                $blockNames[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                            }

                            $null = $blockNames[$key].Add($parameter.Name.VariablePath.UserPath)
                        }
                    }
                }

                $assignments = @{}
                foreach ($assignment in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                    $key = & $scopeOf $assignment
                    if (-not $assignments.ContainsKey($key)) {
                        $assignments[$key] = [System.Collections.Generic.List[System.Object]]::new()
                    }

                    $assignments[$key].Add($assignment)
                }

                foreach ($key in @($assignments.Keys)) {
                    if (-not $blockNames.ContainsKey($key)) {
                        $blockNames[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    }

                    $names = $blockNames[$key]
                    for ($round = 0; $round -lt 3; $round++) {
                        $candidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $others = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($assignment in $assignments[$key]) {
                            $right = $assignment.Right
                            if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) {
                                $right = $right.Expression
                            }

                            $left = $assignment.Left.VariablePath.UserPath
                            if ($right -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or
                                ($right -is [System.Management.Automation.Language.VariableExpressionAst] -and $names.Contains($right.VariablePath.UserPath))) {
                                $null = $candidates.Add($left)
                            }
                            else {
                                $null = $others.Add($left)
                            }
                        }

                        foreach ($name in $candidates) {
                            if (-not $others.Contains($name)) {
                                $null = $names.Add($name)
                            }
                        }

                        foreach ($name in $others) {
                            $null = $names.Remove($name)
                        }
                    }
                }

                $found = [System.Collections.Generic.List[string]]::new()
                foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $name = $command.GetCommandName()
                    if ($name) {
                        if ($name -match '^(Invoke-Expression|iex|Invoke-Command|icm|Add-Type|New-Object)$') {
                            $found.Add("the command $name")
                        }

                        continue
                    }

                    $target = $command.CommandElements[0]
                    if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        $names = $blockNames[(& $scopeOf $command)]
                        if ($null -ne $names -and $names.Contains($target.VariablePath.UserPath)) {
                            continue
                        }
                    }

                    $found.Add("a command that is not named and not a script block: $($target.Extent.Text)")
                }

                foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
                    $member = "$($call.Member.Extent.Text)"
                    if ($member -match '^(InvokeScript|NewScriptBlock|ExpandString|AddScript|AddCommand|CreateNestedPrompt)$') {
                        $found.Add("the method $member")
                    }

                    # The names of methods do not depend on the case, and a type that a variable holds, or that is made from a text, is not
                    # one that this test can read.
                    if ($call.Static) {
                        if ($call.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) {
                            $found.Add("a static call on something that is not a type that is written: $($call.Expression.Extent.Text)::$member")
                        }
                        elseif ([System.String]::Equals($member, 'Create', [System.StringComparison]::OrdinalIgnoreCase) -and $call.Expression.Extent.Text -match 'ScriptBlock|PowerShell') {
                            $found.Add("the method $($call.Expression.Extent.Text)::Create")
                        }
                    }
                }

                $found.ToArray()
            }

            # In the adapters, every call that reaches the tenant stops on an error: a command that writes an error and goes on can
            # give some sites, or no connection at all, and the code that follows would take that for the whole answer.
            function script:Find-TenantCallThatDoesNotStop {
                param([string]$Text)

                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
                $found = [System.Collections.Generic.List[string]]::new()
                foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $name = $command.GetCommandName()
                    if (-not $name -or $name -notmatch '^(.+-PnP.+|.+-Mg.+|Connect-.+|Invoke-RestMethod|Invoke-WebRequest)$') {
                        continue
                    }

                    $stops = $false
                    for ($i = 0; $i -lt $command.CommandElements.Count - 1; $i++) {
                        $element = $command.CommandElements[$i]
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -eq 'ErrorAction') {
                            $value = $command.CommandElements[$i + 1]
                            if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $value.Value -eq 'Stop') {
                                $stops = $true
                            }
                        }
                    }

                    if (-not $stops) {
                        $found.Add("$name")
                    }
                }

                $found.ToArray()
            }
        }

        It 'calls commands by name, or through a script block, outside the adapters' {
            $offenders = foreach ($file in $script:Files) {
                if ($file.FullName -match '[\\/]Private[\\/]Adapters[\\/]') {
                    continue
                }

                foreach ($use in Find-DynamicCall -Text ([System.IO.File]::ReadAllText($file.FullName))) {
                    "$($file.Name): $use"
                }
            }

            @($offenders) | Should -HaveCount 0
        }

        It 'sees a call that a name does not show: <Name>' -ForEach @(
            @{ Name = 'a command built from two texts'; Text = "`$c = 'Connect-' + 'PnPOnline'; & `$c -Interactive"; Expected = 1 }
            @{ Name = 'a command in a variable'; Text = "`$c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a command in parentheses'; Text = "& ('Connect-' + 'PnPOnline') -Interactive"; Expected = 1 }
            @{ Name = 'a command in a string'; Text = "& 'Connect-PnPOnline'"; Expected = 0 }
            @{ Name = 'the dot operator'; Text = "`$c = 'Connect-PnPOnline'; . `$c"; Expected = 1 }
            @{ Name = 'Invoke-Expression'; Text = "Invoke-Expression 'Connect-PnPOnline'"; Expected = 1 }
            @{ Name = 'its alias'; Text = "iex 'Connect-PnPOnline'"; Expected = 1 }
            @{ Name = 'Invoke-Command'; Text = "Invoke-Command -ScriptBlock { Connect-PnPOnline }"; Expected = 1 }
            @{ Name = 'a script block made from a text'; Text = "`$b = [scriptblock]::Create('Connect-PnPOnline'); & `$b"; Expected = 2 }
            @{ Name = 'InvokeScript'; Text = "`$ExecutionContext.InvokeCommand.InvokeScript('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'New-Object with a type that is a text'; Text = "New-Object 'Microsoft.SharePoint.Client.ClientContext'"; Expected = 1 }
            @{ Name = 'a variable that is a script block and then something else'; Text = "`$b = { 1 }; `$b = 'Connect-PnPOnline'; & `$b"; Expected = 1 }
            @{ Name = 'a script block that is written in the file'; Text = "`$b = { param(`$x) `$x }; & `$b 1"; Expected = 0 }
            @{ Name = 'a parameter that is typed as a script block'; Text = "param([System.Management.Automation.ScriptBlock]`$Source) & `$Source 1"; Expected = 0 }
            @{ Name = 'a parameter that is typed as a script block, in short'; Text = "param([scriptblock]`$Source) & `$Source 1"; Expected = 0 }
            @{ Name = 'a parameter that is not typed'; Text = "param(`$Source) & `$Source 1"; Expected = 1 }
            @{ Name = 'a copy of a parameter that is typed as a script block'; Text = "param([scriptblock]`$Source) `$handler = `$Source; & `$handler 1"; Expected = 0 }
            @{ Name = 'a copy of a parameter that is not typed'; Text = "param(`$Source) `$handler = `$Source; & `$handler 1"; Expected = 1 }
            @{ Name = 'a copy that is later given a text'; Text = "param([scriptblock]`$Source) `$handler = `$Source; `$handler = 'Connect-PnPOnline'; & `$handler"; Expected = 1 }
            @{ Name = 'a command called by its name'; Text = "Get-ChildItem -Path ."; Expected = 0 }
            @{ Name = 'a script block made from a text, with the method in lowercase'; Text = "[scriptblock]::create('Connect-' + 'PnPOnline').Invoke()"; Expected = 1 }
            @{ Name = 'a script block made from a text, with the method in capitals'; Text = "[ScriptBlock]::CREATE('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a PowerShell instance that is given a text'; Text = "[powershell]::create().AddScript('Connect-PnPOnline')"; Expected = 2 }
            @{ Name = 'a static call on a type that a variable holds'; Text = "`$t = [scriptblock]; `$t::Create('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a static call on a type that is made from a text'; Text = "([type]'System.Management.Automation.ScriptBlock')::Create('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a static call on a type that is written'; Text = "[System.String]::Equals('a', 'b')"; Expected = 0 }
            @{ Name = 'a parameter typed as a script block in one function and as a text in another'; Text = "function A { param([scriptblock]`$c) & `$c }`nfunction B { param([string]`$c) & `$c }"; Expected = 1 }
            @{ Name = 'a parameter typed as a script block in two functions'; Text = "function A { param([scriptblock]`$c) & `$c }`nfunction B { param([scriptblock]`$c) & `$c }"; Expected = 0 }
            @{ Name = 'a variable that is a script block in one function and a text in another'; Text = "function A { `$b = { 1 }; & `$b }`nfunction B { `$b = 'Connect-PnPOnline'; & `$b }"; Expected = 1 }
            @{ Name = 'a parameter of a function, used in a script block that the function writes'; Text = "function A { param([scriptblock]`$c) `$x = { & `$c }; & `$x }"; Expected = 0 }
            @{ Name = 'a parameter of the file, used in a function that does not have it'; Text = "param([scriptblock]`$c)`nfunction A { & `$c }"; Expected = 1 }
            @{ Name = 'a parameter of a function, with the parameters written after its name'; Text = "function A([scriptblock]`$c) { & `$c }"; Expected = 0 }
        ) {
            @(Find-DynamicCall -Text $Text) | Should -HaveCount $Expected
        }

        It 'stops on an error in every call of the adapters that reaches the tenant' {
            $offenders = foreach ($file in $script:Files) {
                if ($file.FullName -notmatch '[\\/]Private[\\/]Adapters[\\/]') {
                    continue
                }

                foreach ($call in Find-TenantCallThatDoesNotStop -Text ([System.IO.File]::ReadAllText($file.FullName))) {
                    "$($file.Name): $call"
                }
            }

            @($offenders) | Should -HaveCount 0
        }

        It 'sees a call that does not stop on an error: <Name>' -ForEach @(
            @{ Name = 'no ErrorAction'; Text = 'Connect-PnPOnline -Url $u'; Expected = 1 }
            @{ Name = 'ErrorAction Continue'; Text = 'Get-PnPContext -ErrorAction Continue'; Expected = 1 }
            @{ Name = 'ErrorAction SilentlyContinue'; Text = 'Invoke-PnPQuery -ErrorAction SilentlyContinue'; Expected = 1 }
            @{ Name = 'a splatted call with no ErrorAction'; Text = 'Get-PnPTenantSite @parameters'; Expected = 1 }
            @{ Name = 'ErrorAction Stop'; Text = 'Connect-PnPOnline -Url $u -ErrorAction Stop'; Expected = 0 }
            @{ Name = 'a splatted call with ErrorAction Stop'; Text = 'Get-PnPTenantSite @parameters -ErrorAction Stop'; Expected = 0 }
            @{ Name = 'a Graph command'; Text = 'Get-MgSite'; Expected = 1 }
            @{ Name = 'a web call'; Text = 'Invoke-RestMethod -Uri $u'; Expected = 1 }
            @{ Name = 'a command that is not a call to the tenant'; Text = 'Get-Date'; Expected = 0 }
            @{ Name = 'two calls, one of them stopping'; Text = 'Get-PnPContext -ErrorAction Stop; Invoke-PnPQuery'; Expected = 1 }
        ) {
            @(Find-TenantCallThatDoesNotStop -Text $Text) | Should -HaveCount $Expected
        }
    }

    Context 'The types of the tenant' {
        BeforeAll {
            # The commands are checked by name (see above). The types of the SharePoint admin API and of PnP.PowerShell are
            # checked here, in type expressions and in the names that a string holds, because a type can be used without a command.
            function script:Find-TenantTypeUse {
                param([string]$Text)
                $pattern = '^(Microsoft\.Online\.SharePoint|Microsoft\.SharePoint\.Client|PnP\.PowerShell|PnP\.Framework)(\.|$)'
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
                $uses = $ast.FindAll({
                        param($node)
                        ($node -is [System.Management.Automation.Language.TypeExpressionAst] -and $node.TypeName.FullName -match $pattern) -or
                        ($node -is [System.Management.Automation.Language.TypeConstraintAst] -and $node.TypeName.FullName -match $pattern) -or
                        ($node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match $pattern)
                    }, $true)
                @($uses | ForEach-Object { $_.Extent.Text })
            }
        }

        It 'keeps the types of the SharePoint admin API and of PnP.PowerShell in the adapters' {
            $offenders = foreach ($file in $script:Files) {
                if ($file.FullName -match '[\\/]Private[\\/]Adapters[\\/]') {
                    continue
                }

                foreach ($use in Find-TenantTypeUse -Text ([System.IO.File]::ReadAllText($file.FullName))) {
                    "$($file.Name): $use"
                }
            }

            @($offenders) | Should -HaveCount 0
        }

        It 'sees a type of the tenant wherever it is written: <Name>' -ForEach @(
            @{ Name = 'a static call'; Text = '[Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($context)'; Expected = 1 }
            @{ Name = 'a cast'; Text = '[Microsoft.SharePoint.Client.ClientContext]$context'; Expected = 1 }
            @{ Name = 'a parameter type'; Text = 'param([PnP.Framework.Entities.SiteEntity]$Site)'; Expected = 1 }
            @{ Name = 'a type name in a string'; Text = "'Microsoft.Online.SharePoint.TenantAdministration.Tenant' -as [type]"; Expected = 1 }
            @{ Name = 'a type of .NET'; Text = '[System.Guid]::Empty'; Expected = 0 }
            @{ Name = 'a message that names the module'; Text = "throw 'The types are not in this PnP.PowerShell.'"; Expected = 0 }
        ) {
            @(Find-TenantTypeUse -Text $Text) | Should -HaveCount $Expected
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
