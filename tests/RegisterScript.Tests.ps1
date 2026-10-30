BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Script = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../src/Register-SPSSiteLifecycleApp.ps1')).ProviderPath
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    # Runs the script in this process, where the module that is loaded is the one of the repository and its adapters are stubbed, and gives
    # its exit code, the lines of information that it wrote, its errors and what else it wrote.
    function script:Invoke-RegisterScript {
        param([hashtable]$Parameter)

        $global:LASTEXITCODE = $null
        $output = @(& $script:Script @Parameter 2>&1 3>&1 6>&1)
        [PSCustomObject]@{
            ExitCode = $global:LASTEXITCODE
            Info     = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })
            Errors   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$($_.Exception.Message)" })
            Other    = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] -and $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
            Log      = @(Get-StubLog)
        }
    }

    function script:Set-RegisterStub {
        param([string]$Fail = '', [string[]]$Answer = @('contoso'))

        Set-ModuleStub -Stub @{
            'Assert-SPSLifecyclePnPModule'  = @'
$script:StubLog.Add('pnp check')
'@
            'Test-SPSLifecycleInputRedirected' = @'
$script:StubData.Redirected
'@
            'Read-Host'                     = @'
[CmdletBinding()]
param($Prompt)
$script:StubLog.Add("ask: $Prompt")
$answer = $script:StubData.Answers[$script:StubData.AnswerIndex]
$script:StubData.AnswerIndex++
$answer
'@
            'Register-SPSLifecycleEntraApp' = @'
param($Plan, $CertificatePassword)
$script:StubLog.Add("register $($Plan.Kind) $($Plan.ApplicationName) $($Plan.TenantDomain)")
if ($script:StubData.Fail) { throw $script:StubData.Fail }
[PSCustomObject]@{ ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'; Thumbprint = '' }
'@
        } -Data @{ Fail = $Fail; Answers = $Answer; AnswerIndex = 0; Redirected = $false }
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Register-SPSSiteLifecycleApp.ps1' {
    AfterEach {
        Clear-ModuleStub
    }

    Context 'What it is' {
        It 'requires PowerShell 7.4, as PnP.PowerShell 3.x does' {
            @(Get-Content -LiteralPath $script:Script | Where-Object { $_ -match '^#Requires' }) | Should -Be @('#Requires -Version 7.4')
        }

        It 'has the parameters of the registration and no other: what it can do is what the person gave' {
            $command = Get-Command -Name $script:Script
            $common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters
            $names = @($command.Parameters.Keys | Where-Object { $_ -notin $common })

            ($names | Sort-Object) | Should -Be @('ApplicationName', 'DeviceLogin', 'Kind', 'OutputFolder', 'TenantName', 'UseCertificateStore', 'ValidYears')
            $command.Parameters['TenantName'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            @($command.Parameters['Kind'].Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues) | Should -Be @('Interactive', 'Certificate')
        }

        It 'takes -WhatIf, so that the plan can be read without anything done' {
            (Get-Command -Name $script:Script).Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }

    Context 'A run' {
        It 'registers the app, says what to put in the settings file, writes nothing on the pipeline, and exits with 0' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso' }

            $run.ExitCode | Should -Be 0
            $run.Other | Should -HaveCount 0
            $run.Errors | Should -HaveCount 0
            $run.Log[-1] | Should -Be 'register Interactive SPSSiteLifecycle contoso.onmicrosoft.com'
            $run.Info | Should -Contain "    ClientId   = '$script:ClientId'"
        }

        It 'passes the name, the kind and the device code on' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso'; ApplicationName = 'My-App'; Kind = 'Interactive'; DeviceLogin = $true }

            $run.ExitCode | Should -Be 0
            $run.Log[-1] | Should -Be 'register Interactive My-App contoso.onmicrosoft.com'
            ($run.Info -join "`n") | Should -BeLike '*device code*'
        }

        It 'does nothing with -WhatIf, shows the plan, and exits with 0' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso'; WhatIf = $true }

            $run.ExitCode | Should -Be 0
            $run.Info[0] | Should -BeLike 'App registration plan (nothing has been changed yet)*'
            $run.Log | Should -HaveCount 0
        }

        It 'hides what it says with -InformationAction SilentlyContinue' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso'; InformationAction = 'Ignore' }

            $run.ExitCode | Should -Be 0
            $run.Info | Should -HaveCount 0
        }

        It 'does not pass on what the person did not give: a default must not count as a parameter that does not go with the kind' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso'; Kind = 'Interactive' }

            $run.ExitCode | Should -Be 0
            $run.Errors | Should -HaveCount 0
        }

        It 'says what does not go with the kind, and exits with 1: <Name>' -ForEach @(
            @{ Name = 'OutputFolder'; Parameter = @{ OutputFolder = '/keys' } }
            @{ Name = 'ValidYears'; Parameter = @{ ValidYears = 3 } }
            @{ Name = 'UseCertificateStore'; Parameter = @{ UseCertificateStore = $true } }
        ) {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter (@{ TenantName = 'contoso' } + $Parameter)

            $run.ExitCode | Should -Be 1
            $run.Errors | Should -HaveCount 1
            $run.Errors[0] | Should -BeLike "SPSSiteLifecycle app registration stopped: -$Name is for the Certificate kind*"
            $run.Log | Should -HaveCount 0
        }
    }

    Context 'A run that stops' {
        It 'exits with 1 after a message that says what stopped it, for a tenant that is refused, before anything is asked' {
            Set-RegisterStub

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'microsoft' }

            $run.ExitCode | Should -Be 1
            $run.Errors[0] | Should -BeLike 'SPSSiteLifecycle app registration stopped: TenantName: the tenant ''microsoft'' is refused*'
            $run.Log | Should -HaveCount 0
        }

        It 'exits with 1 when the confirmation is not the tenant' {
            Set-RegisterStub -Answer @('fabrikam')

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso' }

            $run.ExitCode | Should -Be 1
            $run.Errors[0] | Should -BeLike '*does not match the tenant (contoso). Nothing was changed.'
        }

        It 'exits with 1 when the registration fails, with what the registration says' {
            Set-RegisterStub -Fail 'The application with name SPSSiteLifecycle already exists.'

            $run = Invoke-RegisterScript -Parameter @{ TenantName = 'contoso' }

            $run.ExitCode | Should -Be 1
            $run.Errors | Should -HaveCount 1
            $run.Errors[0] | Should -BeLike "SPSSiteLifecycle app registration stopped: An application named 'SPSSiteLifecycle' already exists in this tenant, so nothing was created.*"
        }
    }

    Context 'In a process of its own' {
        It 'stops, and exits with 1, when the tenant is not given, instead of asking for it' {
            $null = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script 2>&1

            $LASTEXITCODE | Should -Not -Be 0
        }

        It 'shows the plan with -WhatIf, in a process of its own, and creates nothing' {
            $output = @(& $script:Pwsh -NoProfile -NonInteractive -File $script:Script -TenantName contoso -WhatIf 2>&1 6>&1)

            $LASTEXITCODE | Should -Be 0
            ($output -join "`n") | Should -BeLike '*App registration plan (nothing has been changed yet)*'
        }
    }
}
