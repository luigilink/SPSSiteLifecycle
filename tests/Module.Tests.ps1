BeforeAll {
    $script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common'
    $script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:ManifestPath -Force -PassThru

    # The files that the structure tests read, set here and not in a context, so that a test that is run alone does not read none and
    # pass for want of a file to look at.
    $script:Files = @(Get-ChildItem -Path $script:ModuleRoot -Filter '*.ps1' -Recurse)

    # The name that a command is called by, without the name of its module: Microsoft.PowerShell.Utility\Invoke-Expression is the same
    # command as Invoke-Expression. Nothing when the name is not written.
    function script:Get-CommandBaseName {
        param($Command)

        $name = $Command.GetCommandName()
        if ($name) {
            $name.Substring($name.LastIndexOf('\') + 1)
        }
    }

    # The name of a variable without its scope: $script:c, $local:c, $global:c and $private:c are written $c in the scope that they
    # name, and ${local:c} is the same variable as $local:c.
    function script:Get-VariableBaseName {
        param([string]$Path)

        [System.Text.RegularExpressions.Regex]::Replace($Path, '^(local|script|global|private|using|variable):', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
    }

    # The variable that a name stands for, and the scope that it lives in. A function writes its own variables; it writes one of the
    # file only when the name says so ($script:c), and the global scope is not the one of the file, so a name of the global scope is
    # given the scope of the file here and is never trusted when it is read (see Find-DynamicCall).
    function script:Get-VariableTarget {
        param([string]$Path, $Own)

        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        $qualifier = [System.Text.RegularExpressions.Regex]::Match($Path, '^(?<scope>local|script|global|private|using|variable):', $options)
        $scope = if ($qualifier.Success) { $qualifier.Groups['scope'].Value } else { '' }
        $outside = [System.String]::Equals($scope, 'script', [System.StringComparison]::OrdinalIgnoreCase) -or [System.String]::Equals($scope, 'global', [System.StringComparison]::OrdinalIgnoreCase)
        [PSCustomObject]@{
            Name   = Get-VariableBaseName -Path $Path
            Key    = if ($outside) { -1 } else { $Own }
            Global = [System.String]::Equals($scope, 'global', [System.StringComparison]::OrdinalIgnoreCase)
        }
    }

    # The commands that reach the tenant, outside the adapters: by the name that a command is called by.
    function script:Find-TenantCommandUse {
        param([string]$Text)

        $forbidden = '^(.+-PnP.+|.+-Mg.+|Connect-.+|Invoke-RestMethod|Invoke-WebRequest)$'
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errors)
        foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = Get-CommandBaseName -Command $command
            if ($name -and $name -match $forbidden) {
                $command.GetCommandName()
            }
        }
    }
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
            $offenders = foreach ($file in $script:Files) {
                if ($file.FullName -match '[\\/]Private[\\/]Adapters[\\/]') {
                    continue
                }

                foreach ($use in Find-TenantCommandUse -Text ([System.IO.File]::ReadAllText($file.FullName))) {
                    "$($file.Name): $use"
                }
            }

            @($offenders) | Should -HaveCount 0
        }

        It 'sees a command that reaches the tenant, whatever the way it is named: <Name>' -ForEach @(
            @{ Name = 'a command of PnP.PowerShell'; Text = 'Connect-PnPOnline'; Expected = 1 }
            @{ Name = 'a command of PnP.PowerShell, with the name of its module'; Text = 'PnP.PowerShell\Connect-PnPOnline -Interactive'; Expected = 1 }
            @{ Name = 'a command of Microsoft Graph'; Text = 'Get-MgSite'; Expected = 1 }
            @{ Name = 'a command of Microsoft Graph, with the name of its module'; Text = 'Microsoft.Graph.Sites\Get-MgSite'; Expected = 1 }
            @{ Name = 'a web call'; Text = 'Invoke-WebRequest -Uri $u'; Expected = 1 }
            @{ Name = 'a web call, with the name of its module'; Text = 'Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $u'; Expected = 1 }
            @{ Name = 'another web call, with the name of its module'; Text = 'Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri $u'; Expected = 1 }
            @{ Name = 'a command of the tenant that is written between quotes, with the name of its module'; Text = "& 'PnP.PowerShell\Connect-PnPOnline'"; Expected = 1 }
            @{ Name = 'a connection command of another module'; Text = 'Connect-ExchangeOnline'; Expected = 1 }
            @{ Name = 'a command of the tenant in a script block of another command'; Text = 'Get-Date | ForEach-Object { Connect-PnPOnline }'; Expected = 1 }
            @{ Name = 'a command that does not reach the tenant'; Text = 'Get-Date'; Expected = 0 }
            @{ Name = 'a command that does not reach the tenant, with the name of its module'; Text = 'Microsoft.PowerShell.Utility\Get-Date'; Expected = 0 }
            @{ Name = 'the name of a command in a text'; Text = "'Connect-PnPOnline'"; Expected = 0 }
        ) {
            @(Find-TenantCommandUse -Text $Text) | Should -HaveCount $Expected
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
                # the functions. A script block that a function writes belongs to that function, with its parameters and its variables.
                $scopeOf = {
                    param($node)
                    for ($parent = $node.Parent; $null -ne $parent; $parent = $parent.Parent) {
                        if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                            return $parent.Extent.StartOffset
                        }
                    }

                    -1
                }
                $nameSet = {
                    param($table, $key)
                    if (-not $table.ContainsKey($key)) {
                        $table[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    }

                    , $table[$key]
                }

                # The names that hold a script block: parameters typed [ScriptBlock], variables that are given a script block that is
                # written in the file, and copies of those. A name that is also written in a way that is not followed is not trusted: a
                # parameter of another type or with none (in a script block of the function too), the variable of a foreach, a variable
                # that Set-Variable, New-Variable and the like, a parameter such as -OutVariable or [ref] can write, a list assignment
                # or one with a type. When a name that is written is itself not written in the file, no name of the scope is trusted.
                $blockNames = @{}
                $forced = @{}
                $everything = @{}

                # A name that can be written in the scope of another function is not trusted anywhere in the file: the names that
                # Set-Variable and the like write (the scope is one of their parameters), that a reference or OutVariable gives, and
                # that the drive of the variables names (a variable is found in the scopes that enclose a function too). When such a
                # command writes a name that is not written, or has its arguments splatted, or Get-Variable or PSVariable gives the
                # object of a variable, no name is trusted in the file at all.
                $forcedFile = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $everywhere = $false
                foreach ($parameter in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
                    $key = & $scopeOf $parameter
                    $typed = $false
                    foreach ($attribute in $parameter.Attributes) {
                        if ($attribute -is [System.Management.Automation.Language.TypeConstraintAst] -and $attribute.TypeName.FullName -match '^(System\.Management\.Automation\.)?ScriptBlock$') {
                            $typed = $true
                        }
                    }

                    $null = (& $nameSet $(if ($typed) { $blockNames } else { $forced }) $key).Add((Get-VariableBaseName -Path $parameter.Name.VariablePath.UserPath))
                }

                foreach ($loop in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
                    $target = Get-VariableTarget -Path $loop.Variable.VariablePath.UserPath -Own (& $scopeOf $loop)
                    $null = (& $nameSet $forced $target.Key).Add($target.Name)
                }

                foreach ($reference in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ConvertExpressionAst] -and $n.Type.TypeName.Name -eq 'ref' -and $n.Child -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                    $null = $forcedFile.Add((Get-VariableBaseName -Path $reference.Child.VariablePath.UserPath))
                }

                foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $name = Get-CommandBaseName -Command $command
                    $elements = @($command.CommandElements | Select-Object -Skip 1)

                    # The object of a variable can be written, and which one is not followed (a variable is found in the scopes that
                    # enclose the function too): Get-Variable, like the object that PSVariable gives below, puts every name of the file in
                    # doubt.
                    if ($name -match '^(Get-Variable|gv)$') {
                        $everywhere = $true
                    }

                    if ($name -match '^(Set-Variable|New-Variable|Clear-Variable|Remove-Variable|sv|nv|clv|rv|set)$') {
                        foreach ($element in $elements) {
                            # An argument that is bound to its parameter by a colon (-Name:c) is the argument of the parameter, not
                            # an element of the command.
                            $value = $element
                            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                                if ($null -eq $element.Argument) {
                                    continue
                                }

                                $value = $element.Argument
                            }

                            if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $null = $forcedFile.Add((Get-VariableBaseName -Path $value.Value))
                            }
                            else {
                                $everywhere = $true
                            }
                        }
                    }

                    for ($i = 0; $i -lt $elements.Count; $i++) {
                        if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -match '^((Out|Error|Warning|Information|Info|Pipeline)[A-Za-z]*|ov|ev|wv|iv|pv)$') {
                            $value = if ($null -ne $elements[$i].Argument) { $elements[$i].Argument } elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1] } else { $null }
                            if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $null = $forcedFile.Add((Get-VariableBaseName -Path $value.Value.TrimStart('+')))
                            }
                            elseif ($null -ne $value -and $value -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                                $everywhere = $true
                            }
                        }
                    }
                }

                # A variable can be written by a path of its drive ('variable:c'): a path that names one puts that name in doubt, and one that
                # does not (the drive alone, or a text that holds a variable) puts every name of the scope in doubt. The drive of the
                # aliases makes a command that goes by another name, and PSVariable gives the object of a variable, which can be written.
                $drives = [System.Collections.Generic.List[string]]::new()
                $textOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                foreach ($literal in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) {
                    $drive = [System.Text.RegularExpressions.Regex]::Match($literal.Value, '^\s*variable:[\\/]?(?<name>.*)$', $textOptions)
                    if ($drive.Success) {
                        if ($drive.Groups['name'].Value -and $literal -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $null = $forcedFile.Add((Get-VariableBaseName -Path $drive.Groups['name'].Value))
                        }
                        else {
                            $everywhere = $true
                        }
                    }

                    if ([System.Text.RegularExpressions.Regex]::IsMatch($literal.Value, '^\s*alias:', $textOptions)) {
                        $drives.Add("the drive of the aliases: $($literal.Extent.Text)")
                    }
                }

                foreach ($member in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)) {
                    if ($member.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and [System.String]::Equals($member.Member.Value, 'PSVariable', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $everywhere = $true
                        $drives.Add('the object of a variable, from PSVariable')
                    }
                }

                $assignments = @{}
                foreach ($assignment in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                    $key = & $scopeOf $assignment
                    $left = $assignment.Left
                    if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        # The variable is kept with the scope that it lives in, which is the file for $script:c, and the scope of the
                        # assignment is kept for the variable that the right side reads.
                        $written = Get-VariableTarget -Path $left.VariablePath.UserPath -Own $key
                        if (-not $assignments.ContainsKey($written.Key)) {
                            $assignments[$written.Key] = [System.Collections.Generic.List[System.Object]]::new()
                        }

                        $assignments[$written.Key].Add([PSCustomObject]@{ Assignment = $assignment; Name = $written.Name; Scope = $key })
                        continue
                    }

                    # A list of variables, or a variable that has a type: written with something that is not followed.
                    $targets = if ($left -is [System.Management.Automation.Language.ArrayLiteralAst]) { @($left.Elements) } else { @($left) }
                    foreach ($target in $targets) {
                        if ($target -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                            $target = $target.Child
                        }

                        if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                            $written = Get-VariableTarget -Path $target.VariablePath.UserPath -Own $key
                            $null = (& $nameSet $forced $written.Key).Add($written.Name)
                        }
                    }
                }

                foreach ($key in @($assignments.Keys)) {
                    $names = & $nameSet $blockNames $key
                    for ($round = 0; $round -lt 3; $round++) {
                        $candidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $others = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($entry in $assignments[$key]) {
                            $right = $entry.Assignment.Right
                            if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) {
                                $right = $right.Expression
                            }

                            $copied = $false
                            if ($right -is [System.Management.Automation.Language.VariableExpressionAst]) {
                                $read = Get-VariableTarget -Path $right.VariablePath.UserPath -Own $entry.Scope
                                $copied = -not $read.Global -and (& $nameSet $blockNames $read.Key).Contains($read.Name)
                            }

                            if ($right -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $copied) {
                                $null = $candidates.Add($entry.Name)
                            }
                            else {
                                $null = $others.Add($entry.Name)
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

                $found = [System.Collections.Generic.List[string]]::new($drives)
                foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $name = Get-CommandBaseName -Command $command
                    if ($name) {
                        if ($name -match '^(Invoke-Expression|iex|Invoke-Command|icm|Add-Type|New-Object|Set-Alias|New-Alias|Import-Alias|sal|nal|ipal)$') {
                            $found.Add("the command $name")
                        }

                        continue
                    }

                    $target = $command.CommandElements[0]
                    if ($target -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        # A variable that is read with the scope of the file ($script:c) is the one of the file, and one of the global scope
                        # is never followed.
                        $read = Get-VariableTarget -Path $target.VariablePath.UserPath -Own (& $scopeOf $command)
                        if (-not $everywhere -and -not $read.Global -and -not $everything.ContainsKey($read.Key) -and (& $nameSet $blockNames $read.Key).Contains($read.Name) -and -not (& $nameSet $forced $read.Key).Contains($read.Name) -and -not $forcedFile.Contains($read.Name)) {
                            continue
                        }
                    }

                    $found.Add("a command that is not named and not a script block: $($target.Extent.Text)")
                }

                foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
                    # A method is named by a text that is written, whatever the quotes, or the test cannot tell what it calls.
                    if ($call.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $found.Add("a method whose name is not written: $($call.Member.Extent.Text)")
                        continue
                    }

                    $member = $call.Member.Value
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
                    $name = Get-CommandBaseName -Command $command
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
                        $found.Add($command.GetCommandName())
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
            @{ Name = 'a method whose name is written between single quotes'; Text = "[scriptblock]::'Create'('Connect-' + 'PnPOnline').Invoke()"; Expected = 1 }
            @{ Name = 'a method whose name is written between double quotes'; Text = "[scriptblock]::`"Create`"('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a method whose name is a variable'; Text = "`$name = 'Create'; [scriptblock]::`$name('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a method of an object whose name is a variable'; Text = "`$name = 'InvokeScript'; `$ExecutionContext.InvokeCommand.`$name('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a method that is dangerous, with its name between quotes'; Text = "`$ExecutionContext.InvokeCommand.'InvokeScript'('Connect-PnPOnline')"; Expected = 1 }
            @{ Name = 'a method that is not dangerous, with its name between quotes'; Text = "[System.String]::'Equals'('a', 'b')"; Expected = 0 }
            @{ Name = 'a variable that a script block was given and a foreach then holds'; Text = "`$c = { 1 }; foreach (`$c in @('Connect-' + 'PnPOnline')) { & `$c }"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and Set-Variable gives a text'; Text = "`$c = { 1 }; Set-Variable -Name c -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and its alias gives a text'; Text = "`$c = { 1 }; sv c 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and New-Variable gives a text'; Text = "`$c = { 1 }; New-Variable -Name c -Value 'Connect-PnPOnline' -Force; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and Set-Variable gives a text by a name that is not written'; Text = "`$c = { 1 }; `$n = 'c'; Set-Variable -Name `$n -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a reference to it is given to a function'; Text = "`$c = { 1 }; Update-Something ([ref]`$c); & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a parameter writes a variable of that name'; Text = "`$c = { 1 }; Get-Date -OutVariable c | Out-Null; & `$c"; Expected = 1 }
            @{ Name = 'the same, with the short name of the parameter'; Text = "`$c = { 1 }; Get-Date -ov c | Out-Null; & `$c"; Expected = 1 }
            @{ Name = 'the same, with the error variable'; Text = "`$c = { 1 }; Get-Item nothing -ErrorVariable c -ErrorAction SilentlyContinue; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a list assignment gives it a text'; Text = "`$c = { 1 }; `$a, `$c = 'x', 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a typed assignment gives it a text'; Text = "`$c = { 1 }; [string]`$c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a parameter of a function, that a script block of the function declares again without a type'; Text = "function A { param([scriptblock]`$c) `$x = { param(`$c) & `$c }; & `$x 'Connect-PnPOnline' }"; Expected = 1 }
            @{ Name = 'a parameter of a function, and a script block of the function that has another parameter'; Text = "function A { param([scriptblock]`$c) `$x = { param(`$other) `$other }; & `$c }"; Expected = 0 }
            @{ Name = 'a call operator on a member of an object'; Text = "& `$object.Command 'x'"; Expected = 1 }
            @{ Name = 'a script block that is written in the file and a foreach with another name'; Text = "`$c = { 1 }; foreach (`$item in 1..3) { & `$c }"; Expected = 0 }
            @{ Name = 'a script block that is written in the file and a parameter that writes another name'; Text = "`$c = { 1 }; Get-Date -OutVariable other | Out-Null; & `$c"; Expected = 0 }
            @{ Name = 'Set-Variable with its arguments bound by a colon'; Text = "`$c = { 1 }; Set-Variable -Name:c -Value:'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'Set-Variable with the name bound by a colon and the value after it'; Text = "`$c = { 1 }; Set-Variable -Name:c 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'Set-Variable with a name that is not written, bound by a colon'; Text = "`$c = { 1 }; `$n = 'c'; Set-Variable -Name:`$n -Value:'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'Set-Variable with a list of names, bound by a colon'; Text = "`$c = { 1 }; Set-Variable -Name:@('c', 'd') -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'its alias with the short names of the parameters, bound by a colon'; Text = "`$c = { 1 }; sv -n:c -va:'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'Set-Variable with a colon, for a name that is not the script block'; Text = "`$c = { 1 }; Set-Variable -Name:other -Value:'x'; & `$c"; Expected = 0 }
            @{ Name = 'Set-Variable called with the name of its module'; Text = "`$c = { 1 }; Microsoft.PowerShell.Utility\Set-Variable -Name c -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'its alias called with the name of its module'; Text = "`$c = { 1 }; Microsoft.PowerShell.Utility\sv c 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'Invoke-Expression called with the name of its module'; Text = "Microsoft.PowerShell.Utility\Invoke-Expression 'Connect-PnPOnline'"; Expected = 1 }
            @{ Name = 'Invoke-Command called with the name of its module'; Text = "Microsoft.PowerShell.Core\Invoke-Command -ScriptBlock { 1 }"; Expected = 1 }
            @{ Name = 'New-Object called with the name of its module'; Text = "Microsoft.PowerShell.Utility\New-Object 'Microsoft.SharePoint.Client.ClientContext'"; Expected = 1 }
            @{ Name = 'a command that is not dangerous, called with the name of its module'; Text = "Microsoft.PowerShell.Utility\Get-Date"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and a variable of the local scope gives it a text'; Text = "`$c = { 1 }; `$local:c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a variable of the script scope gives it a text'; Text = "`$c = { 1 }; `$script:c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a variable of the global scope gives it a text'; Text = "`$c = { 1 }; `$global:c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a private variable gives it a text'; Text = "`$c = { 1 }; `$private:c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a variable between braces gives it a text'; Text = "`$c = { 1 }; `${local:c} = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that is a script block, and is called with its scope'; Text = "`$script:c = { 1 }; & `$script:c"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and is called with a scope'; Text = "`$c = { 1 }; & `$script:c"; Expected = 0 }
            @{ Name = 'a variable of the script scope that is a script block, and is called without it'; Text = "`$script:c = { 1 }; & `$c"; Expected = 0 }
            @{ Name = 'a parameter typed as a script block, and called with a scope'; Text = "function A { param([scriptblock]`$c) & `$local:c }"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and a foreach holds it with a scope'; Text = "`$c = { 1 }; foreach (`$script:c in @('Connect-' + 'PnPOnline')) { & `$c }"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a list assignment gives it a text with a scope'; Text = "`$c = { 1 }; `$a, `$script:c = 'x', 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a typed assignment gives it a text with a scope'; Text = "`$c = { 1 }; [string]`$script:c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a reference to it is given with a scope'; Text = "`$c = { 1 }; Update-Something ([ref]`$script:c); & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and Set-Variable gives a text by a name with a scope'; Text = "`$c = { 1 }; Set-Variable -Name script:c -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a parameter writes a variable of that name with a scope'; Text = "`$c = { 1 }; Get-Date -OutVariable script:c | Out-Null; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and Set-Item writes it by the drive of the variables'; Text = "`$c = { 1 }; Set-Item variable:c 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a path of the drive of the variables is in quotes'; Text = "`$c = { 1 }; Set-Item -Path 'Variable:\c' -Value 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a path of the drive of the variables is bound by a colon'; Text = "`$c = { 1 }; Set-Item -Path:variable:c 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and New-Item gives the drive of the variables and a name'; Text = "`$c = { 1 }; New-Item -Path variable: -Name c -Value 'Connect-PnPOnline' -Force; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and a path of the drive of the variables is a string with a variable'; Text = "`$c = { 1 }; `$n = 'c'; Set-Item `"variable:`$n`" 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a path that is not the drive of the variables'; Text = "`$c = { 1 }; Get-Content 'file.txt'; & `$c"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and the object of another variable is written'; Text = "`$c = { 1 }; (Get-Variable c).Value = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and the object of another variable is written, by the alias'; Text = "`$c = { 1 }; (gv c).Value = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and PSVariable writes it'; Text = "`$c = { 1 }; `$ExecutionContext.SessionState.PSVariable.Set('c', 'Connect-PnPOnline'); & `$c"; Expected = 2 }
            @{ Name = 'an alias that is made for a command'; Text = "Set-Alias Get-Thing Connect-PnPOnline"; Expected = 1 }
            @{ Name = 'an alias that is made with New-Alias'; Text = "New-Alias -Name Get-Thing -Value Connect-PnPOnline"; Expected = 1 }
            @{ Name = 'an alias that is made with its own alias'; Text = "nal Get-Thing Connect-PnPOnline"; Expected = 1 }
            @{ Name = 'an alias that is made with the name of its module'; Text = "Microsoft.PowerShell.Utility\Set-Alias Get-Thing Connect-PnPOnline"; Expected = 1 }
            @{ Name = 'an alias that is made by the drive of the aliases'; Text = "Set-Item alias:Get-Thing Connect-PnPOnline"; Expected = 1 }
            @{ Name = 'a script block of a command that holds a foreach that writes the variable'; Text = "`$c = { 1 }; Get-Date | ForEach-Object { foreach (`$c in @('Connect-' + 'PnPOnline')) { } }; & `$c"; Expected = 1 }
            @{ Name = 'a script block of a command that gives a reference to the variable'; Text = "`$c = { 1 }; Get-Date | ForEach-Object { Update-Something ([ref]`$c) }; & `$c"; Expected = 1 }
            @{ Name = 'a script block of a command that gives a text to the variable with Set-Variable'; Text = "`$c = { 1 }; Get-Date | ForEach-Object { Set-Variable -Name c -Value 'Connect-PnPOnline' }; & `$c"; Expected = 1 }
            @{ Name = 'a script block of a command that writes the variable by the drive of the variables'; Text = "`$c = { 1 }; Get-Date | ForEach-Object { Set-Item variable:c 'Connect-PnPOnline' }; & `$c"; Expected = 1 }
            @{ Name = 'a script block of a command that writes the variable through PSVariable'; Text = "`$c = { 1 }; Get-Date | ForEach-Object { `$ExecutionContext.SessionState.PSVariable.Set('c', 'x') }; & `$c"; Expected = 2 }
            @{ Name = 'a script block of a command that makes a script block from a text'; Text = "Get-Date | ForEach-Object { [scriptblock]::Create('Connect-PnPOnline') }"; Expected = 1 }
            @{ Name = 'a script block of a command that evaluates a text'; Text = "Get-Date | ForEach-Object { Invoke-Expression 'Connect-PnPOnline' }"; Expected = 1 }
            @{ Name = 'a variable that is a script block, written with another case, and called with a third'; Text = "`$Handler = { 1 }; `$handler = 'Connect-PnPOnline'; & `$HANDLER"; Expected = 1 }
            @{ Name = 'a copy of a script block, written with another case'; Text = "`$c = { 1 }; `$d = `$C; & `$D"; Expected = 0 }
            @{ Name = 'PSVariable written in lowercase'; Text = "`$c = { 1 }; `$ExecutionContext.SessionState.psvariable.Set('c', 'x'); & `$c"; Expected = 2 }
            @{ Name = 'a variable that is a script block, and a cast of it to another type'; Text = "`$c = { 1 }; `$x = [object]`$c; & `$c"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and Set-Variable writes another name'; Text = "`$c = { 1 }; Set-Variable -Name d -Value 'y'; & `$c"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and OutVariable writes a name that is a variable'; Text = "`$c = { 1 }; `$n = 'c'; Get-Date -OutVariable `$n | Out-Null; & `$c"; Expected = 1 }
            @{ Name = 'a function whose variable is written by the drive of the variables, and a command outside it'; Text = "function A { `$c = { 1 }; Set-Item variable:c 'Connect-PnPOnline'; & `$c }`n`$d = 'x'; Get-Date"; Expected = 1 }
            @{ Name = 'a parameter that is typed as a script block, and is given a text'; Text = "param([scriptblock]`$c) `$c = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a parameter of a function that is typed as a script block, and is given a text'; Text = "function A { param([scriptblock]`$c) `$c = 'Connect-PnPOnline'; & `$c }"; Expected = 1 }
            @{ Name = 'a static method of a type that a variable holds, whose name is a variable'; Text = "`$t = [scriptblock]; `$name = 'Create'; `$t::`$name('x')"; Expected = 1 }
            @{ Name = 'a static method Create of another type'; Text = "[System.IO.File]::Create('a')"; Expected = 0 }
            @{ Name = 'a static method of the type of a script block, that is not Create'; Text = "[scriptblock]::Equals('a', 'b')"; Expected = 0 }
            @{ Name = 'a variable that is a script block, and the same variable written with another case is given a text'; Text = "`$c = { 1 }; `$C = 'Connect-PnPOnline'; & `$c"; Expected = 1 }
            @{ Name = 'a variable that is a script block, and OutVariable has no value but is followed by another parameter'; Text = "`$c = { 1 }; Get-Date -OutVariable -Verbose; & `$c"; Expected = 0 }
            @{ Name = 'a variable of the script scope that a function gives a text'; Text = "`$c = { 1 }`nfunction A { `$script:c = 'Connect-PnPOnline' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a function gives a text, with the scope in capitals'; Text = "`$c = { 1 }`nfunction A { `$SCRIPT:c = 'Connect-PnPOnline' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable that a function gives a text in the global scope'; Text = "`$c = { 1 }`nfunction A { `$global:c = 'Connect-PnPOnline' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a function gives a script block'; Text = "`$c = { 1 }`nfunction A { `$script:c = { 2 } }`nA`n& `$c"; Expected = 0 }
            @{ Name = 'a variable that a function gives a text in its own scope, and that of the file stays a script block'; Text = "`$c = { 1 }`nfunction A { `$local:c = 'x' }`nA`n& `$c"; Expected = 0 }
            @{ Name = 'a variable that a function gives a text as a private one'; Text = "`$c = { 1 }`nfunction A { `$private:c = 'x' }`nA`n& `$c"; Expected = 0 }
            @{ Name = 'a variable of the script scope that Set-Variable gives a text in a function'; Text = "`$c = { 1 }`nfunction A { Set-Variable -Name c -Scope Script -Value 'Connect-PnPOnline' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the global scope that Set-Variable gives a text in a function, with the scope bound by a colon'; Text = "`$c = { 1 }`nfunction A { Set-Variable -Scope:Global -Name c -Value 'x' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the caller of a function that Set-Variable gives a text'; Text = "function A { `$c = { 1 }; B; & `$c }`nfunction B { Set-Variable -Name c -Scope 1 -Value 'Connect-PnPOnline' }"; Expected = 1 }
            @{ Name = 'a variable that Set-Variable gives a text by a name that is not written, in another scope'; Text = "`$c = { 1 }`nfunction A { `$n = 'c'; Set-Variable -Name `$n -Scope Script -Value 'x' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable that Set-Variable gives a text with its arguments splatted, in a function'; Text = "`$c = { 1 }`nfunction A { Set-Variable @args }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of another scope that the object of Get-Variable writes'; Text = "`$c = { 1 }`nfunction A { Get-Variable c -Scope Script | ForEach-Object { `$_.Value = 'x' } }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that OutVariable writes in a function'; Text = "`$c = { 1 }`nfunction A { Get-Date -OutVariable script:c | Out-Null }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a reference is given for, in a function'; Text = "`$c = { 1 }`nfunction A { Update-Something ([ref]`$script:c) }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a foreach holds, in a function'; Text = "`$c = { 1 }`nfunction A { foreach (`$script:c in 'x') { } }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a typed assignment gives a text, in a function'; Text = "`$c = { 1 }`nfunction A { [string]`$script:c = 'x' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a list assignment gives a text, in a function'; Text = "`$c = { 1 }`nfunction A { `$x, `$script:c = 'x', 'y' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a call through the script scope, and a variable of the function that is a script block'; Text = "function A { `$c = { 1 }; & `$script:c }"; Expected = 1 }
            @{ Name = 'a call through the script scope, and a variable of the file that is a script block'; Text = "`$c = { 1 }`nfunction A { & `$script:c }"; Expected = 0 }
            @{ Name = 'a call through the script scope, and a variable of the function that is a text'; Text = "`$script:c = { 1 }`nfunction A { `$c = 'x'; & `$script:c }"; Expected = 0 }
            @{ Name = 'a call through the script scope, and a variable of the file that a function gives a text'; Text = "`$c = { 1 }`nfunction A { `$c = 'x'; & `$script:c }"; Expected = 0 }
            @{ Name = 'a call through the global scope'; Text = "`$c = { 1 }`nfunction A { & `$global:c }"; Expected = 1 }
            @{ Name = 'a call through the script scope of a variable that the file gives a text'; Text = "`$c = 'Connect-PnPOnline'`nfunction A { `$c = { 1 }; & `$script:c }"; Expected = 1 }
            @{ Name = 'a variable of the script scope that a function gives a text, with the global scope in capitals'; Text = "`$c = { 1 }`nfunction A { `$GLOBAL:c = 'Connect-PnPOnline' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a call through the global scope, written in capitals'; Text = "`$c = { 1 }`nfunction A { & `$GLOBAL:c }"; Expected = 1 }
            @{ Name = 'a variable of a function that another function gives a text with Set-Variable, the name in another case'; Text = "function A { `$c = { 1 }; B; & `$c }`nfunction B { Set-Variable -Name C -Scope 1 -Value 'x' }"; Expected = 1 }
            @{ Name = 'a variable of a function that another function writes by the drive of the variables'; Text = "function A { `$c = { 1 }; B; & `$c }`nfunction B { Set-Item variable:c 'x' }"; Expected = 1 }
            @{ Name = 'a variable of a function that another function gives a text with Set-Variable, in its own scope and with the name in another case'; Text = "function A { `$c = { 1 }; B; & `$c }`nfunction B { Set-Variable -Name C -Scope Local -Value 'x' }"; Expected = 1 }
            @{ Name = 'a variable of the file that a function writes through a reference'; Text = "`$c = { 1 }`nfunction A { Update-Something ([ref]`$c) }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the file that a function writes with OutVariable'; Text = "`$c = { 1 }`nfunction A { Get-Date -OutVariable c | Out-Null }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable of the file that the object of Get-Variable writes in a function, with no scope given'; Text = "`$c = { 1 }`nfunction A { (Get-Variable c).Value = 'x' }`nA`n& `$c"; Expected = 1 }
            @{ Name = 'a variable that a list assignment gives a text, after the assignment of another one'; Text = "`$c = { 1 }; `$d = { 2 }; `$a, `$c = 'x', 'Connect-PnPOnline'; & `$c"; Expected = 1 }
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
            @{ Name = 'a call with the name of its module, and no ErrorAction'; Text = 'PnP.PowerShell\Connect-PnPOnline -Url $u'; Expected = 1 }
            @{ Name = 'a call with the name of its module, and ErrorAction Stop'; Text = 'PnP.PowerShell\Connect-PnPOnline -Url $u -ErrorAction Stop'; Expected = 0 }
            @{ Name = 'a web call with the name of its module, and no ErrorAction'; Text = 'Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri $u'; Expected = 1 }
            @{ Name = 'a web call with the name of its module, and ErrorAction Stop'; Text = 'Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $u -ErrorAction Stop'; Expected = 0 }
            @{ Name = 'a call of Graph with the name of its module, and no ErrorAction'; Text = 'Microsoft.Graph.Sites\Get-MgSite'; Expected = 1 }
            @{ Name = 'a call in a script block of another command, and no ErrorAction'; Text = 'Get-Date | ForEach-Object { Connect-PnPOnline -Url $u }'; Expected = 1 }
            @{ Name = 'a call in which another parameter is given Stop'; Text = 'Connect-PnPOnline -Url $u -Mode Stop'; Expected = 1 }
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
