BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ActFixture.ps1')

    # A tenant of sites 1 to Count, and a run that decides on the first of them: Decision is a list of the decisions of the rows
    # ('' is a row without a decision), Override maps the number of a site to what differs in its state.
    function script:Start-ActScenario {
        param(
            [string[]]$Decision,
            [hashtable]$Override = @{},
            [string]$ActSettings = '',
            [string]$Settings = '',
            [hashtable]$Data = @{},
            [int]$Count = 0,
            $Locks = $null,
            [string]$Delimiter = ','
        )

        if ($Count -eq 0) { $Count = $Decision.Count }
        $sites = foreach ($index in 1..$Count) {
            New-ActSiteState -Index $index -Override $(if ($Override.ContainsKey($index)) { $Override[$index] } else { @{} })
        }

        Set-ActStub -Site @($sites) -Data $Data
        $rows = for ($i = 0; $i -lt $Decision.Count; $i++) { @{ Index = $i + 1; Decision = $Decision[$i] } }
        New-ActRunFolder -Row @($rows) -ActSettings $ActSettings -Settings $Settings -Locks $Locks -Delimiter $Delimiter
    }

    function script:Get-World {
        & $script:Module { $script:StubData.World }
    }

    function script:Get-Calls {
        param([string]$Pattern)
        @(Get-StubLog | Where-Object { $_ -like $Pattern })
    }

    $script:Writes = @('lock *', 'delete site *', 'delete group *', 'archive https*', 'admin *')

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Invoke-SPSLifecycleAct, report only (the default)' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'changes nothing and asks nothing: each decision gets the verdict that it would get, and the outcome WouldDo' {
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Archive', 'Lock', 'Delete', 'Delete' -Override @{
            2 = @{ GroupId = '' }
            4 = @{ LockState = 'Unlock' }
            5 = @{ IsHubSite = $true }
            6 = @{ LastContentModified = [System.DateTime]::new(2026, 10, 29, 20, 0, 0, [System.DateTimeKind]::Utc) }
        }

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-SITE', 'ARCHIVE', 'LOCK', 'SKIP-PROTECTED', 'REVIEW-CONTENT-MODIFIED')
        @($result.Rows.Outcome) | Should -Be @('WouldDo', 'WouldDo', 'WouldDo', 'WouldDo', 'Skipped', 'Review')
        @($result.Rows.Decision) | Should -Be @('Delete', 'Delete', 'Archive', 'Lock', 'Delete', 'Delete')
        @($result.Rows.Line) | Should -Be @('2', '3', '4', '5', '6', '7')
        foreach ($pattern in $script:Writes) {
            Get-Calls -Pattern $pattern | Should -HaveCount 0 -Because $pattern
        }

        Get-Calls -Pattern 'ask:*' | Should -HaveCount 0
        Get-Calls -Pattern 'redirected?' | Should -HaveCount 0
        Get-Calls -Pattern 'account' | Should -HaveCount 0
        $result.Summary.Mode | Should -BeExactly 'ReportOnly'
        $result.Summary.Counts.WouldDo | Should -Be 4
        $result.Summary.Counts.Skipped | Should -Be 1
        $result.Summary.Counts.Review | Should -Be 1
        (Get-World)['https://contoso.sharepoint.com/sites/site4'].LockState | Should -BeExactly 'Unlock'
        Test-Path -LiteralPath $run.Journal | Should -BeFalse
    }

    It 'is report only when Execute is not set, and when it is $false' -ForEach @(
        @{ ActSettings = '' }
        @{ ActSettings = 'Execute = $false' }
    ) {
        $run = Start-ActScenario -Decision 'Delete' -ActSettings $ActSettings

        $result = Invoke-TestAct -Run $run

        $result.Summary.Mode | Should -BeExactly 'ReportOnly'
        Get-Calls -Pattern 'delete *' | Should -HaveCount 0
    }

    It 'refuses a setting that is not a boolean, before it signs in: Execute is not read from a text' {
        $run = Start-ActScenario -Decision 'Delete' -ActSettings "Execute = 'true'"

        { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*Execute*'

        Get-StubLog | Should -HaveCount 0
    }

    It 'gives the verdict of every row, also beyond MaxActions: the rows past the cap are NotRun, with their verdict' {
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'MaxActions = 2'

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Outcome) | Should -Be @('WouldDo', 'WouldDo', 'NotRun', 'NotRun')
        @($result.Rows.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-VIA-GROUP', 'DELETE-VIA-GROUP', 'DELETE-VIA-GROUP')
        $result.Rows[2].Detail | Should -BeLike '*MaxActions (2)*would not do*'
    }

    It 'does not count a row that is not an action toward MaxActions' {
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete' -ActSettings 'MaxActions = 2' -Override @{ 1 = @{ IsHubSite = $true } }

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Outcome) | Should -Be @('Skipped', 'WouldDo', 'WouldDo')
    }

    It 'says that a site could not be read, with the message, and goes on with the next row' {
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete' -Data @{ Fail = @{ read = @{ 'https://contoso.sharepoint.com/sites/site2' = "The site 'https://contoso.sharepoint.com/sites/site2' could not be read from the tenant: Access denied." } } }

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Outcome) | Should -Be @('WouldDo', 'ReadError', 'WouldDo')
        $result.Rows[1].Verdict | Should -BeExactly ''
        $result.Rows[1].Detail | Should -BeLike '*could not be read from the tenant: Access denied*'
        $result.Summary.Counts.ReadError | Should -Be 1
        $result.Summary.StoppedBecause | Should -BeExactly ''
    }

    It 'stops after 3 errors in a row, here too, and leaves the other rows NotRun' {
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete', 'Delete' -Data @{ Fail = @{ read = 'The tenant did not answer.' } }

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Outcome) | Should -Be @('ReadError', 'ReadError', 'ReadError', 'NotRun', 'NotRun')
        $result.Summary.StoppedBecause | Should -BeExactly 'ConsecutiveErrors'
        $result.Rows[3].Detail | Should -BeLike '*stopped after 3 errors in a row*'
        Get-Calls -Pattern 'read *' | Should -HaveCount 3
    }

    It 'counts only the errors that follow each other: a row that is read in between starts the count again' {
        $fail = @{ read = @{
                'https://contoso.sharepoint.com/sites/site1' = 'x'; 'https://contoso.sharepoint.com/sites/site2' = 'x'
                'https://contoso.sharepoint.com/sites/site4' = 'x'; 'https://contoso.sharepoint.com/sites/site5' = 'x'
            }
        }
        $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete', 'Delete', 'Delete' -Data @{ Fail = $fail }

        $result = Invoke-TestAct -Run $run

        @($result.Rows.Outcome) | Should -Be @('ReadError', 'ReadError', 'WouldDo', 'ReadError', 'ReadError', 'WouldDo')
        $result.Summary.StoppedBecause | Should -BeExactly ''
    }

    It 'says nothing is to be done, and does not sign in, when no row has a decision' {
        $run = Start-ActScenario -Decision '', '', ''

        $result = Invoke-TestAct -Run $run

        Get-StubLog | Should -HaveCount 0
        $result.Text | Should -Contain 'Nothing to do: no row of the reviewed report has a decision (Delete, Archive or Lock).'
        $result.Summary.Counts.Done | Should -Be 0
        $result.Rows | Should -HaveCount 0
        Test-Path -LiteralPath $run.Reports | Should -BeFalse
    }

    It 'protects the home site, and a site that is not a site to act on: <Name>' -ForEach @(
        @{ Name = 'a hub site'; Override = @{ IsHubSite = $true }; HomeSite = ''; Expected = 'SKIP-PROTECTED' }
        @{ Name = 'the home site'; Override = @{}; HomeSite = 'https://contoso.sharepoint.com/sites/site1'; Expected = 'SKIP-PROTECTED' }
        @{ Name = 'a system site'; Override = @{ Template = 'APPCATALOG#0' }; HomeSite = ''; Expected = 'SKIP-PROTECTED' }
        @{ Name = 'a channel site'; Override = @{ Template = 'TEAMCHANNEL#1' }; HomeSite = ''; Expected = 'SKIP-CHANNEL-SITE' }
        @{ Name = 'a site that is not read-only'; Override = @{ LockState = 'Unlock' }; HomeSite = ''; Expected = 'SKIP-LOCK-STATE' }
        @{ Name = 'a site that is locked out'; Override = @{ LockState = 'NoAccess' }; HomeSite = ''; Expected = 'SKIP-LOCK-STATE' }
        @{ Name = 'an archived site'; Override = @{ ArchiveStatus = 'Archived' }; HomeSite = ''; Expected = 'SKIP-ALREADY-ARCHIVED' }
    ) {
        $run = Start-ActScenario -Decision 'Delete' -Override @{ 1 = $Override } -Data @{ HomeSite = $HomeSite }

        $result = Invoke-TestAct -Run $run

        $result.Rows[0].Verdict | Should -BeExactly $Expected
        $result.Rows[0].Outcome | Should -BeExactly 'Skipped'
        $result.Rows[0].Detail | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-SPSLifecycleAct, with Execute' {
    AfterEach {
        Clear-ModuleStub
    }

    Context 'The confirmation' {
        It 'shows the banner, asks for the tenant and then the phrase, and only then signs in' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 2') }

            $result = Invoke-TestAct -Run $run

            @(Get-StubLog)[0..4] | Should -Be @(
                'redirected?'
                'ask: Type the name of the tenant to go on'
                'ask: Type DELETE 2 to start: the tenant is changed as soon as you do'
                'open'
                'home site'
            )
            $result.Text[0] | Should -BeExactly 'Act phase on the tenant contoso: EXECUTE. This run changes the tenant.'
            ($result.Text -join "`n") | Should -BeLike '*Decisions: Delete 2, Archive 0, Lock 0 (2 in all). This run does at most 2 of them (MaxActions 25), 2 s apart.*'
        }

        It 'stops before the sign-in, with nothing changed and no report, when the confirmation is not right: <Name>' -ForEach @(
            @{ Name = 'another tenant'; Answers = @('fabrikam', 'DELETE 2'); Redirected = $false; Expected = '*does not match the tenant*' }
            @{ Name = 'another phrase'; Answers = @('contoso', 'DELETE 3'); Redirected = $false; Expected = '*is not the phrase*DELETE 2*' }
            @{ Name = 'a redirected input'; Answers = @('contoso', 'DELETE 2'); Redirected = $true; Expected = '*input is redirected*' }
        ) {
            $run = Start-ActScenario -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = $Answers; Redirected = $Redirected }

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage $Expected

            Get-Calls -Pattern 'open' | Should -HaveCount 0
            foreach ($pattern in $script:Writes) {
                Get-Calls -Pattern $pattern | Should -HaveCount 0 -Because $pattern
            }

            Test-Path -LiteralPath $run.Reports | Should -BeFalse
        }

        It 'does not ask a thing when the input is redirected' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Data @{ Redirected = $true }

            { Invoke-TestAct -Run $run } | Should -Throw

            Get-Calls -Pattern 'ask:*' | Should -HaveCount 0
        }

        It 'gives the phrase of the mix of decisions: APPLY and the number of actions' {
            $run = Start-ActScenario -Decision 'Delete', 'Archive', 'Lock' -ActSettings 'Execute = $true' -Override @{ 3 = @{ LockState = 'Unlock' } } -Data @{ Answers = @('contoso', 'APPLY 3') }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Done', 'Done', 'Done')
        }
    }

    Context 'The actions' {
        It 'does each action of the file in order, a pause apart, and writes the record of each' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 3') }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Done', 'Done', 'Done')
            @($result.Rows.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-VIA-GROUP', 'DELETE-VIA-GROUP')
            $result.Rows[0].Detail | Should -BeExactly 'The group was deleted: SharePoint deletes the site some time later (from minutes to hours).'
            $log = @(Get-StubLog)
            $log[5..($log.Count - 1)] | Should -Be @(
                'read https://contoso.sharepoint.com/sites/site1'
                'group 00000001-1111-4111-8111-000000000001'
                'delete group 00000001-1111-4111-8111-000000000001'
                'sleep 2'
                'read https://contoso.sharepoint.com/sites/site2'
                'group 00000002-1111-4111-8111-000000000002'
                'delete group 00000002-1111-4111-8111-000000000002'
                'sleep 2'
                'read https://contoso.sharepoint.com/sites/site3'
                'group 00000003-1111-4111-8111-000000000003'
                'delete group 00000003-1111-4111-8111-000000000003'
                'close'
            )
            $result.Summary.Counts.Done | Should -Be 3
            $result.Summary.ActionsAttempted | Should -Be 3
            $result.Summary.Mode | Should -BeExactly 'Execute'
        }

        It 'does not pause when the pause is 0, and not after the last action' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true; DelaySeconds = 0' -Data @{ Answers = @('contoso', 'DELETE 2') }

            $null = Invoke-TestAct -Run $run

            Get-Calls -Pattern 'sleep*' | Should -HaveCount 0
        }

        It 'locks a site that is unlocked, waits for it, and writes its date in the lock journal' {
            $run = Start-ActScenario -Decision 'Lock' -ActSettings 'Execute = $true' -Override @{ 1 = @{ LockState = 'Unlock' } } -Data @{ Answers = @('contoso', 'APPLY 1') }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Outcome | Should -BeExactly 'Done'
            $result.Rows[0].Verdict | Should -BeExactly 'LOCK'
            (Get-World)['https://contoso.sharepoint.com/sites/site1'].LockState | Should -BeExactly 'ReadOnly'
            $journal = @(Import-Csv -LiteralPath $run.Journal)
            $journal | Should -HaveCount 1
            $journal[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/site1'
            $journal[0].SiteId | Should -BeExactly '00000001-0000-4000-8000-000000000001'
            $journal[0].LockedOn | Should -BeLike '2026-10-30*'
        }

        It 'unlocks, deletes a site without a group, and leaves its lock alone when it works' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Override @{ 1 = @{ GroupId = '' } } -Data @{ Answers = @('contoso', 'DELETE 1') }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Verdict | Should -BeExactly 'DELETE-SITE'
            $result.Rows[0].Outcome | Should -BeExactly 'Done'
            (Get-World)['https://contoso.sharepoint.com/sites/site1'].Exists | Should -BeFalse
            Get-Calls -Pattern 'lock *' | Should -Be @('lock Unlock https://contoso.sharepoint.com/sites/site1')
        }

        It 'archives, unlocking and locking again and adding the administrator, when it is asked to' {
            $run = Start-ActScenario -Decision 'Archive' -ActSettings 'Execute = $true; UnlockBeforeArchive = $true; GrantSiteAdmin = $true' -Data @{ Answers = @('contoso', 'ARCHIVE 1') }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Outcome | Should -BeExactly 'Done'
            $result.Rows[0].Detail | Should -BeExactly 'The archive was requested: it takes place later. The site is locked again.'
            Get-Calls -Pattern 'account' | Should -HaveCount 1
            (Get-StubLog | Where-Object { $_ -like 'lock *' -or $_ -like 'admin *' -or $_ -like 'archive https*' }) | Should -Be @(
                'lock Unlock https://contoso.sharepoint.com/sites/site1'
                'admin admin@contoso.example https://contoso.sharepoint.com/sites/site1'
                'archive https://contoso.sharepoint.com/sites/site1'
                'lock ReadOnly https://contoso.sharepoint.com/sites/site1'
            )
            (Get-World)['https://contoso.sharepoint.com/sites/site1'].ArchiveStatus | Should -BeExactly 'RecentlyArchived'
            (Get-World)['https://contoso.sharepoint.com/sites/site1'].LockState | Should -BeExactly 'ReadOnly'
        }

        It 'does not read the account when no administrator is to be added: <Name>' -ForEach @(
            @{ Name = 'GrantSiteAdmin is off'; ActSettings = 'Execute = $true'; Decision = 'Archive' }
            @{ Name = 'no row is to be archived'; ActSettings = 'Execute = $true; UnlockBeforeArchive = $true; GrantSiteAdmin = $true'; Decision = 'Delete' }
        ) {
            $run = Start-ActScenario -Decision $Decision -ActSettings $ActSettings -Data @{ Answers = @('contoso', "$($Decision.ToUpperInvariant()) 1") }

            $null = Invoke-TestAct -Run $run

            Get-Calls -Pattern 'account' | Should -HaveCount 0
        }
    }

    Context 'MaxActions' {
        It 'does the first actions only, and does not even read the rows after them' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true; MaxActions = 2' -Data @{ Answers = @('contoso', 'DELETE 2') }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Done', 'Done', 'NotRun', 'NotRun')
            $result.Rows[2].Detail | Should -BeLike '*MaxActions (2)*reached*'
            Get-Calls -Pattern 'read *' | Should -HaveCount 2
            Get-Calls -Pattern 'delete group *' | Should -HaveCount 2
            $result.Summary.ActionsAttempted | Should -Be 2
        }

        It 'does not count a row that is not an action' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true; MaxActions = 2' -Override @{ 1 = @{ IsHubSite = $true } } -Data @{ Answers = @('contoso', 'DELETE 2') }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Skipped', 'Done', 'Done', 'NotRun')
        }

        It 'counts an action that failed' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true; MaxActions = 2' -Data @{ Answers = @('contoso', 'DELETE 2'); Fail = @{ 'delete group' = @{ '00000001-1111-4111-8111-000000000001' = 'The group could not be deleted: Forbidden.' } } }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Failed', 'Done', 'NotRun')
        }
    }

    Context 'The stop after 3 errors in a row' {
        It 'stops after 3 actions that fail, and leaves the rows that follow alone, unread' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 5'); Fail = @{ 'delete group' = 'The group could not be deleted: Forbidden.' } }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Failed', 'Failed', 'Failed', 'NotRun', 'NotRun')
            $result.Rows[0].Detail | Should -BeLike '*could not be deleted: Forbidden*'
            $result.Rows[3].Detail | Should -BeLike '*stopped after 3 errors in a row*'
            $result.Summary.StoppedBecause | Should -BeExactly 'ConsecutiveErrors'
            Get-Calls -Pattern 'read *' | Should -HaveCount 3
            Get-Calls -Pattern 'delete group *' | Should -HaveCount 3
        }

        It 'counts the reads that fail with the actions that fail' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{
                Answers = @('contoso', 'DELETE 4')
                Fail    = @{
                    'delete group' = @{ '00000001-1111-4111-8111-000000000001' = 'x' }
                    read           = @{ 'https://contoso.sharepoint.com/sites/site2' = 'y'; 'https://contoso.sharepoint.com/sites/site3' = 'y' }
                }
            }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Failed', 'ReadError', 'ReadError', 'NotRun')
            $result.Summary.StoppedBecause | Should -BeExactly 'ConsecutiveErrors'
        }

        It 'does not stop when a row that is not an error comes in between: E E S E E D' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true' -Override @{ 3 = @{ IsHubSite = $true } } -Data @{
                Answers = @('contoso', 'DELETE 6')
                Fail    = @{ 'delete group' = @{
                        '00000001-1111-4111-8111-000000000001' = 'x'; '00000002-1111-4111-8111-000000000002' = 'x'
                        '00000004-1111-4111-8111-000000000004' = 'x'; '00000005-1111-4111-8111-000000000005' = 'x'
                    }
                }
            }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Failed', 'Failed', 'Skipped', 'Failed', 'Failed', 'Done')
            $result.Summary.StoppedBecause | Should -BeExactly ''
        }

        It 'does not stop when a success comes in between: E E D E E D' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{
                Answers = @('contoso', 'DELETE 6')
                Fail    = @{ 'delete group' = @{
                        '00000001-1111-4111-8111-000000000001' = 'x'; '00000002-1111-4111-8111-000000000002' = 'x'
                        '00000004-1111-4111-8111-000000000004' = 'x'; '00000005-1111-4111-8111-000000000005' = 'x'
                    }
                }
            }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Outcome) | Should -Be @('Failed', 'Failed', 'Done', 'Failed', 'Failed', 'Done')
        }

        It 'locks a site again that was unlocked for a deletion that failed, and the record says so' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Override @{ 1 = @{ GroupId = '' } } -Data @{ Answers = @('contoso', 'DELETE 1'); Fail = @{ 'delete site' = 'The site could not be deleted: Access denied.' } }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Outcome | Should -BeExactly 'Failed'
            $result.Rows[0].Detail | Should -BeLike '*could not be deleted*The site was locked again.'
            (Get-World)['https://contoso.sharepoint.com/sites/site1'].LockState | Should -BeExactly 'ReadOnly'
        }
    }

    Context 'Each row is read again right before its action' {
        It 'does not touch a site that changed since the Scan, or that must not be touched: <Name>' -ForEach @(
            @{ Name = 'a site whose content changed'; Override = @{ LastContentModified = [System.DateTime]::new(2026, 10, 29, 20, 0, 0, [System.DateTimeKind]::Utc) }; Expected = 'REVIEW-CONTENT-MODIFIED'; Outcome = 'Review' }
            @{ Name = 'a site that has a hold'; Override = @{ HasHolds = $true }; Expected = 'REVIEW-RETENTION'; Outcome = 'Review' }
            @{ Name = 'a site whose group is in the recycle bin'; Override = @{ GroupState = 'SoftDeleted' }; Expected = 'REVIEW-GROUP-SOFTDELETED'; Outcome = 'Review' }
            @{ Name = 'a site whose group is gone'; Override = @{ GroupState = 'NotFound' }; Expected = 'REVIEW-GROUP-NOTFOUND'; Outcome = 'Review' }
            @{ Name = 'a site that is no longer read-only'; Override = @{ LockState = 'Unlock' }; Expected = 'SKIP-LOCK-STATE'; Outcome = 'Skipped' }
            @{ Name = 'a site that is gone'; Override = @{ Exists = $false }; Expected = 'SKIP-NOT-FOUND'; Outcome = 'Skipped' }
            @{ Name = 'a site that was replaced by another at its address'; Override = @{ SiteId = '99999999-0000-4000-8000-000000000099' }; Expected = 'SKIP-SITEID-MISMATCH'; Outcome = 'Skipped' }
            @{ Name = 'a hub site'; Override = @{ IsHubSite = $true }; Expected = 'SKIP-PROTECTED'; Outcome = 'Skipped' }
            @{ Name = 'a site that is too large to delete'; Override = @{ StorageUsedMB = [System.Int64]5000 }; Expected = 'SKIP-TOO-LARGE-TO-DELETE'; Outcome = 'Skipped' }
        ) {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Override @{ 1 = $Override } -Data @{ Answers = @('contoso', 'DELETE 1') }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Verdict | Should -BeExactly $Expected
            $result.Rows[0].Outcome | Should -BeExactly $Outcome
            foreach ($pattern in $script:Writes) {
                Get-Calls -Pattern $pattern | Should -HaveCount 0 -Because $pattern
            }

            Get-Calls -Pattern 'read *' | Should -HaveCount 1
        }

        It 'reads each site once, right before its action, and not before the run' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 2') }

            $null = Invoke-TestAct -Run $run

            $log = @(Get-StubLog)
            $log.IndexOf('read https://contoso.sharepoint.com/sites/site1') | Should -BeGreaterThan $log.IndexOf('open')
            $log.IndexOf('delete group 00000001-1111-4111-8111-000000000001') | Should -Be ($log.IndexOf('read https://contoso.sharepoint.com/sites/site1') + 2)
            $log.IndexOf('read https://contoso.sharepoint.com/sites/site2') | Should -BeGreaterThan $log.IndexOf('delete group 00000001-1111-4111-8111-000000000001')
        }
    }

    Context 'What stops the run before the first action' {
        It 'stops before it signs in, naming the line, for what the file holds that is wrong: <Name>' -ForEach @(
            @{ Name = 'a decision that is unknown'; Row = @(@{ Index = 1; Decision = 'Remove' }); Expected = "*line 2*Decision 'Remove'*" }
            @{ Name = 'a file that is too old'; Row = @(@{ Index = 1; Decision = 'Delete'; GeneratedOn = '20260801T080000Z' }); Expected = '*MaxCsvAgeDays*' }
            @{ Name = 'a OneDrive address'; Row = @(@{ Index = 1; Decision = 'Delete'; Url = 'https://contoso-my.sharepoint.com/personal/someone_contoso_com' }); Expected = '*OneDrive*' }
            @{ Name = 'another tenant'; Row = @(@{ Index = 1; Decision = 'Delete'; Url = 'https://fabrikam.sharepoint.com/sites/site1' }); Expected = '*tenant*' }
            @{ Name = 'a site twice'; Row = @(@{ Index = 1; Decision = 'Delete' }, @{ Index = 1; Decision = 'Archive' }); Expected = '*already*' }
        ) {
            Set-ActStub -Site @(New-ActSiteState -Index 1) -Data @{ Answers = @('contoso', 'DELETE 1') }
            $run = New-ActRunFolder -Row $Row -ActSettings 'Execute = $true'

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage $Expected

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before anything for a tenant that is refused' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Settings "RefusedTenants = @('contoso')"

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*refused*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before anything for a lock journal that is damaged' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true'
            $null = New-Item -Path $run.Reports -ItemType Directory
            [System.IO.File]::WriteAllText($run.Journal, "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,`"broken`r`n")

            { Invoke-TestAct -Run $run } | Should -Throw

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before the first action when Microsoft 365 Archive is off and a row is to be archived' {
            $run = Start-ActScenario -Decision 'Delete', 'Archive' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'APPLY 2'); ArchiveEnabled = $false }

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*Microsoft 365 Archive is off*'

            foreach ($pattern in $script:Writes) {
                Get-Calls -Pattern $pattern | Should -HaveCount 0 -Because $pattern
            }

            Get-Calls -Pattern 'read *' | Should -HaveCount 0
            @(Get-StubLog)[-1] | Should -BeExactly 'close'
        }

        It 'goes on, and says so, when it cannot tell whether Microsoft 365 Archive is on' {
            $run = Start-ActScenario -Decision 'Archive' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'ARCHIVE 1'); ArchiveEnabled = $null }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Outcome | Should -BeExactly 'Done'
            ($result.Text -join "`n") | Should -BeLike '*could not tell whether Microsoft 365 Archive is on*'
            @($result.Summary.Warnings) | Should -HaveCount 1
        }

        It 'does not ask about Microsoft 365 Archive when no row is to be archived' {
            $run = Start-ActScenario -Decision 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 1') }

            $null = Invoke-TestAct -Run $run

            Get-Calls -Pattern 'archive enabled?' | Should -HaveCount 0
        }

        It 'only says so, and goes on, in report-only mode, when Microsoft 365 Archive is off' {
            $run = Start-ActScenario -Decision 'Archive' -Data @{ ArchiveEnabled = $false }

            $result = Invoke-TestAct -Run $run

            $result.Rows[0].Outcome | Should -BeExactly 'WouldDo'
            ($result.Text -join "`n") | Should -BeLike '*Microsoft 365 Archive is off*'
        }

        It 'stops before the first action when the account to add as administrator cannot be read' {
            $run = Start-ActScenario -Decision 'Archive' -ActSettings 'Execute = $true; UnlockBeforeArchive = $true; GrantSiteAdmin = $true' -Data @{ Answers = @('contoso', 'ARCHIVE 1'); Fail = @{ account = 'The account that signed in cannot be told.' } }

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*cannot be told*'

            Get-Calls -Pattern 'read *' | Should -HaveCount 0
        }

        It 'ends the session when the run stops, and does not when the sign-in fails' {
            $run = Start-ActScenario -Decision 'Delete' -Data @{ Fail = @{ open = 'The sign-in failed.' } }

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*sign-in failed*'

            Get-Calls -Pattern 'close' | Should -HaveCount 0
        }
    }

    Context 'The record of the run' {
        It 'holds one row for each row with a decision, in the order of the file, and none for a row without one' {
            $run = Start-ActScenario -Decision 'Delete', '', 'Archive', '', 'Delete' -Override @{ 5 = @{ IsHubSite = $true } }

            $result = Invoke-TestAct -Run $run

            @($result.Rows.Line) | Should -Be @('2', '4', '6')
            @($result.Rows.Url) | Should -Be @('https://contoso.sharepoint.com/sites/site1', 'https://contoso.sharepoint.com/sites/site3', 'https://contoso.sharepoint.com/sites/site5')
            @($result.Rows.SiteId) | Should -Be @('00000001-0000-4000-8000-000000000001', '00000003-0000-4000-8000-000000000003', '00000005-0000-4000-8000-000000000005')
            @($result.Rows.ProcessedOn | Select-Object -Unique) | Should -Be @('20261030T090000Z')
        }

        It 'is written in the output folder, as act-<time>.csv, with the delimiter of the settings' {
            $run = Start-ActScenario -Decision 'Delete' -Delimiter ';'

            $result = Invoke-TestAct -Run $run

            $result.Summary.ReportPath | Should -BeExactly (Join-Path -Path $run.Reports -ChildPath 'act-20261030T090000Z.csv')
            (Get-Content -LiteralPath $result.Summary.ReportPath -TotalCount 1).TrimStart([char]0xFEFF) | Should -BeExactly 'Line;Url;SiteId;Decision;Verdict;Outcome;Detail;ProcessedOn'
        }

        It 'keeps the record of what was done when a later row throws something that nobody expected' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete' -ActSettings 'Execute = $true' -Data @{ Answers = @('contoso', 'DELETE 2') }
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

            { Invoke-TestAct -Run $run } | Should -Throw -ExpectedMessage '*Something nobody expected*'

            $report = @(Get-ChildItem -LiteralPath $run.Reports -Filter 'act-*.csv')
            $report | Should -HaveCount 1
            $rows = @(Import-Csv -LiteralPath $report[0].FullName)
            $rows | Should -HaveCount 1
            $rows[0].Outcome | Should -BeExactly 'Done'
        }
    }

    Context 'What the run says' {
        It 'says how it went, in a few lines, and where the record is' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete' -ActSettings 'Execute = $true; MaxActions = 2' -Override @{ 2 = @{ IsHubSite = $true } } -Data @{ Answers = @('contoso', 'DELETE 2') }

            $result = Invoke-TestAct -Run $run

            $result.Text | Should -Contain "Report: $($result.Summary.ReportPath)"
            $result.Text | Should -Contain 'Rows with a decision: 3. Done 2, Failed 0, WouldDo 0, Skipped 1, Review 0, ReadError 0, NotRun 0.'
            @($result.Text | Where-Object { $_ -like 'Act of the tenant contoso ended in *' }) | Should -HaveCount 1
            ($result.Text -join "`n") | Should -BeLike '*EXECUTE: the tenant was changed.*'
        }

        It 'says that a report-only run changed nothing' {
            $run = Start-ActScenario -Decision 'Delete'

            $result = Invoke-TestAct -Run $run

            ($result.Text -join "`n") | Should -BeLike '*REPORT ONLY: nothing was changed.*'
            $result.Text | Should -Contain 'Rows with a decision: 1. Done 0, Failed 0, WouldDo 1, Skipped 0, Review 0, ReadError 0, NotRun 0.'
        }

        It 'says why it stopped' {
            $run = Start-ActScenario -Decision 'Delete', 'Delete', 'Delete', 'Delete' -Data @{ Fail = @{ read = 'x' } }

            $result = Invoke-TestAct -Run $run

            $result.Text | Should -Contain 'The run stopped after 3 errors in a row: the rows that follow were not read.'
        }
    }
}
