BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:UrlA = 'https://contoso.sharepoint.com/sites/a'
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'
    $script:Modified = [System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    # The site as it is read: what the verdict was given from, and what each read after it gives, with the state that it reports.
    function script:New-LiveSite {
        param([hashtable]$Override = @{})

        $values = [ordered]@{
            Url                     = $script:UrlA
            SiteId                  = $script:SiteA
            Title                   = 'Sales'
            Template                = 'GROUP#0'
            LockState               = 'ReadOnly'
            GroupId                 = $script:GroupA
            IsHubSite               = $false
            IsTeamsConnected        = $true
            IsTeamsChannelConnected = $false
            ArchiveStatus           = 'NotArchived'
            StorageUsedMB           = [System.Int64]12
            LastContentModified     = $script:Modified
            HasHolds                = $false
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    # -Read is what the reads of the site give, one after the other, the last one for ever: a state (a text), nothing (the site is not
    # there), or a hashtable of what differs from the site, with the state in LockState.
    function script:Set-ActionStub {
        param([hashtable]$Fail = @{}, [object[]]$Read = @('ReadOnly'))

        Set-ModuleStub -Stub @{
            'Set-SPSLifecycleSiteLockState'    = @'
param($Session, $Url, $State)
$script:StubLog.Add("lock $State")
if ($script:StubData.Fail.ContainsKey("lock $State")) { throw $script:StubData.Fail["lock $State"] }
'@
            'Remove-SPSLifecycleSite'          = @'
param($Session, $Url)
$script:StubLog.Add('delete site')
if ($script:StubData.Fail.ContainsKey('delete site')) { throw $script:StubData.Fail['delete site'] }
'@
            'Remove-SPSLifecycleGroup'         = @'
param($Session, $GroupId)
$script:StubLog.Add("delete group $GroupId")
if ($script:StubData.Fail.ContainsKey('delete group')) { throw $script:StubData.Fail['delete group'] }
'@
            'Request-SPSLifecycleSiteArchive'  = @'
param($Session, $Url)
$script:StubLog.Add('archive')
if ($script:StubData.Fail.ContainsKey('archive')) { throw $script:StubData.Fail['archive'] }
'@
            'Add-SPSLifecycleSiteAdmin'        = @'
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
            'Get-SPSLifecycleLiveSite'         = @'
param($Session, $Url)
$script:StubLog.Add('read')
if ($script:StubData.Fail.ContainsKey('read')) { throw $script:StubData.Fail['read'] }
$index = [System.Math]::Min($script:StubData.ReadIndex, $script:StubData.Read.Count - 1)
$script:StubData.ReadIndex++
$item = $script:StubData.Read[$index]
if ($null -eq $item) { return }
$record = [ordered]@{}
foreach ($property in $script:StubData.Base.PSObject.Properties) { $record[$property.Name] = $property.Value }
if ($item -is [hashtable]) { foreach ($key in $item.Keys) { $record[$key] = $item[$key] } } else { $record['LockState'] = $item }
[PSCustomObject]$record
'@
            'Get-SPSLifecycleGroupState'       = @'
param($Session, $GroupId)
$script:StubLog.Add('group')
if ($script:StubData.Fail.ContainsKey('group')) { throw $script:StubData.Fail['group'] }
$script:StubData.GroupState
'@
            'Get-SPSLifecycleHomeSiteUrl'      = @'
param($Session)
$script:StubLog.Add('home site')
if ($script:StubData.Fail.ContainsKey('home site')) { throw $script:StubData.Fail['home site'] }
$script:StubData.HomeSite
'@
            'Start-Sleep'                      = @'
param([double]$Seconds)
$script:StubLog.Add("sleep $Seconds")
'@
        } -Data @{ Fail = $Fail; Read = $Read; ReadIndex = 0; Base = (New-LiveSite); GroupState = 'Active'; HomeSite = '' }
    }

    function script:New-ActionSetting {
        param([bool]$UnlockBeforeArchive = $false, [bool]$GrantSiteAdmin = $false)

        [PSCustomObject]@{
            LockJournal      = '/reports/lock-journal.csv'
            CsvDelimiterChar = [System.Char]';'
            DeleteMaxSizeGB  = 1.0
            Act              = [PSCustomObject]@{ UnlockBeforeArchive = $UnlockBeforeArchive; GrantSiteAdmin = $GrantSiteAdmin }
        }
    }

    function script:New-ActionSite {
        param([string]$LockState = 'ReadOnly', [string]$GroupId = $script:GroupA)

        New-LiveSite -Override @{ LockState = $LockState; GroupId = $GroupId }
    }

    function script:Invoke-TestAction {
        param([string]$Verdict, $Site = (New-ActionSite), $Setting = (New-ActionSetting), [string]$Account = '')

        # The reads of the site that follow give the site that the verdict was given from, with the state that each one reports.
        if ($null -ne $Site) { & $script:Module { param($b) $script:StubData.Base = $b } $Site }
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
        # -Tries and -SiteId are given only when a test asks for them: the others use what the function has by default.
        function script:Invoke-TestWait {
            param([string]$State = 'Unlock', [int]$Tries = 0, [string]$SiteId = '')
            $parameters = @{ Session = [PSCustomObject]@{ Connection = 'a connection' }; Url = 'https://contoso.sharepoint.com/sites/a'; State = $State }
            if ($Tries -gt 0) { $parameters.Tries = $Tries }
            if ($SiteId) { $parameters.SiteId = $SiteId }
            & $script:Module { param($p) Wait-SPSLifecycleLockState @p } $parameters
        }
    }

    It 'gives the record that was read at once when the site is in the state, and does not wait' {
        Set-ActionStub -Read @('Unlock')

        $site = Invoke-TestWait

        $site.LockState | Should -BeExactly 'Unlock'
        $site.SiteId | Should -BeExactly $script:SiteA
        Get-StubLog | Should -Be @('read')
    }

    It 'asks again after 5 s until the site is in the state' {
        Set-ActionStub -Read @('ReadOnly', 'ReadOnly', 'Unlock')

        (Invoke-TestWait).LockState | Should -BeExactly 'Unlock'

        Get-StubLog | Should -Be @('read', 'sleep 5', 'read', 'sleep 5', 'read')
    }

    It 'gives nothing after 24 reads, 23 pauses of 5 s apart (2 minutes), when the site never gets there' {
        Set-ActionStub -Read @('ReadOnly')

        Invoke-TestWait | Should -BeNullOrEmpty

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount 24
        @(Get-StubLog | Where-Object { $_ -eq 'sleep 5' }) | Should -HaveCount 23
        @(Get-StubLog)[-1] | Should -BeExactly 'read'
    }

    It 'gives nothing after the number of tries that was asked: <Tries>' -ForEach @(
        @{ Tries = 1 }
        @{ Tries = 3 }
    ) {
        Set-ActionStub -Read @('ReadOnly')

        Invoke-TestWait -Tries $Tries | Should -BeNullOrEmpty

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount $Tries
    }

    It 'compares the state as it is written: a state in another case is not the state' {
        Set-ActionStub -Read @('readonly')

        Invoke-TestWait -State 'ReadOnly' -Tries 2 | Should -BeNullOrEmpty
    }

    It 'takes a site that is not there for a site that is not in the state' {
        Set-ActionStub -Read @($null, 'Unlock')

        (Invoke-TestWait).LockState | Should -BeExactly 'Unlock'

        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount 2
    }

    It 'does not hide a read that fails: it is an error, and not a state' {
        Set-ActionStub -Fail @{ read = 'The site could not be read.' }

        { Invoke-TestWait } | Should -Throw -ExpectedMessage '*could not be read*'
    }

    It 'goes on when the site is the one that is waited for' {
        Set-ActionStub -Read @('ReadOnly', 'Unlock')

        (Invoke-TestWait -SiteId $script:SiteA).LockState | Should -BeExactly 'Unlock'
    }

    It 'stops, and does not take the state of another site for the state of this one, when the address is reused while it waits' {
        Set-ActionStub -Read @('ReadOnly', @{ LockState = 'Unlock'; SiteId = $script:SiteB })

        { Invoke-TestWait -SiteId $script:SiteA } | Should -Throw -ExpectedMessage "*another site*is not $script:SiteA*"
    }

    It 'does not look at the site ID when it was not given one' {
        Set-ActionStub -Read @(@{ LockState = 'Unlock'; SiteId = $script:SiteB })

        (Invoke-TestWait).SiteId | Should -BeExactly $script:SiteB
    }
}

Describe 'Get-SPSLifecycleSiteChange' {
    BeforeAll {
        function script:Get-TestChange {
            param([hashtable]$Override = @{}, [switch]$CheckSize, [double]$Max = 1.0)

            $before = New-LiveSite
            $after = New-LiveSite -Override (@{ LockState = 'Unlock' } + $Override)
            & $script:Module { param($b, $a, $c, $m) Get-SPSLifecycleSiteChange -Before $b -After $a -CheckSize:$c -DeleteMaxSizeGB $m } $before $after ([bool]$CheckSize) $Max
        }
    }

    It 'says nothing changed when only the lock state is not the same: it is what the unlock changed' {
        Get-TestChange | Should -BeExactly ''
    }

    It 'says what changed, in words, for each thing that the verdict was given from: <Name>' -ForEach @(
        @{ Name = 'the site ID'; Override = @{ SiteId = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c' }; Expected = '*site ID*another site*' }
        @{ Name = 'a site ID that is not one'; Override = @{ SiteId = 'nope' }; Expected = '*site ID*another site*' }
        @{ Name = 'the address'; Override = @{ Url = 'https://contoso.sharepoint.com/sites/other' }; Expected = '*address*' }
        @{ Name = 'the template'; Override = @{ Template = 'STS#3' }; Expected = '*template*' }
        @{ Name = 'the template in another case'; Override = @{ Template = 'group#0' }; Expected = '*template*' }
        @{ Name = 'the group'; Override = @{ GroupId = '22222222-2222-2222-2222-222222222222' }; Expected = '*group*' }
        @{ Name = 'the group, gone'; Override = @{ GroupId = '' }; Expected = '*group*' }
        @{ Name = 'a group ID that is not a GUID'; Override = @{ GroupId = 'not-a-guid' }; Expected = '*group ID is not a GUID*' }
        @{ Name = 'the hub site flag'; Override = @{ IsHubSite = $true }; Expected = '*hub site*' }
        @{ Name = 'a hub site flag that is not a boolean'; Override = @{ IsHubSite = $null }; Expected = '*hub site*' }
        @{ Name = 'the channel site flag'; Override = @{ IsTeamsChannelConnected = $true }; Expected = '*channel site*' }
        @{ Name = 'the archive status'; Override = @{ ArchiveStatus = 'RecentlyArchived' }; Expected = '*archive status*' }
        @{ Name = 'a hold'; Override = @{ HasHolds = $true }; Expected = '*hold*' }
        @{ Name = 'a hold that is not reported'; Override = @{ HasHolds = $null }; Expected = '*hold*' }
        @{ Name = 'a hold that is a text'; Override = @{ HasHolds = 'False' }; Expected = '*hold*' }
        @{ Name = 'the content, written a second later'; Override = @{ LastContentModified = ([System.DateTime]::new(2025, 1, 5, 10, 0, 1, [System.DateTimeKind]::Utc)) }; Expected = '*content changed*' }
        @{ Name = 'a content date that cannot be read'; Override = @{ LastContentModified = $null }; Expected = '*date of its content*' }
    ) {
        Get-TestChange -Override $Override | Should -BeLike $Expected
    }

    It 'reads a group ID that is written another way as the same group: <Name>' -ForEach @(
        @{ Name = 'with braces'; GroupId = '{11111111-1111-1111-1111-111111111111}' }
        @{ Name = 'in capitals'; GroupId = '11111111-1111-1111-1111-111111111111'.ToUpperInvariant() }
    ) {
        Get-TestChange -Override @{ GroupId = $GroupId } | Should -BeExactly ''
    }

    It 'reads no group, an empty group ID and the all-zero one as the same: <Name>' -ForEach @(
        @{ Name = 'an empty text'; After = '' }
        @{ Name = 'all zeros'; After = '00000000-0000-0000-0000-000000000000' }
    ) {
        $before = New-LiveSite -Override @{ GroupId = '' }
        $after = New-LiveSite -Override @{ GroupId = $After }

        & $script:Module { param($b, $a) Get-SPSLifecycleSiteChange -Before $b -After $a } $before $after | Should -BeExactly ''
    }

    It 'does not count a content date that is earlier, or the same, as a change' -ForEach @(
        @{ Date = [System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc) }
        @{ Date = [System.DateTime]::new(2024, 12, 1, 0, 0, 0, [System.DateTimeKind]::Utc) }
    ) {
        Get-TestChange -Override @{ LastContentModified = $Date } | Should -BeExactly ''
    }

    It 'reads the size only for a deletion: <Name>' -ForEach @(
        @{ Name = 'a size above the limit is no change for another action'; Override = @{ StorageUsedMB = [System.Int64]5000 }; Check = $false; Expected = '' }
        @{ Name = 'a size above the limit stops a deletion'; Override = @{ StorageUsedMB = [System.Int64]5000 }; Check = $true; Expected = '*size*DeleteMaxSizeGB*' }
        @{ Name = 'the size at the limit is not above it'; Override = @{ StorageUsedMB = [System.Int64]1024 }; Check = $true; Expected = '' }
        @{ Name = 'a size a megabyte above the limit is above it'; Override = @{ StorageUsedMB = [System.Int64]1025 }; Check = $true; Expected = '*size*DeleteMaxSizeGB*' }
        @{ Name = 'an empty site has a size that is known: it is zero'; Override = @{ StorageUsedMB = [System.Int64]0 }; Check = $true; Expected = '' }
        @{ Name = 'a size that is not known stops a deletion'; Override = @{ StorageUsedMB = $null }; Check = $true; Expected = '*size is unknown*' }
        @{ Name = 'a size that is below zero stops a deletion'; Override = @{ StorageUsedMB = [System.Int64]-1 }; Check = $true; Expected = '*size is unknown*' }
        @{ Name = 'a size that is a text stops a deletion'; Override = @{ StorageUsedMB = '12' }; Check = $true; Expected = '*size is unknown*' }
    ) {
        $change = if ($Check) { Get-TestChange -Override $Override -CheckSize } else { Get-TestChange -Override $Override }

        if ($Expected) { $change | Should -BeLike $Expected } else { $change | Should -BeExactly '' }
    }

    It 'tells the first thing that changed, and the site ID before the rest' {
        Get-TestChange -Override @{ SiteId = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'; Template = 'STS#3'; HasHolds = $true } | Should -BeLike '*site ID*'
    }
}

Describe 'Restore-SPSLifecycleSiteLock' {
    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Invoke-TestRestore {
            & $script:Module { Restore-SPSLifecycleSiteLock -Session ([PSCustomObject]@{ Connection = 'a connection' }) -Url 'https://contoso.sharepoint.com/sites/a' -SiteId 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64' }
        }
    }

    It 'reads the site, asks for the lock, waits for the site to report it, and says that it is locked again' {
        Set-ActionStub -Read @('Unlock', 'ReadOnly')

        $result = Invoke-TestRestore

        $result.Locked | Should -BeTrue
        $result.Note | Should -BeExactly 'The site was locked again.'
        Get-StubLog | Should -Be @('read', 'lock ReadOnly', 'read')
    }

    It 'asks for the lock even when the site reports ReadOnly, since a request to unlock may still be on its way' {
        Set-ActionStub -Read @('ReadOnly')

        (Invoke-TestRestore).Locked | Should -BeTrue

        Get-StubLog | Should -Contain 'lock ReadOnly'
    }

    It 'does not say that the site is locked when it does not report it in 2 minutes: the request was accepted and nothing changed' {
        Set-ActionStub -Read @('Unlock')

        $result = Invoke-TestRestore

        $result.Locked | Should -BeFalse
        $result.Note | Should -BeExactly 'The lock request was sent, but the site did not report ReadOnly within 2 minutes: check it, and lock it by hand if it is not read-only.'
        @(Get-StubLog | Where-Object { $_ -eq 'read' }) | Should -HaveCount 25
    }

    It 'does not lock a site that is another one now, and says so' {
        Set-ActionStub -Read @(@{ LockState = 'Unlock'; SiteId = $script:SiteB })

        $result = Invoke-TestRestore

        $result.Locked | Should -BeFalse
        $result.Note | Should -BeExactly 'The address belongs to another site now, which was left as it is.'
        Get-StubLog | Should -Be @('read')
    }

    It 'does not lock a site that is not there, and says so' {
        Set-ActionStub -Read @($null)

        $result = Invoke-TestRestore

        $result.Locked | Should -BeFalse
        $result.Note | Should -BeExactly 'The site is not there any more, so there is nothing to lock again.'
        Get-StubLog | Should -Be @('read')
    }

    It 'says that it could not, and why, and does not throw: <Name>' -ForEach @(
        @{ Name = 'the read fails'; Fail = @{ read = 'Throttled.' }; Expected = 'The site could not be locked again: Throttled. Lock it by hand.' }
        @{ Name = 'the request fails'; Fail = @{ 'lock ReadOnly' = 'The lock state could not be set to ReadOnly: Forbidden.' }; Expected = 'The site could not be locked again: The lock state could not be set to ReadOnly: Forbidden. Lock it by hand.' }
    ) {
        Set-ActionStub -Fail $Fail -Read @('Unlock')

        $result = Invoke-TestRestore

        $result.Locked | Should -BeFalse
        $result.Note | Should -BeExactly $Expected
    }

    It 'says that it could not when another site takes the address while it waits' {
        Set-ActionStub -Read @('Unlock', @{ LockState = 'ReadOnly'; SiteId = $script:SiteB })

        $result = Invoke-TestRestore

        $result.Locked | Should -BeFalse
        $result.Note | Should -BeLike 'The site could not be locked again: *another site*Lock it by hand.'
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

        It 'writes no date when the address is another site by the time the lock shows' {
            Set-ActionStub -Read @(@{ LockState = 'ReadOnly'; SiteId = $script:SiteB })

            { Invoke-TestAction -Verdict 'LOCK' -Site (New-ActionSite -LockState 'Unlock') } | Should -Throw -ExpectedMessage '*another site*'

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
        It 'unlocks a read-only site, waits for it, reads it again, and deletes it' {
            Set-ActionStub -Read @('Unlock')

            $detail = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '')

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'home site', 'delete site')
            $detail | Should -BeExactly 'The site was deleted: it is in the recycle bin of the deleted sites.'
        }

        It 'deletes an unlocked site directly: it has nothing to unlock and nothing to lock again' {
            Set-ActionStub

            $null = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -LockState 'Unlock' -GroupId '')

            Get-StubLog | Should -Be @('delete site')
        }

        It 'locks the site again, confirms it, and says so, when the deletion fails after the unlock' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly') -Fail @{ 'delete site' = "The site '$script:UrlA' could not be deleted: Access denied." }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*could not be deleted*Access denied*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'home site', 'delete site', 'read', 'lock ReadOnly', 'read')
        }

        It 'does not say that the site was locked again when it does not report it: the request is asynchronous' {
            Set-ActionStub -Read @('Unlock') -Fail @{ 'delete site' = "The site '$script:UrlA' could not be deleted: Access denied." }

            $message = ''
            try { $null = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } catch { $message = $_.Exception.Message }

            $message | Should -BeLike '*could not be deleted*did not report ReadOnly within 2 minutes*lock it by hand*'
            $message | Should -Not -BeLike '*was locked again*'
        }

        It 'locks the site again when it does not unlock in 2 minutes: the request may be applied later' {
            Set-ActionStub -Read @('ReadOnly')

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*did not report Unlock within 2 minutes*The site was locked again.'

            Get-StubLog | Should -Contain 'lock ReadOnly'
            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'locks the site again when the unlock request itself fails: a request that throws may have been applied all the same' {
            Set-ActionStub -Fail @{ 'lock Unlock' = 'The lock state of the site could not be set to Unlock: Throttled.' }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*could not be set to Unlock*Throttled*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'lock ReadOnly', 'read')
            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'locks the site again when the archive unlock request itself fails' {
            Set-ActionStub -Fail @{ 'lock Unlock' = 'The lock state of the site could not be set to Unlock: Throttled.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*could not be set to Unlock*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'lock ReadOnly', 'read')
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

    Context 'The site is read again once it is unlocked, and nothing is done if it changed' {
        It 'does not delete, and locks the site again, when it changed while it was unlocked: <Name>' -ForEach @(
            @{ Name = 'its content changed'; After = @{ LockState = 'Unlock'; LastContentModified = ([System.DateTime]::new(2026, 10, 30, 8, 59, 0, [System.DateTimeKind]::Utc)) }; Expected = '*changed while it was unlocked (its content changed), so it was not touched.*' }
            @{ Name = 'a hold appeared'; After = @{ LockState = 'Unlock'; HasHolds = $true }; Expected = '*changed while it was unlocked (the tenant reports a hold*' }
            @{ Name = 'the hold is not reported any more'; After = @{ LockState = 'Unlock'; HasHolds = $null }; Expected = '*changed while it was unlocked (the tenant reports a hold on it, or does not report the flag)*' }
            @{ Name = 'it became large'; After = @{ LockState = 'Unlock'; StorageUsedMB = [System.Int64]5000 }; Expected = '*changed while it was unlocked (its size is above DeleteMaxSizeGB)*' }
            @{ Name = 'it became a hub site'; After = @{ LockState = 'Unlock'; IsHubSite = $true }; Expected = '*changed while it was unlocked (its hub site flag is not the same)*' }
            @{ Name = 'it got a group'; After = @{ LockState = 'Unlock'; GroupId = '22222222-2222-2222-2222-222222222222' }; Expected = '*changed while it was unlocked (its group is not the same)*' }
            @{ Name = 'its template changed'; After = @{ LockState = 'Unlock'; Template = 'STS#3' }; Expected = '*changed while it was unlocked (its template is not the same)*' }
            @{ Name = 'it started to be archived'; After = @{ LockState = 'Unlock'; ArchiveStatus = 'RecentlyArchived' }; Expected = '*changed while it was unlocked (its archive status is not the same)*' }
        ) {
            Set-ActionStub -Read @($After, 'Unlock', 'ReadOnly')

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage $Expected

            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
            @(Get-StubLog | Where-Object { $_ -like 'lock *' }) | Should -Be @('lock Unlock', 'lock ReadOnly')
        }

        It 'does not delete a site that another site replaced at its address, and does not lock the other site' {
            Set-ActionStub -Read @(@{ LockState = 'Unlock'; SiteId = $script:SiteB }, @{ LockState = 'Unlock'; SiteId = $script:SiteB })

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*another site*left as it is.'

            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
            @(Get-StubLog | Where-Object { $_ -like 'lock *' }) | Should -Be @('lock Unlock')
        }

        It 'does not archive, add the administrator or ask for anything else, when the site changed while it was unlocked' {
            Set-ActionStub -Read @(@{ LockState = 'Unlock'; HasHolds = $true }, 'Unlock', 'ReadOnly')

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example' } | Should -Throw -ExpectedMessage '*changed while it was unlocked*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -like 'admin*' -or $_ -eq 'archive' }) | Should -HaveCount 0
        }

        It 'does not delete a site whose group ID became something that is not a GUID: it is not "no group"' {
            Set-ActionStub -Read @(@{ LockState = 'Unlock'; GroupId = 'not-a-guid' }, 'Unlock', 'ReadOnly')

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*changed while it was unlocked (its group ID is not a GUID)*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'does not act on a site whose group is not active any more while it was unlocked, whatever its ID: <State>' -ForEach @(
            @{ State = 'SoftDeleted' }
            @{ State = 'NotFound' }
            @{ State = 'active' }
            @{ State = '' }
        ) {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly')
            & $script:Module { param($s) $script:StubData.GroupState = $s } $State

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*group of the site is not active any more*while the site was unlocked*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -eq 'archive' }) | Should -HaveCount 0
        }

        It 'does not act when the group cannot be read while the site is unlocked, and locks the site again' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly') -Fail @{ group = 'The Microsoft 365 group could not be read: Throttled.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*group could not be read*Throttled*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -eq 'archive' }) | Should -HaveCount 0
        }

        It 'does not read the group of a site that has none' {
            Set-ActionStub -Read @('Unlock')

            $null = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '')

            @(Get-StubLog | Where-Object { $_ -eq 'group' }) | Should -HaveCount 0
        }

        It 'does not act on a site that became the home site of the tenant while it was unlocked' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly')
            & $script:Module { $script:StubData.HomeSite = 'HTTPS://Contoso.SharePoint.com/Sites/A/' }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*home site of the tenant now*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'does not act when the home site cannot be read while the site is unlocked, and locks the site again' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly') -Fail @{ 'home site' = 'The home site of the tenant could not be read: Throttled.' }

            { Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -GroupId '') } | Should -Throw -ExpectedMessage '*home site*could not be read*Throttled*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -eq 'delete site' }) | Should -HaveCount 0
        }

        It 'does not read the home site of a site that was not unlocked: the verdict has just read it' {
            Set-ActionStub

            $null = Invoke-TestAction -Verdict 'DELETE-SITE' -Site (New-ActionSite -LockState 'Unlock' -GroupId '')

            @(Get-StubLog | Where-Object { $_ -eq 'home site' }) | Should -HaveCount 0
        }

        It 'does not check the size of a site that is archived: the size does not matter for an archive' {
            Set-ActionStub -Read @(@{ LockState = 'Unlock'; StorageUsedMB = [System.Int64]5000 }, 'ReadOnly')

            $detail = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true)

            $detail | Should -BeExactly 'The archive was requested: it takes place later. The site is locked again.'
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

        It 'deletes the group of a read-only site and of an unlocked one, and of nothing else: <LockState>' -ForEach @(
            @{ LockState = 'ReadOnly'; Expected = $true }
            @{ LockState = 'Unlock'; Expected = $true }
            @{ LockState = 'NoAccess'; Expected = $false }
            @{ LockState = 'readonly'; Expected = $false }
            @{ LockState = ''; Expected = $false }
        ) {
            Set-ActionStub

            if ($Expected) {
                $null = Invoke-TestAction -Verdict 'DELETE-VIA-GROUP' -Site (New-ActionSite -LockState $LockState)
                Get-StubLog | Should -Be @("delete group $script:GroupA")
            }
            else {
                { Invoke-TestAction -Verdict 'DELETE-VIA-GROUP' -Site (New-ActionSite -LockState $LockState) } | Should -Throw -ExpectedMessage '*lock state*ReadOnly or Unlock*'
                Get-StubLog | Should -HaveCount 0
            }
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
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly')

            $detail = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true)

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'group', 'home site', 'archive', 'read', 'lock ReadOnly', 'read')
            $detail | Should -BeExactly 'The archive was requested: it takes place later. The site is locked again.'
        }

        It 'adds the administrator who signed in between the unlock and the archive, when it is asked to' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly')

            $null = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example'

            @(Get-StubLog | Where-Object { $_ -like 'lock *' -or $_ -like 'admin *' -or $_ -eq 'archive' }) | Should -Be @('lock Unlock', 'admin admin@contoso.example', 'archive', 'lock ReadOnly')
        }

        It 'does not unlock, and does not lock again, a site that is not locked' {
            Set-ActionStub

            $detail = Invoke-TestAction -Verdict 'ARCHIVE' -Site (New-ActionSite -LockState 'Unlock') -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example'

            Get-StubLog | Should -Be @('admin admin@contoso.example', 'archive')
            $detail | Should -BeExactly 'The archive was requested: it takes place later.'
        }

        It 'does not hide a failure of the archive request when the site was not unlocked: the archive was not requested' {
            Set-ActionStub -Fail @{ archive = "The archive of the site '$script:UrlA' could not be requested: Access denied." }

            { Invoke-TestAction -Verdict 'ARCHIVE' } | Should -Throw -ExpectedMessage '*could not be requested*Access denied*'

            Get-StubLog | Should -Be @('archive')
        }

        It 'adds the account without the spaces around it' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly')

            $null = Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account '  admin@contoso.example  '

            Get-StubLog | Should -Contain 'admin admin@contoso.example'
        }

        It 'stops before it changes anything when the administrator is to be added and the account is not known' {
            Set-ActionStub

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account '' } | Should -Throw -ExpectedMessage '*GrantSiteAdmin*account*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'locks the site again, and says so, when the archive fails after the unlock' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly') -Fail @{ archive = "The archive of the site '$script:UrlA' could not be requested: Access denied." }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*could not be requested*Access denied*The site was locked again.'

            Get-StubLog | Should -Be @('lock Unlock', 'read', 'group', 'home site', 'archive', 'read', 'lock ReadOnly', 'read')
        }

        It 'locks the site again when the administrator cannot be added' {
            Set-ActionStub -Read @('Unlock', 'Unlock', 'ReadOnly') -Fail @{ admin = 'The administrator could not be added: Access denied.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true -GrantSiteAdmin $true) -Account 'admin@contoso.example' } | Should -Throw -ExpectedMessage '*could not be added*The site was locked again.'

            @(Get-StubLog | Where-Object { $_ -like 'lock *' }) | Should -Be @('lock Unlock', 'lock ReadOnly')
            @(Get-StubLog | Where-Object { $_ -eq 'archive' }) | Should -HaveCount 0
        }

        It 'says that the archive was requested but the site could not be locked again, as an error, when the lock fails afterwards' {
            Set-ActionStub -Read @('Unlock') -Fail @{ 'lock ReadOnly' = 'The lock state could not be set to ReadOnly: Throttled.' }

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*archive was requested*could not be locked again*Throttled*by hand*'
        }

        It 'says that the archive was requested but the site is not known to be locked, as an error, when it does not report the lock' {
            Set-ActionStub -Read @('Unlock')

            { Invoke-TestAction -Verdict 'ARCHIVE' -Setting (New-ActionSetting -UnlockBeforeArchive $true) } | Should -Throw -ExpectedMessage '*archive was requested*did not report ReadOnly within 2 minutes*lock it by hand*'
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

Describe 'A run that is interrupted while a site is unlocked' {
    BeforeAll {
        $script:Pwsh = (Get-Process -Id $PID).Path

        # Ctrl+C raises a PipelineStoppedException, which a catch does not catch: only a finally runs. This runs the action in a process of its
        # own, where a step throws such an exception (StopAt names it, or the number of the read), or an ordinary error (FailAt), with a site that
        # reports the lock state that was asked for last, and reads what the process did to the lock of the site.
        function script:Invoke-Interrupted {
            param([string]$Verdict, [string]$UnlockBeforeArchive, [string]$StopAt = '', [string]$FailAt = '', [int]$StopAtRead = 0)

            $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $folder -ItemType Directory
            $log = Join-Path -Path $folder -ChildPath 'log.txt'
            $template = @'
$ErrorActionPreference = 'Stop'
$module = Import-Module -Name '@@MANIFEST@@' -Force -PassThru
& $module {
    param($log, $stopAt, $failAt, $stopAtRead, $verdict, $unlockBeforeArchive)
    $script:Log = $log
    $script:StopAt = $stopAt
    $script:FailAt = $failAt
    $script:StopAtRead = $stopAtRead
    $script:Reads = 0
    $script:State = 'ReadOnly'
    function script:Write-Step { param([string]$Text) [System.IO.File]::AppendAllText($script:Log, "$Text`n") }
    function script:Step { param([string]$Name) Write-Step $Name; if ($script:StopAt -eq $Name) { throw [System.Management.Automation.PipelineStoppedException]::new() }; if ($script:FailAt -eq $Name) { throw 'The step failed.' } }
    function script:Set-SPSLifecycleSiteLockState { param($Session, $Url, $State) Step "lock $State"; $script:State = $State }
    function script:Remove-SPSLifecycleSite { param($Session, $Url) Step 'delete' }
    function script:Request-SPSLifecycleSiteArchive { param($Session, $Url) Step 'archive' }
    function script:Get-SPSLifecycleHomeSiteUrl { param($Session) Write-Step 'home site'; '' }
    function script:Get-SPSLifecycleGroupState { param($Session, $GroupId) Write-Step 'group'; 'Active' }
    function script:Start-Sleep { param([double]$Seconds) }
    function script:Get-SPSLifecycleLiveSite {
        param($Session, $Url)
        Write-Step 'read'
        $script:Reads++
        if ($script:StopAtRead -gt 0 -and $script:Reads -eq $script:StopAtRead) { throw [System.Management.Automation.PipelineStoppedException]::new() }
        [PSCustomObject]@{ Url = '@@URL@@'; SiteId = '@@SITEID@@'; Title = 'Sales'; Template = 'GROUP#0'; LockState = $script:State; GroupId = ''; IsHubSite = $false; IsTeamsConnected = $false; IsTeamsChannelConnected = $false; ArchiveStatus = 'NotArchived'; StorageUsedMB = [long]12; LastContentModified = [datetime]'2025-01-05'; HasHolds = $false }
    }
    $site = [PSCustomObject]@{ Url = '@@URL@@'; SiteId = '@@SITEID@@'; Title = 'Sales'; Template = 'GROUP#0'; LockState = 'ReadOnly'; GroupId = ''; IsHubSite = $false; IsTeamsConnected = $false; IsTeamsChannelConnected = $false; ArchiveStatus = 'NotArchived'; StorageUsedMB = [long]12; LastContentModified = [datetime]'2025-01-05'; HasHolds = $false }
    $setting = [PSCustomObject]@{ LockJournal = 'x'; CsvDelimiterChar = ','; DeleteMaxSizeGB = 1.0; Act = [PSCustomObject]@{ UnlockBeforeArchive = ($unlockBeforeArchive -eq 'yes'); GrantSiteAdmin = $false } }
    Invoke-SPSLifecycleSiteAction -Session ([PSCustomObject]@{ Connection = 'c' }) -Setting $setting -Verdict $verdict -Site $site
} '@@LOG@@' '@@STOPAT@@' '@@FAILAT@@' @@STOPATREAD@@ '@@VERDICT@@' '@@UNLOCK@@'
'@
            $text = $template.Replace('@@MANIFEST@@', $script:Manifest).Replace('@@URL@@', $script:UrlA).Replace('@@SITEID@@', $script:SiteA).Replace('@@LOG@@', $log).Replace('@@STOPAT@@', $StopAt).Replace('@@FAILAT@@', $FailAt).Replace('@@STOPATREAD@@', "$StopAtRead").Replace('@@VERDICT@@', $Verdict).Replace('@@UNLOCK@@', $UnlockBeforeArchive)
            $file = Join-Path -Path $folder -ChildPath 'run.ps1'
            [System.IO.File]::WriteAllText($file, $text)
            $null = & $script:Pwsh -NoProfile -File $file 2>&1

            @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log } else { @() })
        }
    }

    It 'puts the lock back, with the same care as after a failure, when the run is interrupted during the deletion' {
        Invoke-Interrupted -Verdict 'DELETE-SITE' -UnlockBeforeArchive 'no' -StopAt 'delete' | Should -Be @('lock Unlock', 'read', 'home site', 'delete', 'read', 'lock ReadOnly', 'read')
    }

    It 'puts the lock back when the run is interrupted during the archive request' {
        Invoke-Interrupted -Verdict 'ARCHIVE' -UnlockBeforeArchive 'yes' -StopAt 'archive' | Should -Be @('lock Unlock', 'read', 'home site', 'archive', 'read', 'lock ReadOnly', 'read')
    }

    It 'puts the lock back when the run is interrupted during the request to unlock: it may have been applied' {
        Invoke-Interrupted -Verdict 'DELETE-SITE' -UnlockBeforeArchive 'no' -StopAt 'lock Unlock' | Should -Be @('lock Unlock', 'read', 'lock ReadOnly', 'read')
    }

    It 'does it again when the run is interrupted while it was putting the lock back after a failure' {
        $steps = Invoke-Interrupted -Verdict 'DELETE-SITE' -UnlockBeforeArchive 'no' -FailAt 'delete' -StopAtRead 2

        $steps | Should -Be @('lock Unlock', 'read', 'home site', 'delete', 'read', 'read', 'lock ReadOnly', 'read')
    }

    It 'does not lock a site that it did not unlock' {
        Invoke-Interrupted -Verdict 'ARCHIVE' -UnlockBeforeArchive 'no' -StopAt 'archive' | Should -Be @('archive')
    }

    It 'does not put the lock back after a deletion that went through, or after a failure that it has already dealt with' {
        Invoke-Interrupted -Verdict 'DELETE-SITE' -UnlockBeforeArchive 'no' | Should -Be @('lock Unlock', 'read', 'home site', 'delete')
        Invoke-Interrupted -Verdict 'DELETE-SITE' -UnlockBeforeArchive 'no' -FailAt 'delete' | Should -Be @('lock Unlock', 'read', 'home site', 'delete', 'read', 'lock ReadOnly', 'read')
    }
}
