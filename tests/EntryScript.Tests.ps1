BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Script = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../src/SPSSiteLifecycle.ps1')).ProviderPath
    $script:Pwsh = (Get-Process -Id $PID).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ScanFixture.ps1')

    # Runs the script in this process, where the module that is loaded is the one of the repository and its adapters are stubbed, and
    # gives its exit code, the lines of information that it wrote and its errors.
    function script:Invoke-EntryScript {
        param([hashtable]$Parameter)

        $global:LASTEXITCODE = $null
        $output = @(& $script:Script @Parameter 2>&1 6>&1)
        [PSCustomObject]@{
            ExitCode = $global:LASTEXITCODE
            Info     = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })
            Errors   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$($_.Exception.Message)" })
            Other    = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] -and $_ -isnot [System.Management.Automation.ErrorRecord] })
        }
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'SPSSiteLifecycle.ps1' {
    Context 'What it is' {
        It 'requires PowerShell 7.4, as PnP.PowerShell 3.x does' {
            @(Get-Content -LiteralPath $script:Script | Where-Object { $_ -match '^#Requires' }) | Should -Be @('#Requires -Version 7.4')
        }

        It 'has no parameter but the settings file and the phase: what a run can do is written in a file that can be reviewed' {
            $names = @((Get-Command -Name $script:Script).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters })

            $names | Should -Be @('ConfigFile', 'Phase')
        }

        It 'takes Scan and Act as the phase, and nothing else' {
            $set = (Get-Command -Name $script:Script).Parameters['Phase'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }

            @($set.ValidValues) | Should -Be @('Scan', 'Act')
            { & $script:Script -ConfigFile 'settings.psd1' -Phase 'Both' } | Should -Throw
        }

        It 'explains itself and its two parameters' {
            $help = Get-Help -Name $script:Script -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            foreach ($name in 'ConfigFile', 'Phase') {
                (@($help.parameters.parameter | Where-Object { $_.name -eq $name }).description.Text -join '') | Should -Not -BeNullOrEmpty -Because $name
            }

            @($help.examples.example) | Should -Not -HaveCount 0
        }
    }

    Context 'The Scan' {
        BeforeEach {
            Set-ScanStub
        }

        AfterEach {
            Clear-ModuleStub
        }

        It 'writes the report, tells how it went, and exits with 0' {
            $run = New-RunFolder

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Scan' }

            $result.ExitCode | Should -Be 0
            $result.Errors | Should -HaveCount 0
            $result.Other | Should -HaveCount 0
            $report = @(Get-ChildItem -LiteralPath $run.Reports -Filter 'sites-*.csv')
            $report | Should -HaveCount 1
            @(Import-Csv -LiteralPath $report[0].FullName) | Should -HaveCount 5
            $result.Info[0] | Should -BeLike 'Scan of the tenant contoso ended in *. It only reads: nothing was changed in the tenant.'
            $result.Info | Should -Contain "Report: $($report[0].FullName)"
            ($result.Info -join "`n") | Should -BeLike '*Sites in the report: 5.*Suggested actions: Delete 2, Archive 1, Lock 0, nothing 2.*'
        }

        It 'shows no line when it is asked not to' {
            # SilentlyContinue hides the lines on the screen, but the redirection of the test still reads the stream: Ignore does not write them at all.
            $quiet = Invoke-EntryScript -Parameter @{ ConfigFile = (New-RunFolder).Config; Phase = 'Scan'; InformationAction = 'Ignore' }

            $quiet.ExitCode | Should -Be 0
            $quiet.Info | Should -HaveCount 0
        }

        It 'gives the settings file as it was typed, and shows the information unless the person who runs it asks otherwise: <Name>' -ForEach @(
            @{ Name = 'nothing asked'; Extra = @{}; Expected = 'Continue' }
            @{ Name = 'Continue'; Extra = @{ InformationAction = 'Continue' }; Expected = 'Continue' }
            @{ Name = 'SilentlyContinue'; Extra = @{ InformationAction = 'SilentlyContinue' }; Expected = 'SilentlyContinue' }
            @{ Name = 'Ignore'; Extra = @{ InformationAction = 'Ignore' }; Expected = 'Ignore' }
        ) {
            Set-ModuleStub -Stub @{
                'Invoke-SPSLifecycleScan' = @'
[CmdletBinding()]
param($ConfigFile, $Now)
$script:StubLog.Add("scan config=[$ConfigFile] information=$InformationPreference")
'@
            }
            $parameters = @{ ConfigFile = './dir/settings file.psd1'; Phase = 'Scan' } + $Extra

            $result = Invoke-EntryScript -Parameter $parameters

            $result.ExitCode | Should -Be 0
            Get-StubLog | Should -Be @("scan config=[./dir/settings file.psd1] information=$Expected")
        }

        It 'signs in once, and asks the tenant for nothing but the home site and the sites' {
            $null = Invoke-EntryScript -Parameter @{ ConfigFile = (New-RunFolder).Config; Phase = 'Scan' }

            Get-StubLog | Should -Be @('open', 'home site', 'api checked', 'page start=[]', 'page start=[t1]', 'close')
        }

        It 'exits with 1, writes the message, and says that nothing was changed, when the settings file is not there' {
            $result = Invoke-EntryScript -Parameter @{ ConfigFile = (Join-Path -Path $TestDrive -ChildPath 'no-such-file.psd1'); Phase = 'Scan' }

            $result.ExitCode | Should -Be 1
            $result.Errors | Should -HaveCount 1
            $result.Errors[0] | Should -BeLike 'SPSSiteLifecycle stopped: *no-such-file*Nothing was changed in the tenant: the Scan only reads. Fix the problem and run it again.'
            Get-StubLog | Should -HaveCount 0
        }

        It 'exits with 1 before the sign-in when a setting is wrong, and names it' {
            $run = New-RunFolder -Settings 'NoSuchSetting = 1'

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Scan' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike '*NoSuchSetting*'
            Get-StubLog | Should -HaveCount 0
            Test-Path -LiteralPath $run.Reports | Should -BeFalse
        }

        It 'exits with 1, and leaves no report that looks complete, when the listing fails' {
            $run = New-RunFolder
            & $script:Module { $script:StubData.FailAt = 't1' }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Scan' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike 'SPSSiteLifecycle stopped: *page 2*'
            @(Get-ChildItem -LiteralPath $run.Reports -File | Where-Object { $_.Name -like 'sites-*' }) | Should -HaveCount 0
            @(Get-StubLog)[-1] | Should -BeExactly 'close'
        }

        It 'exits with 1 when the home site cannot be read, and does not list anything' {
            $run = New-RunFolder
            & $script:Module { $script:StubData.HomeSiteFails = 'The home site of the tenant could not be read: Access denied.' }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Scan' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike '*home site*could not be read*'
            (Get-StubLog | Where-Object { $_ -like 'page*' }) | Should -HaveCount 0
        }

        It 'exits with 1, whatever the error that stops it, when it is not an error of the settings' {
            $run = New-RunFolder
            Set-ModuleStub -Stub @{ 'Open-SPSLifecycleTenantSession' = "throw [System.IO.IOException]::new('The sign-in could not be made.')" }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Scan' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike 'SPSSiteLifecycle stopped: The sign-in could not be made.*'
        }
    }

    Context 'The Act phase' {
        BeforeEach {
            Set-ScanStub
        }

        AfterEach {
            Clear-ModuleStub
        }

        It 'says that it is not available in this version, and exits with 1, without reading the settings or the tenant' {
            $run = New-RunFolder

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 1
            $result.Errors | Should -HaveCount 1
            $result.Errors[0] | Should -BeExactly 'SPSSiteLifecycle stopped: The Act phase is not available in this version. Run -Phase Scan: it writes the report that the Act phase will read.'
            Get-StubLog | Should -HaveCount 0
            Test-Path -LiteralPath $run.Reports | Should -BeFalse
        }

        It 'says it even when the settings file is not there' {
            $result = Invoke-EntryScript -Parameter @{ ConfigFile = (Join-Path -Path $TestDrive -ChildPath 'no-such-file.psd1'); Phase = 'Act' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike '*not available in this version*'
        }
    }

    Context 'As a process of its own' {
        It 'exits with 1 and says why when it is asked for the Act phase' {
            $output = & $script:Pwsh -NoProfile -File $script:Script -ConfigFile (Join-Path -Path $TestDrive -ChildPath 'settings.psd1') -Phase Act 2>&1 | Out-String

            $LASTEXITCODE | Should -Be 1
            $output | Should -BeLike '*SPSSiteLifecycle stopped: The Act phase is not available in this version*'
        }

        It 'exits with 1 and says which file is missing, before any sign-in' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'no-such-file.psd1'

            $output = & $script:Pwsh -NoProfile -File $script:Script -ConfigFile $missing -Phase Scan 2>&1 | Out-String

            $LASTEXITCODE | Should -Be 1
            $output | Should -BeLike '*SPSSiteLifecycle stopped:*no-such-file.psd1*Nothing was changed in the tenant*'
        }

        It 'exits with 1 when a parameter is missing' {
            $null = & $script:Pwsh -NoProfile -NonInteractive -File $script:Script -Phase Scan 2>&1

            $LASTEXITCODE | Should -Not -Be 0
        }
    }
}
