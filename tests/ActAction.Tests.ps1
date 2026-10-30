BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:UrlA = 'https://contoso.sharepoint.com/sites/a'
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:Set-ActionStub {
        param([hashtable]$Fail = @{}, [string[]]$Read = @('ReadOnly'))

        Set-ModuleStub -Stub @{
            'Set-SPSLifecycleSiteLockState'   = @'
param($Session, $Url, $State)
$script:StubLog.Add("lock $State")
if ($script:StubData.Fail.ContainsKey("lock $State")) { throw $script:StubData.Fail["lock $State"] }
'@
            'Remove-SPSLifecycleSite'         = @'
param($Session, $Url)
$script:StubLog.Add('delete site')
if ($script:StubData.Fail.ContainsKey('delete site')) { throw $script:StubData.Fail['delete site'] }
'@
            'Remove-SPSLifecycleGroup'        = @'
param($Session, $GroupId)
$script:StubLog.Add("delete group $GroupId")
if ($script:StubData.Fail.ContainsKey('delete group')) { throw $script:StubData.Fail['delete group'] }
'@
            'Request-SPSLifecycleSiteArchive' = @'
param($Session, $Url)
$script:StubLog.Add('archive')
if ($script:StubData.Fail.ContainsKey('archive')) { throw $script:StubData.Fail['archive'] }
'@
            'Add-SPSLifecycleSiteAdmin'       = @'
param($Session, $Url, $Account)
$script:StubLog.Add("admin $Account")
if ($script:StubData.Fail.ContainsKey('admin')) { throw $script:StubData.Fail['admin'] }
'@
            'Add-SPSLifecycleLockJournalEntry' = @'
param($Path, $Url, $SiteId, $LockedOn, $Delimiter)
$script:StubLog.Add("journal path=$Path url=$Url site=$SiteId on=$($LockedOn.ToString('yyyy-MM-dd HH:mm')) delimiter=$Delimiter")
if ($script:StubData.Fail.ContainsKey('journal')) { throw $script:StubData.Fail['journal'] }
$Path
'@
            'Get-SPSLifecycleLiveSite'        = @'
param($Session, $Url)
$script:StubLog.Add('read')
if ($script:StubData.Fail.ContainsKey('read')) { throw $script:StubData.Fail['read'] }
$index = [System.Math]::Min($script:StubData.ReadIndex, $script:StubData.Read.Count - 1)
$script:StubData.ReadIndex++
$state = $script:StubData.Read[$index]
if ($null -eq $state) { return }
[PSCustomObject]@{ LockState = $state }
'@
            'Start-Sleep'                     = @'
param([double]$Seconds)
$script:StubLog.Add("sleep $Seconds")
'@
        } -Data @{ Fail = $Fail; Read = $Read; ReadIndex = 0 }
    }

    function script:New-ActionSetting {
        param([bool]$UnlockBeforeArchive = $false, [bool]$GrantSiteAdmin = $false)

        [PSCustomObject]@{
            LockJournal      = '/reports/lock-journal.csv'
            CsvDelimiterChar = [System.Char]';'
            Act              = [PSCustomObject]@{ UnlockBeforeArchive = $UnlockBeforeArchive; GrantSiteAdmin = $GrantSiteAdmin }
        }
    }

    function script:New-ActionSite {
        param([string]$LockState = 'ReadOnly', [string]$GroupId = $script:GroupA)

        [PSCustomObject]@{ Url = $script:UrlA; SiteId = $script:SiteA; GroupId = $GroupId; LockState = $LockState }
    }

    function script:Invoke-TestAction {
        param([string]$Verdict, $Site = (New-ActionSite), $Setting = (New-ActionSetting), [string]$Account = '')

        $parameters = @{
            Session = [PSCustomObject]@{ Connection = 'a connection' }; Setting = $Setting; Verdict = $Verdict; Site = $Site; Account = $Account; Now = $script:Now
        }
        & $script:Module { param($p) Invoke-SPSLifecycleSiteAction @p } $parameters
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Wait-SPSLifecycleLockState' {
    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Invoke-TestWait {
            param([string]$State = 'Unlock', [int]$Tries = 24)
            & $script:Module { param($s, $t) Wait-SPSLifecycleLockState -Session ([PSCustomObject]@{ Connection = 'a connection' }) -Url 'https://contoso.sharepoint.com/sites/a' -State $s -Tries $t } $State $Tries
        }
    }

    It 'gives true at once when the site is in the state, and does not wait' {
        Set-ActionStub -Read @('Unlock')

        Invoke-TestWait | Should -BeTrue

        Get-StubLog | Should -Be @('read')
    }

    It 'asks again after 5 s until the site is in the state' {
        Set-ActionStub -Read @('ReadOnly', 'ReadOnly', 'Unlock')

        Invoke-TestWait | Should -BeTrue

        Get-StubLog | Should -Be @('read', 'sleep 5', 'read', 'sleep 5', 'read')
    }

    It 'gives false after 24 reads, 23 pauses of 5 s apart (2 minutes), when the site never gets there' {
        Set-ActionStub -Read @('ReadOnly')

        Invoke-TestWait | Should -BeFalse

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount 24
        @(Get-StubLog | Where-Object { $_ -eq 'sleep 5' }) | Should -HaveCount 23
        @(Get-StubLog)[-1] | Should -BeExactly 'read'
    }

    It 'gives false when the number of tries is the one that was asked: <Tries>' -ForEach @(
        @{ Tries = 1 }
        @{ Tries = 3 }
    ) {
        Set-ActionStub -Read @('ReadOnly')

        Invoke-TestWait -Tries $Tries | Should -BeFalse

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount $Tries
    }

    It 'compares the state as it is written: a state in another case is not the state' {
        Set-ActionStub -Read @('readonly')

        Invoke-TestWait -State 'ReadOnly' -Tries 2 | Should -BeFalse
    }

    It 'takes a site that is not there for a site that is not in the state' {
        Set-ActionStub -Read @($null, 'Unlock')

        Invoke-TestWait | Should -BeTrue

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount 2
    }

    It 'does not hide a read that fails: it is an error, and not a state' {
        Set-ActionStub -Fail @{ read = 'The site could not be read.' }

        { Invoke-TestWait } | Should -Throw -ExpectedMessage '*could not be read*'
    }
}

