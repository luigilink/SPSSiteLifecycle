BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Generated = [System.DateTime]::new(2026, 10, 29, 8, 0, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    # What Import-SPSLifecycleReviewedReport gives, as far as the plan reads it.
    function script:New-PlanImport {
        param([int]$Delete = 12, [int]$Archive = 3, [int]$Lock = 0, [double]$AgeDays = 1.0)

        [PSCustomObject]@{
            Path        = '/reports/sites-20261029T080000Z.csv'
            Name        = 'sites-20261029T080000Z.csv'
            Counts      = [ordered]@{ Delete = $Delete; Archive = $Archive; Lock = $Lock }
            ActionCount = $Delete + $Archive + $Lock
            GeneratedOn = $script:Generated
            AgeDays     = $AgeDays
        }
    }

    function script:New-PlanSetting {
        param([bool]$Execute = $false, [int]$MaxActions = 25, [bool]$UnlockBeforeArchive = $false, [bool]$GrantSiteAdmin = $false)

        [PSCustomObject]@{
            TenantName    = 'contoso'
            MinLockedDays = 365
            Act           = [PSCustomObject]@{
                Execute = $Execute; MaxActions = $MaxActions; DelaySeconds = 2; MaxCsvAgeDays = 30
                UnlockBeforeArchive = $UnlockBeforeArchive; GrantSiteAdmin = $GrantSiteAdmin
            }
        }
    }

    function script:Get-TestPlan {
        param($Import = (New-PlanImport), $Setting = (New-PlanSetting))
        & $script:Module { param($i, $s) Get-SPSLifecycleActPlan -Import $i -Setting $s } $Import $Setting
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Get-SPSLifecycleActPlan' {
    It 'says what the run will do: the mode, the counts of each decision, and the most that it will do' {
        $plan = Get-TestPlan

        $plan.Mode | Should -BeExactly 'ReportOnly'
        $plan.Counts.Delete | Should -Be 12
        $plan.Counts.Archive | Should -Be 3
        $plan.Counts.Lock | Should -Be 0
        $plan.DecisionCount | Should -Be 15
        $plan.PlannedActions | Should -Be 15
        $plan.MaxActions | Should -Be 25
        $plan.DelaySeconds | Should -Be 2
        $plan.InputFile | Should -BeExactly '/reports/sites-20261029T080000Z.csv'
        $plan.GeneratedOn | Should -Be $script:Generated
        $plan.AgeDays | Should -Be 1.0
        $plan.HasArchive | Should -BeTrue
    }

    It 'is an Execute run only when the setting is exactly $true' {
        (Get-TestPlan -Setting (New-PlanSetting -Execute $true)).Mode | Should -BeExactly 'Execute'
        (Get-TestPlan -Setting (New-PlanSetting -Execute $false)).Mode | Should -BeExactly 'ReportOnly'

        $odd = New-PlanSetting
        $odd.Act.Execute = 'true'
        (Get-TestPlan -Setting $odd).Mode | Should -BeExactly 'ReportOnly'
        $odd.Act.Execute = 1
        (Get-TestPlan -Setting $odd).Mode | Should -BeExactly 'ReportOnly'
        $odd.Act.Execute = $null
        (Get-TestPlan -Setting $odd).Mode | Should -BeExactly 'ReportOnly'
    }

    It 'caps the number of actions at MaxActions' {
        $plan = Get-TestPlan -Setting (New-PlanSetting -MaxActions 5)

        $plan.PlannedActions | Should -Be 5
        $plan.DecisionCount | Should -Be 15
    }

    It 'gives the phrase to type, which carries the number of actions: <Name>' -ForEach @(
        @{ Name = 'only deletions'; Delete = 7; Archive = 0; Lock = 0; Max = 25; Expected = 'DELETE 7' }
        @{ Name = 'only archives'; Delete = 0; Archive = 4; Lock = 0; Max = 25; Expected = 'ARCHIVE 4' }
        @{ Name = 'only locks'; Delete = 0; Archive = 0; Lock = 9; Max = 25; Expected = 'APPLY 9' }
        @{ Name = 'deletions and archives'; Delete = 7; Archive = 4; Lock = 0; Max = 25; Expected = 'APPLY 11' }
        @{ Name = 'deletions and a lock'; Delete = 7; Archive = 0; Lock = 1; Max = 25; Expected = 'APPLY 8' }
        @{ Name = 'only deletions, more than MaxActions'; Delete = 40; Archive = 0; Lock = 0; Max = 25; Expected = 'DELETE 25' }
        @{ Name = 'only archives, more than MaxActions'; Delete = 0; Archive = 40; Lock = 0; Max = 10; Expected = 'ARCHIVE 10' }
    ) {
        $plan = Get-TestPlan -Import (New-PlanImport -Delete $Delete -Archive $Archive -Lock $Lock) -Setting (New-PlanSetting -MaxActions $Max)

        $plan.Phrase | Should -BeExactly $Expected
    }

    It 'says whether the Archive options are on' {
        $plan = Get-TestPlan -Setting (New-PlanSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true)

        $plan.UnlockBeforeArchive | Should -BeTrue
        $plan.GrantSiteAdmin | Should -BeTrue
        (Get-TestPlan).UnlockBeforeArchive | Should -BeFalse
    }

    It 'has no archive when there is no decision to archive' {
        (Get-TestPlan -Import (New-PlanImport -Archive 0)).HasArchive | Should -BeFalse
    }
}

Describe 'Format-SPSLifecycleActBanner' {
    BeforeAll {
        function script:Get-TestBanner {
            param($Plan = (Get-TestPlan), $Setting = (New-PlanSetting))
            @(& $script:Module { param($p, $s) Format-SPSLifecycleActBanner -Plan $p -Setting $s } $Plan $Setting)
        }
    }

    It 'says that a report-only run changes nothing, and gives the file, the date and the age, and the decisions' {
        $lines = Get-TestBanner

        $lines | Should -Be @(
            'Act phase on the tenant contoso: REPORT ONLY. This run changes nothing: it says what each row would get.'
            'File: /reports/sites-20261029T080000Z.csv'
            'Generated on: 2026-10-29 08:00 UTC (the oldest row of the file), 1.0 days ago; the limit is 30 days (MaxCsvAgeDays).'
            'Decisions: Delete 12, Archive 3, Lock 0 (15 in all). This run does at most 15 of them (MaxActions 25), 2 s apart.'
            'Archive: no option is on (UnlockBeforeArchive, GrantSiteAdmin): the site is archived as it is.'
            'Every row is read again from the tenant right before its action, and a site that is protected, excluded, in a lock state that is not accepted, locked for less than 365 days, or whose group is not active is left alone, whatever the decision.'
        )
    }

    It 'says that an execute run changes the tenant' {
        $setting = New-PlanSetting -Execute $true
        $lines = Get-TestBanner -Plan (Get-TestPlan -Setting $setting) -Setting $setting

        $lines[0] | Should -BeExactly 'Act phase on the tenant contoso: EXECUTE. This run changes the tenant.'
    }

    It 'says what the Archive options do' {
        $setting = New-PlanSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true
        $lines = Get-TestBanner -Plan (Get-TestPlan -Setting $setting) -Setting $setting

        $lines | Should -Contain 'Archive: a read-only site is unlocked first and locked again afterwards (UnlockBeforeArchive), and the administrator who signed in is added to the site collection (GrantSiteAdmin).'
    }

    It 'says what the Archive option does when only the unlock is on' {
        $setting = New-PlanSetting -UnlockBeforeArchive $true
        $lines = Get-TestBanner -Plan (Get-TestPlan -Setting $setting) -Setting $setting

        $lines | Should -Contain 'Archive: a read-only site is unlocked first and locked again afterwards (UnlockBeforeArchive).'
    }

    It 'says nothing of the archive when no row is to be archived' {
        $plan = Get-TestPlan -Import (New-PlanImport -Archive 0)

        @(Get-TestBanner -Plan $plan | Where-Object { $_ -like 'Archive:*' }) | Should -HaveCount 0
    }

    It 'says that the number of actions is capped' {
        $setting = New-PlanSetting -MaxActions 5
        $lines = Get-TestBanner -Plan (Get-TestPlan -Setting $setting) -Setting $setting

        $lines | Should -Contain 'Decisions: Delete 12, Archive 3, Lock 0 (15 in all). This run does at most 5 of them (MaxActions 5), 2 s apart.'
    }
}

Describe 'Confirm-SPSLifecycleAct' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Test-SPSLifecycleInputRedirected' = @'
$script:StubLog.Add('redirected?')
$script:StubData.Redirected
'@
            'Read-Host'                        = @'
[CmdletBinding()]
param($Prompt)
$script:StubLog.Add("ask: $Prompt")
$answer = $script:StubData.Answers[$script:StubData.AnswerIndex]
$script:StubData.AnswerIndex++
$answer
'@
        } -Data @{ Redirected = $false; Answers = @('contoso', 'DELETE 15'); AnswerIndex = 0 }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Invoke-TestConfirm {
            param([string[]]$Answer = @('contoso', 'APPLY 15'), [bool]$Redirected = $false)

            & $script:Module { param($a, $r) $script:StubData.Answers = $a; $script:StubData.Redirected = $r; $script:StubData.AnswerIndex = 0 } $Answer $Redirected
            $setting = New-PlanSetting -Execute $true
            $plan = Get-TestPlan -Setting $setting
            & $script:Module { param($p, $s) Confirm-SPSLifecycleAct -Plan $p -Setting $s } $plan $setting
        }
    }

    It 'asks for the name of the tenant, then for the phrase, and goes on when both are right' {
        { Invoke-TestConfirm } | Should -Not -Throw

        Get-StubLog | Should -Be @(
            'redirected?'
            'ask: Type the name of the tenant to go on'
            'ask: Type APPLY 15 to start: the tenant is changed as soon as you do'
        )
    }

    It 'takes the name of the tenant in any case, with spaces around it' {
        { Invoke-TestConfirm -Answer @('  CONTOSO ', 'APPLY 15') } | Should -Not -Throw
    }

    It 'stops, before it asks anything, when the input is redirected: no person can type the confirmation' {
        { Invoke-TestConfirm -Redirected $true } | Should -Throw -ExpectedMessage '*input is redirected*cannot*Nothing was changed*'

        Get-StubLog | Should -Be @('redirected?')
    }

    It 'stops, and asks no more, when the name of the tenant is not the right one: <Name>' -ForEach @(
        @{ Name = 'another tenant'; Answer = 'fabrikam' }
        @{ Name = 'a part of the name'; Answer = 'conto' }
        @{ Name = 'an empty answer'; Answer = '' }
        @{ Name = 'nothing'; Answer = $null }
        @{ Name = 'the name with a hidden character'; Answer = "contoso$([char]0x200B)" }
    ) {
        { Invoke-TestConfirm -Answer @($Answer, 'APPLY 15') } | Should -Throw -ExpectedMessage '*does not match the tenant*Nothing was changed*'

        @(Get-StubLog | Where-Object { $_ -like 'ask:*' }) | Should -HaveCount 1
    }

    It 'stops when the phrase is not the right one: <Name>' -ForEach @(
        @{ Name = 'another number'; Answer = 'APPLY 16' }
        @{ Name = 'another word'; Answer = 'DELETE 15' }
        @{ Name = 'in lowercase'; Answer = 'apply 15' }
        @{ Name = 'an empty answer'; Answer = '' }
        @{ Name = 'nothing'; Answer = $null }
        @{ Name = 'a phrase that is a part of the one to type'; Answer = 'APPLY' }
        @{ Name = 'the number only'; Answer = '15' }
    ) {
        { Invoke-TestConfirm -Answer @('contoso', $Answer) } | Should -Throw -ExpectedMessage '*is not the phrase*APPLY 15*Nothing was changed*'
    }

    It 'takes the phrase with spaces around it' {
        { Invoke-TestConfirm -Answer @('contoso', '  APPLY 15  ') } | Should -Not -Throw
    }
}
