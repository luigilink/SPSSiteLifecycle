BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Script = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../src/SPSSiteLifecycle.ps1')).ProviderPath
    $script:Pwsh = (Get-Process -Id $PID).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ScanFixture.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ActFixture.ps1')

    # Runs the script in this process, where the module that is loaded is the one of the repository and its adapters are stubbed, and
    # gives its exit code, the lines of information that it wrote and its errors.
    function script:Invoke-EntryScript {
        param([hashtable]$Parameter)

        $global:LASTEXITCODE = $null
        $output = @(& $script:Script @Parameter 2>&1 3>&1 6>&1)
        [PSCustomObject]@{
            ExitCode = $global:LASTEXITCODE
            Info     = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })
            Errors   = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$($_.Exception.Message)" })
            Warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { "$($_.Message)" })
            Other    = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] -and $_ -isnot [System.Management.Automation.ErrorRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
        }
    }

    # A tenant of Count sites, and a reviewed report that decides on the first of them.
    function script:Start-ActEntry {
        param([string[]]$Decision, [hashtable]$Override = @{}, [string]$ActSettings = '', [hashtable]$Data = @{}, [string]$Settings = '')

        $sites = foreach ($index in 1..$Decision.Count) {
            New-ActSiteState -Index $index -Override $(if ($Override.ContainsKey($index)) { $Override[$index] } else { @{} })
        }

        Set-ActStub -Site @($sites) -Data $Data
        $rows = for ($i = 0; $i -lt $Decision.Count; $i++) { @{ Index = $i + 1; Decision = $Decision[$i] } }
        New-ActRunFolder -Row @($rows) -ActSettings $ActSettings -Settings $Settings -Generated ([System.DateTime]::UtcNow.AddHours(-2).ToString("yyyyMMdd'T'HHmmss'Z'"))
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
            $script:Writes = @('lock *', 'delete site *', 'delete group *', 'archive https*', 'admin *')
        }

        AfterEach {
            Clear-ModuleStub
        }

        It 'runs a report only by default: the banner and the summary, the record, nothing changed, and an exit with 0' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete'

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 0
            $result.Errors | Should -HaveCount 0
            $result.Warnings | Should -HaveCount 0
            $result.Other | Should -HaveCount 0
            $result.Info[0] | Should -BeExactly 'Act phase on the tenant contoso: REPORT ONLY. This run changes nothing: it says what each row would get.'
            $report = @(Get-ChildItem -LiteralPath $run.Reports -Filter 'act-*.csv')
            $report | Should -HaveCount 1
            @((Import-Csv -LiteralPath $report[0].FullName).Outcome) | Should -Be @('WouldDo', 'WouldDo')
            $result.Info | Should -Contain 'Rows with a decision: 2. Done 0, Failed 0, WouldDo 2, Skipped 0, Review 0, ReadError 0, NotRun 0.'
            $result.Info | Should -Contain "Report: $($report[0].FullName)"
            foreach ($pattern in $script:Writes) {
                @(Get-StubLog | Where-Object { $_ -like $pattern }) | Should -HaveCount 0 -Because $pattern
            }

            @(Get-StubLog | Where-Object { $_ -like 'ask:*' }) | Should -HaveCount 0
        }

        It 'does what it is asked, after the confirmation, and exits with 0' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 2') }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 0
            $result.Info[0] | Should -BeExactly 'Act phase on the tenant contoso: EXECUTE. This run changes the tenant.'
            ($result.Info -join "`n") | Should -BeLike '*EXECUTE: the tenant was changed.*Done 2*'
            @(Get-StubLog | Where-Object { $_ -like 'delete group *' }) | Should -HaveCount 2
        }

        It 'exits with 0 when no row has a decision, and says so' {
            $run = Start-ActEntry -Decision '', ''

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 0
            $result.Info | Should -Contain 'Nothing to do: no row of the reviewed report has a decision (Delete, Archive or Lock).'
            Get-StubLog | Should -HaveCount 0
        }

        It 'exits with 2, and says that rows failed and where the record is, when the run ended but an action failed' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{
                Answers = @('contoso', 'DELETE 2')
                Fail    = @{ 'delete group' = @{ '00000001-1111-4111-8111-000000000001' = 'The group could not be deleted: Forbidden.' } }
            }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 2
            $result.Errors | Should -HaveCount 0
            $result.Warnings | Should -HaveCount 1
            $result.Warnings[0] | Should -BeLike 'SPSSiteLifecycle: the Act run ended, but 1 row failed or could not be read. Read the Act report: *act-*.csv'
            $result.Info | Should -Contain 'Rows with a decision: 2. Done 1, Failed 1, WouldDo 0, Skipped 0, Review 0, ReadError 0, NotRun 0.'
        }

        It 'exits with 2 when a site could not be read, also in report-only mode' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete' -Data @{ Fail = @{ read = @{ 'https://contoso.sharepoint.com/sites/site2' = 'The site could not be read.' } } }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 2
            $result.Warnings[0] | Should -BeLike 'SPSSiteLifecycle: the Act run ended, but 1 row failed or could not be read.*'
        }

        It 'exits with 2, and says that it stopped, after 3 errors in a row' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete', 'Delete', 'Delete' -Data @{ Fail = @{ read = 'The tenant did not answer.' } }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 2
            $result.Warnings[0] | Should -BeLike 'SPSSiteLifecycle: the Act run stopped after 3 errors in a row, with 3 rows that failed or could not be read. Read the Act report: *act-*.csv'
            $result.Info | Should -Contain 'The run stopped after 3 errors in a row: the rows that follow were not read.'
        }

        It 'exits with 0 when the rows are skipped or to be reviewed: that is the run that was planned' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete' -Override @{ 1 = @{ IsHubSite = $true }; 2 = @{ HasHolds = $true } }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 0
            @((Get-ChildItem -LiteralPath $run.Reports -Filter 'act-*.csv' | ForEach-Object { Import-Csv -LiteralPath $_.FullName }).Outcome) | Should -Be @('Skipped', 'Review')
        }

        It 'exits with 1, with the message, and changes nothing, when the confirmation is not right: <Name>' -ForEach @(
            @{ Name = 'another tenant'; Answers = @('fabrikam', 'DELETE 1'); Redirected = $false; Expected = '*does not match the tenant*Nothing was changed.*' }
            @{ Name = 'another phrase'; Answers = @('contoso', 'DELETE 2'); Redirected = $false; Expected = '*is not the phrase*DELETE 1*Nothing was changed.*' }
            @{ Name = 'a redirected input'; Answers = @('contoso', 'DELETE 1'); Redirected = $true; Expected = '*input is redirected*Nothing was changed.*' }
        ) {
            $run = Start-ActEntry -Decision 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = $Answers; Redirected = $Redirected }

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 1
            $result.Errors | Should -HaveCount 1
            $result.Errors[0] | Should -BeLike 'SPSSiteLifecycle stopped: *'
            $result.Errors[0] | Should -BeLike $Expected
            foreach ($pattern in $script:Writes) {
                @(Get-StubLog | Where-Object { $_ -like $pattern }) | Should -HaveCount 0 -Because $pattern
            }
        }

        It 'exits with 1 before the sign-in, naming the problem, when the file or the settings are wrong: <Name>' -ForEach @(
            @{ Name = 'an unknown decision'; Decision = @('Remove'); Settings = ''; Expected = "*Decision 'Remove'*" }
            @{ Name = 'a tenant that is refused'; Decision = @('Delete'); Settings = "RefusedTenants = @('contoso')"; Expected = '*refused*' }
        ) {
            $run = Start-ActEntry -Decision $Decision -Settings $Settings

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike $Expected
            Get-StubLog | Should -HaveCount 0
        }

        It 'exits with 1, and sends the person to the Act report, when something stops the run half-way' {
            $run = Start-ActEntry -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 2') }
            $existing = & $script:Module { $script:StubData }
            $existing.Verdicts = 0
            Set-ModuleStub -Stub @{
                'Get-SPSLifecycleActVerdict' = @'
param($Row, $Session, $Setting, $LockDateIndex, $ExclusionIndex, $HomeSiteUrl, $Now)
$script:StubData.Verdicts++
if ($script:StubData.Verdicts -eq 2) { throw 'Something nobody expected.' }
[PSCustomObject]@{ Verdict = 'DELETE-VIA-GROUP'; ReadError = ''; Site = [PSCustomObject]@{ Url = $Row.Url; SiteId = $Row.SiteId; GroupId = '00000001-1111-4111-8111-000000000001'; LockState = 'ReadOnly' }; GroupState = 'Active'; LockedOn = $null }
'@
            } -Data $existing

            $result = Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }

            $result.ExitCode | Should -Be 1
            $result.Errors[0] | Should -BeLike 'SPSSiteLifecycle stopped: Something nobody expected.*The Act report in the output folder, if it exists, says what was done before the error.'
        }

        It 'gives the settings file as it was typed, and shows the information unless the person who runs it asks otherwise: <Name>' -ForEach @(
            @{ Name = 'nothing asked'; Extra = @{}; Expected = 'Continue' }
            @{ Name = 'SilentlyContinue'; Extra = @{ InformationAction = 'SilentlyContinue' }; Expected = 'SilentlyContinue' }
            @{ Name = 'Ignore'; Extra = @{ InformationAction = 'Ignore' }; Expected = 'Ignore' }
        ) {
            Set-ModuleStub -Stub @{
                'Invoke-SPSLifecycleAct' = @'
[CmdletBinding()]
param($ConfigFile, $Now)
$script:StubLog.Add("act config=[$ConfigFile] information=$InformationPreference")
[PSCustomObject]@{ Counts = @{ Failed = 0; ReadError = 0 }; StoppedBecause = ''; ReportPath = '' }
'@
            }

            $result = Invoke-EntryScript -Parameter (@{ ConfigFile = './dir/settings file.psd1'; Phase = 'Act' } + $Extra)

            $result.ExitCode | Should -Be 0
            Get-StubLog | Should -Be @("act config=[./dir/settings file.psd1] information=$Expected")
        }

        It 'does not call the Scan' {
            $run = Start-ActEntry -Decision 'Delete'
            Set-ModuleStub -Stub @{ 'Invoke-SPSLifecycleScan' = 'throw "The Scan must not be called by the Act phase."' } -Data (& $script:Module { $script:StubData })

            (Invoke-EntryScript -Parameter @{ ConfigFile = $run.Config; Phase = 'Act' }).ExitCode | Should -Be 0
        }
    }

    Context 'As a process of its own' {
        It 'exits with 1 and says which file is missing, for the Act phase too, before any sign-in' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'no-such-file.psd1'

            $output = & $script:Pwsh -NoProfile -File $script:Script -ConfigFile $missing -Phase Act 2>&1 | Out-String

            $LASTEXITCODE | Should -Be 1
            $output | Should -BeLike '*SPSSiteLifecycle stopped:*no-such-file.psd1*'
            $output | Should -Not -BeLike '*Nothing was changed in the tenant: the Scan only reads*'
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