Describe 'Invoke-SPSLifecycleSiteAction' {
    AfterEach {
        Clear-ModuleStub
    }

    Context 'Lock' {
        It 'makes the site read-only, waits for it, and writes the date in the lock journal' {
            Set-ActionStub -Read @('ReadOnly')

            $detail = Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState 'Unlock')

            Get-StubLog | Should -Be @(
                'lock ReadOnly'
                'read'
                "journal path=/reports/lock-journal.csv url=$script:UrlA site=$script:SiteA on=2026-10-30 09:00 delimiter=;"
            )
            $detail | Should -BeExactly 'The site is read-only now, and its date is in the lock journal.'
        }

        It 'writes no date when the site does not get to read-only in 2 minutes, and says that the request was sent' {
            Set-ActionStub -Read @('Unlock')

            { Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState 'Unlock') } | Should -Throw -ExpectedMessage '*did not report ReadOnly within 2 minutes*request*sent*'

            @(Get-StubLog | Where-Object { $_ -like 'journal*' }) | Should -HaveCount 0
        }

        It 'does not wait and writes no date when the request fails' {
            Set-ActionStub -Fail @{ 'lock ReadOnly' = 'The lock state of the site could not be set to ReadOnly: Access denied.' }

            { Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState 'Unlock') } | Should -Throw -ExpectedMessage '*could not be set to ReadOnly*'

            Get-StubLog | Should -Be @('lock ReadOnly')
        }

        It 'says that the site is locked, and that its date is not in the journal, when the journal cannot be written' {
            Set-ActionStub -Fail @{ journal = 'The lock journal is open in another program.' }

            { Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState 'Unlock') } | Should -Throw -ExpectedMessage '*locked*not in the lock journal*open in another program*'
        }

        It 'locks a site that is unlocked and nothing else: <LockState>' -ForEach @(
            @{ LockState = 'ReadOnly' }
            @{ LockState = 'NoAccess' }
            @{ LockState = '' }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState $LockState) } | Should -Throw -ExpectedMessage '*only an unlocked site*'

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'Delete a site that has no group' {
        It 'unlocks a read-only site, waits for it, and deletes it' {
            Set-ActionStub -Read @('Unlock')

            $detail = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '')

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'delete site')
            $detail | Should -BeExactly 'The site was deleted: it is in the recycle bin of the deleted sites.'
        }

        It 'deletes an unlocked site directly: it has nothing to unlock and nothing to lock again' {
            Set-ActionStub

            $null = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -LockState 'Unlock' -GroupId '')

            Get-StubLog | Should -Be @('delete site')
        }

        It 'locks the site again, and says so, when the deletion fails after the unlock' {
            Set-ActionStub -Read @('Unlock') -Fail @{ 'delete site' = "The site '$script:UrlA' could not be deleted: Access denied." }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*could not be deleted*Access denied*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'delete site', 'lock ReadOnly')
        }

        It 'locks the site again when it does not unlock in 2 minutes: the request may be applied later' {
            Set-ActionStub -Read @('ReadOnly')

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*did not report Unlock within 2 minutes*The site was locked again.'

            @(Get-StubLog)[-1] | Should -BeExactly 'lock ReadOnly'
            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'does not lock the site again when the unlock request itself fails: nothing was unlocked' {
            Set-ActionStub -Fail @{ 'lock Unlock' = 'The lock state of the site could not be set to Unlock: Access denied.' }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*could not be set to Unlock*'

            Get-StubLog | Should -Be @('lock Unlock')
        }

        It 'says that the site could not be locked again, and to lock it by hand, when that fails too' {
            Set-ActionStub -Read @('Unlock') -Fail @{ 'delete site' = 'The site could not be deleted: Access denied.'; 'lock ReadOnly' = 'The lock state could not be set to ReadOnly: Throttled.' }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*Access denied*could not be locked again*Throttled*by hand*'
        }

        It 'does not touch a site that is neither read-only nor unlocked: <LockState>' -ForEach @(
            @{ LockState = 'NoAccess' }
            @{ LockState = 'readonly' }
            @{ LockState = '' }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -LockState $LockState -GroupId '') } | Should -Throw -ExpectedMessage '*lock state*ReadOnly or Unlock*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'does not delete a site that has a group: it would leave the group behind' {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite) } | Should -Throw -ExpectedMessage '*has a group*'

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'Delete through the group' {
        It 'deletes the group by its ID, without unlocking the site' {
            Set-ActionStub

            $detail = Invoke-TestAction -Verdict 'DELETE-VIA-GROUP'

            Get-StubLog | Should -Be @("delete group $script:GroupA")
            $detail | Should -BeExactly 'The group was deleted: SharePoint deletes the site some time later (from minutes to hours).'
        }

        It 'does not delete a group that the site does not have: <GroupId>' -ForEach @(
            @{ GroupId = '' }
            @{ GroupId = '00000000-0000-0000-0000-000000000000' }
            @{ GroupId = 'not-a-guid' }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'DELETE-VIA-GROUP' -Site (New-ActionSite -GroupId $GroupId) } | Should -Throw -ExpectedMessage '*no group*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'does not hide a failure of the deletion' {
            Set-ActionStub -Fail @{ 'delete group' = 'The group could not be deleted: Forbidden.' }

            { Invoke-TestAction -Verdict 'DELETE-VIA-GROUP' } | Should -Throw -ExpectedMessage '*could not be deleted*Forbidden*'
        }
    }

    Context 'Archive' {
        It 'asks for the archive, and does nothing else, by default' {
            Set-ActionStub

            $detail = Invoke-TestAction -Verdict 'ARCHIVE'

            Get-StubLog | Should -Be @('archive')
            $detail | Should -BeExactly 'The archive was requested: it takes place later.'
        }

        It 'unlocks a read-only site before the archive, and locks it again afterwards, when it is asked to' {
            Set-ActionStub -Read @('Unlock')

            $detail = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true)

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'archive', 'lock ReadOnly')
            $detail | Should -BeExactly 'The archive was requested: it takes place later. The site is locked again.'
        }

        It 'adds the administrator who signed in between the unlock and the archive, when it is asked to' {
            Set-ActionStub -Read @('Unlock')

            $null = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'admin admin@contoso.example', 'archive', 'lock ReadOnly')
        }

        It 'does not unlock, and does not lock again, a site that is not locked' {
            Set-ActionStub

            $detail = Invoke-TestAction -Verdict 'ARCHIVE' -Site (New-ActionSite -LockState 'Unlock') -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example'

            Get-StubLog | Should -Be @('admin admin@contoso.example', 'archive')
            $detail | Should -BeExactly 'The archive was requested: it takes place later.'
        }

        It 'stops before it changes anything when the administrator is to be added and the account is not known' {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account '' } | Should -Throw -ExpectedMessage '*GrantSiteAdmin*account*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'locks the site again, and says so, when the archive fails after the unlock' {
            Set-ActionStub -Read @('Unlock') -Fail @{ archive = "The archive of the site '$script:UrlA' could not be requested: Access denied." }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*could not be requested*Access denied*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'archive', 'lock ReadOnly')
        }

        It 'locks the site again when the administrator cannot be added' {
            Set-ActionStub -Read @('Unlock') -Fail @{ admin = 'The administrator could not be added: Access denied.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example' } | Should -Throw -ExpectedMessage '*could not be added*The site was locked again.'

            @(Get-StubLog)[-1] | Should -BeExactly 'lock ReadOnly'
            @(Get-StubLog | Where-Object { $_ -eq 'archive' }) | Should -HaveCount 0
        }

        It 'says that the archive was requested but the site could not be locked again, as an error, when the lock fails afterwards' {
            Set-ActionStub -Read @('Unlock') -Fail @{ 'lock ReadOnly' = 'The lock state could not be set to ReadOnly: Throttled.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*archive was requested*could not be locked again*Throttled*by hand*'
        }

        It 'does not archive a site that is neither read-only nor unlocked: <LockState>' -ForEach @(
            @{ LockState = 'NoAccess' }
            @{ LockState = '' }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'ARCHIVE' -Site (New-ActionSite -LockState $LockState) } | Should -Throw -ExpectedMessage '*lock state*ReadOnly or Unlock*'

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'Whatever the verdict' {
        It 'does nothing for a verdict that is not an action: <Verdict>' -ForEach @(
            @{ Verdict = 'SKIP-LOCK-STATE' }
            @{ Verdict = 'REVIEW-CONTENT-MODIFIED' }
            @{ Verdict = 'SKIP-NOT-FOUND' }
            @{ Verdict = 'delete-site' }
            @{ Verdict = 'DELETE' }
            @{ Verdict = '' }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict $Verdict } | Should -Throw -ExpectedMessage '*not an action*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'does nothing without a live site: <Name>' -ForEach @(
            @{ Name = 'no site'; Site = $null }
            @{ Name = 'a site without an address'; Site = [PSCustomObject]@{ Url = ''; SiteId = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'; GroupId = ''; LockState = 'Unlock' } }
            @{ Name = 'a site without an ID'; Site = [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/a'; SiteId = ''; GroupId = ''; LockState = 'Unlock' } }
        ) {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'LOCK' -Site $Site } | Should -Throw

            Get-StubLog | Should -HaveCount 0
        }
    }
}
