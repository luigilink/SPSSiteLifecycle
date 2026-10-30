BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:GeneratedOn = [System.DateTime]::new(2026, 10, 29, 8, 0, 0, [System.DateTimeKind]::Utc)
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'
    $script:UrlA = 'https://contoso.sharepoint.com/sites/a'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    # A site as Get-PnPTenantSite -Detailed gives it (the SPOSite of PnP.PowerShell): its own properties, and the ones that must never leave the adapter.
    function script:New-RawSite {
        param([hashtable]$Override = @{})

        $values = [ordered]@{
            Url                     = $script:UrlA
            SiteId                  = [System.Guid]$script:SiteA
            Title                   = 'Sales'
            Template                = 'GROUP#0'
            LockState               = 'ReadOnly'
            GroupId                 = [System.Guid]$script:GroupA
            IsHubSite               = $false
            IsTeamsConnected        = $true
            IsTeamsChannelConnected = $false
            ArchiveStatus           = 'NotArchived'
            StorageUsageCurrent     = [System.Int64]12
            LastContentModifiedDate = [System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc)
            HasHolds                = $false
            Owner                   = 'owner-login'
            OwnerEmail              = 'owner@contoso.example'
            OwnerName               = 'The Owner'
            OwnerLoginName          = 'i:0#.f|membership|owner@contoso.example'
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Test-SPSLifecycleNotFoundMessage' {
    BeforeAll {
        function script:Test-NotFound {
            param([AllowNull()][AllowEmptyString()][string]$Message)
            & $script:Module { param($m) Test-SPSLifecycleNotFoundMessage -Message $m } $Message
        }
    }

    It 'recognizes a site or a group that does not exist: <Name>' -ForEach @(
        @{ Name = 'a Graph answer that the group is not there'; Message = "Call to Microsoft Graph URL https://graph.microsoft.com/v1.0/directory/deleteditems/microsoft.graph.group/11111111-1111-1111-1111-111111111111 failed with status code NotFound: Resource '11111111-1111-1111-1111-111111111111' does not exist or one of its queried reference-property objects are not present." }
        @{ Name = 'the code of Graph'; Message = 'Request_ResourceNotFound' }
        @{ Name = 'the answer of SharePoint for a site that is not there'; Message = 'Cannot get site https://contoso.sharepoint.com/sites/a.' }
        @{ Name = 'an HTTP 404'; Message = 'The remote server returned an error: (404) Not Found.' }
        @{ Name = 'the same in another case'; Message = 'CANNOT GET SITE https://contoso.sharepoint.com/sites/a.' }
    ) {
        Test-NotFound -Message $Message | Should -BeTrue
    }

    It 'does not take anything else for a site that is not there: <Name>' -ForEach @(
        @{ Name = 'an access denied'; Message = 'Access denied. You do not have permission to perform this action or access this resource.' }
        @{ Name = 'a forbidden answer of Graph'; Message = 'Call to Microsoft Graph URL https://graph.microsoft.com/v1.0/groups failed with status code Forbidden: Insufficient privileges to complete the operation.' }
        @{ Name = 'a throttled call'; Message = 'The remote server returned an error: (429) Too Many Requests.' }
        @{ Name = 'a timeout'; Message = 'The operation has timed out.' }
        @{ Name = 'a parameter that does not exist'; Message = "A parameter cannot be found that matches parameter name 'Foo'." }
        @{ Name = 'a command that is not there'; Message = "The term 'Get-PnPTenantSite' is not recognized as a name of a cmdlet, function, script file, or executable program." }
        @{ Name = 'an empty text'; Message = '' }
        @{ Name = 'nothing'; Message = $null }
        @{ Name = 'a message that merely holds a part of a pattern'; Message = 'The site was found, and does exist in the list, with status code Ok.' }
    ) {
        Test-NotFound -Message $Message | Should -BeFalse
    }
}

Describe 'Get-SPSLifecycleLiveSite' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-PnPTenantSite' = @'
[CmdletBinding()]
param($Identity, [switch]$Detailed, $Connection)
$script:StubLog.Add("Get-PnPTenantSite Identity=$Identity Detailed=$($Detailed.IsPresent) Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
if ($script:StubData.WritesError) { Write-Error 'The server did not answer.'; return }
if ($script:StubData.Sites -is [array]) { $script:StubData.Sites } else { , $script:StubData.Sites }
'@
        } -Data @{ Fails = ''; WritesError = $false; Sites = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Get-TestLiveSite {
            param([string]$Url = $script:UrlA)
            & $script:Module { param($u) Get-SPSLifecycleLiveSite -Session ([PSCustomObject]@{ Connection = 'a connection' }) -Url $u } $Url
        }

        function script:Set-TestSite {
            param($Site)
            & $script:Module { param($s) $script:StubData.Sites = $s } $Site
        }
    }

    It 'asks the tenant for the site by its address, with its details, through the connection of the session' {
        Set-TestSite -Site (New-RawSite)

        $null = Get-TestLiveSite

        Get-StubLog | Should -Be @("Get-PnPTenantSite Identity=$script:UrlA Detailed=True Connection=a connection")
    }

    It 'gives the record of the site, with the twelve names of the listing and whether the site has a hold, and nothing else' {
        Set-TestSite -Site (New-RawSite -Override @{ HasHolds = $true })

        $site = Get-TestLiveSite

        $site.PSObject.Properties.Name | Should -Be @(
            'Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected',
            'ArchiveStatus', 'StorageUsedMB', 'LastContentModified', 'HasHolds')
        $site.Url | Should -BeExactly $script:UrlA
        $site.SiteId | Should -BeExactly $script:SiteA
        $site.GroupId | Should -BeExactly $script:GroupA
        $site.LockState | Should -BeExactly 'ReadOnly'
        $site.StorageUsedMB | Should -Be 12
        $site.LastContentModified | Should -Be ([System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc))
        $site.HasHolds | Should -BeTrue
        ($site | Out-String) | Should -Not -BeLike '*owner*'
    }

    It 'says whether the tenant reports a hold: <Name>' -ForEach @(
        @{ Name = 'a hold'; Value = $true; Expected = $true }
        @{ Name = 'no hold'; Value = $false; Expected = $false }
        @{ Name = 'a text, which is not a flag'; Value = 'True'; Expected = $null }
        @{ Name = 'nothing'; Value = $null; Expected = $null }
    ) {
        Set-TestSite -Site (New-RawSite -Override @{ HasHolds = $Value })

        $site = Get-TestLiveSite

        $site.HasHolds | Should -Be $Expected
        if ($null -eq $Expected) { $null -eq $site.HasHolds | Should -BeTrue }
    }

    It 'says that the site is not there, and does not stop, when the tenant says so: <Name>' -ForEach @(
        @{ Name = 'the answer of SharePoint'; Fails = 'Cannot get site https://contoso.sharepoint.com/sites/a.' }
        @{ Name = 'a 404'; Fails = 'The remote server returned an error: (404) Not Found.' }
    ) {
        & $script:Module { param($f) $script:StubData.Fails = $f } $Fails

        Get-TestLiveSite | Should -BeNullOrEmpty
    }

    It 'says that the site is not there when the cmdlet gives nothing' {
        Set-TestSite -Site @()

        Get-TestLiveSite | Should -BeNullOrEmpty
    }

    It 'stops, and says why, when the site cannot be read: <Name>' -ForEach @(
        @{ Name = 'an access denied'; Fails = 'Access denied.'; Expected = '*could not be read*Access denied*' }
        @{ Name = 'a throttled call'; Fails = 'The remote server returned an error: (429) Too Many Requests.'; Expected = '*could not be read*429*' }
    ) {
        & $script:Module { param($f) $script:StubData.Fails = $f } $Fails

        { Get-TestLiveSite } | Should -Throw -ExpectedMessage $Expected
    }

    It 'stops when the cmdlet reports an error without throwing: a site that was not read is not a site that is not there' {
        & $script:Module { $script:StubData.WritesError = $true }

        { Get-TestLiveSite } | Should -Throw -ExpectedMessage '*could not be read*did not answer*'
    }

    It 'stops when the tenant gives more than one site for one address' {
        Set-TestSite -Site @((New-RawSite), (New-RawSite -Override @{ Url = 'https://contoso.sharepoint.com/sites/b' }))

        { Get-TestLiveSite } | Should -Throw -ExpectedMessage '*more than one site*'
    }

    It 'stops when the site cannot be turned into a record, and names its address' {
        $site = New-RawSite
        $site.PSObject.Properties.Remove('SiteId')
        Set-TestSite -Site $site

        { Get-TestLiveSite } | Should -Throw -ExpectedMessage "*$script:UrlA*SiteId*"
    }
}

Describe 'Get-SPSLifecycleGroupState' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-PnPMicrosoft365Group'        = @'
[CmdletBinding()]
param($Identity, $Connection)
$script:StubLog.Add("Get-PnPMicrosoft365Group Identity=$Identity IsGuid=$($Identity -is [System.Guid]) Connection=$Connection")
if ($script:StubData.ActiveFails) { throw $script:StubData.ActiveFails }
if ($script:StubData.WritesError) { Write-Error 'Insufficient privileges.'; return }
if ($script:StubData.Active -is [array]) { $script:StubData.Active } elseif ($null -ne $script:StubData.Active) { , $script:StubData.Active }
'@
            'Get-PnPDeletedMicrosoft365Group' = @'
[CmdletBinding()]
param($Identity, $Connection)
$script:StubLog.Add("Get-PnPDeletedMicrosoft365Group Identity=$Identity IsGuid=$($Identity -is [System.Guid]) Connection=$Connection")
if ($script:StubData.DeletedFails) { throw $script:StubData.DeletedFails }
if ($script:StubData.Deleted -is [array]) { $script:StubData.Deleted } elseif ($null -ne $script:StubData.Deleted) { , $script:StubData.Deleted }
'@
        } -Data @{ ActiveFails = ''; WritesError = $false; Active = $null; DeletedFails = ''; Deleted = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Get-TestGroupState {
            param([string]$GroupId = $script:GroupA)
            & $script:Module { param($g) Get-SPSLifecycleGroupState -Session ([PSCustomObject]@{ Connection = 'a connection' }) -GroupId $g } $GroupId
        }

        function script:Set-TestGroup {
            param([string]$Name, $Value)
            & $script:Module { param($n, $v) $script:StubData[$n] = $v } $Name $Value
        }
    }

    It 'says None, and asks nobody, for a site that has no group: <Name>' -ForEach @(
        @{ Name = 'an empty ID'; GroupId = '' }
        @{ Name = 'the all-zero ID that the tenant gives to a site without a group'; GroupId = '00000000-0000-0000-0000-000000000000' }
    ) {
        Get-TestGroupState -GroupId $GroupId | Should -BeExactly 'None'

        Get-StubLog | Should -HaveCount 0
    }

    It 'says Active when the group is there, asking for it by its ID as a GUID, and does not look in the recycle bin' {
        Set-TestGroup -Name Active -Value ([PSCustomObject]@{ Id = [System.Guid]$script:GroupA; DisplayName = 'Sales' })

        Get-TestGroupState | Should -BeExactly 'Active'

        Get-StubLog | Should -Be @("Get-PnPMicrosoft365Group Identity=$script:GroupA IsGuid=True Connection=a connection")
    }

    It 'says SoftDeleted when the group is not there but is in the recycle bin' {
        Set-TestGroup -Name Deleted -Value ([PSCustomObject]@{ Id = [System.Guid]$script:GroupA; DisplayName = 'Sales' })

        Get-TestGroupState | Should -BeExactly 'SoftDeleted'

        Get-StubLog | Should -Be @(
            "Get-PnPMicrosoft365Group Identity=$script:GroupA IsGuid=True Connection=a connection"
            "Get-PnPDeletedMicrosoft365Group Identity=$script:GroupA IsGuid=True Connection=a connection"
        )
    }

    It 'says NotFound when the group is in neither: <Name>' -ForEach @(
        @{ Name = 'the recycle bin says nothing'; DeletedFails = ''; }
        @{ Name = 'the recycle bin says that it is not there'; DeletedFails = 'Call to Microsoft Graph URL https://graph.microsoft.com/v1.0/directory/deleteditems/microsoft.graph.group/x failed with status code NotFound: Resource does not exist.' }
    ) {
        Set-TestGroup -Name DeletedFails -Value $DeletedFails

        Get-TestGroupState | Should -BeExactly 'NotFound'
    }

    It 'stops, and says why, when the group cannot be read: <Name>' -ForEach @(
        @{ Name = 'the group call fails'; Name2 = 'ActiveFails'; Message = 'Call to Microsoft Graph URL https://graph.microsoft.com/v1.0/groups failed with status code Forbidden: Insufficient privileges.'; Expected = '*could not be read*Forbidden*' }
        @{ Name = 'the recycle bin call fails'; Name2 = 'DeletedFails'; Message = 'The operation has timed out.'; Expected = '*recycle bin*could not be read*timed out*' }
    ) {
        Set-TestGroup -Name $Name2 -Value $Message

        { Get-TestGroupState } | Should -Throw -ExpectedMessage $Expected
    }

    It 'stops when the group call reports an error without throwing: a group that was not read is not a group that is not there' {
        Set-TestGroup -Name WritesError -Value $true

        { Get-TestGroupState } | Should -Throw -ExpectedMessage '*could not be read*Insufficient privileges*'
    }

    It 'stops when the tenant gives another group than the one that was asked for: <Name>' -ForEach @(
        @{ Name = 'an active one'; Where = 'Active' }
        @{ Name = 'a deleted one'; Where = 'Deleted' }
    ) {
        Set-TestGroup -Name $Where -Value ([PSCustomObject]@{ Id = [System.Guid]'22222222-2222-2222-2222-222222222222'; DisplayName = 'Other' })

        { Get-TestGroupState } | Should -Throw -ExpectedMessage "*another group than the one that was asked for ($script:GroupA)*cannot be told*"
    }

    It 'stops when the tenant gives a group without an ID, or several: <Name>' -ForEach @(
        @{ Name = 'no ID'; Value = [PSCustomObject]@{ DisplayName = 'Sales' }; Expected = '*no usable ID*cannot be told*' }
        @{ Name = 'an ID that is all zeros'; Value = [PSCustomObject]@{ Id = [System.Guid]::Empty }; Expected = '*no usable ID*cannot be told*' }
        @{ Name = 'two groups'; Value = @([PSCustomObject]@{ Id = [System.Guid]'11111111-1111-1111-1111-111111111111' }, [PSCustomObject]@{ Id = [System.Guid]'11111111-1111-1111-1111-111111111111' }); Expected = '*2 groups*cannot be told*' }
    ) {
        Set-TestGroup -Name Active -Value $Value

        { Get-TestGroupState } | Should -Throw -ExpectedMessage $Expected
    }

    It 'accepts the ID of the group as the tenant writes it, in any case' {
        Set-TestGroup -Name Active -Value ([PSCustomObject]@{ Id = 'AAAAAAAA-1111-1111-1111-111111111111' })

        Get-TestGroupState -GroupId 'aaaaaaaa-1111-1111-1111-111111111111' | Should -BeExactly 'Active'
    }
}

Describe 'Get-SPSLifecycleActVerdict' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-SPSLifecycleLiveSite'   = @'
param($Session, $Url)
$script:StubLog.Add("site url=$Url")
if ($script:StubData.SiteFails) { throw $script:StubData.SiteFails }
$script:StubData.Live
'@
            'Get-SPSLifecycleGroupState' = @'
param($Session, $GroupId)
$script:StubLog.Add("group id=$GroupId")
if ($script:StubData.GroupFails) { throw $script:StubData.GroupFails }
$script:StubData.GroupState
'@
        } -Data @{ SiteFails = ''; Live = $null; GroupFails = ''; GroupState = 'Active' }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        # The live record, as Get-SPSLifecycleLiveSite gives it.
        function script:New-LiveRecord {
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
                LastContentModified     = [System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc)
                HasHolds                = $false
            }
            foreach ($key in $Override.Keys) {
                $values[$key] = $Override[$key]
            }

            [PSCustomObject]$values
        }

        # A row of the reviewed report, as Import-SPSLifecycleReviewedReport gives it.
        function script:New-ActRow {
            param([string]$Decision = 'Delete', [string]$Url = $script:UrlA, [string]$SiteId = $script:SiteA)

            [PSCustomObject][ordered]@{
                Line        = 2
                Url         = $Url
                UrlKey      = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $Url
                SiteId      = $SiteId
                Decision    = $Decision
                GeneratedOn = $script:GeneratedOn
            }
        }

        function script:New-ActSetting {
            param([string[]]$Accepted = @('ReadOnly'))

            [PSCustomObject]@{
                TenantName         = 'contoso'
                TenantUrl          = 'https://contoso.sharepoint.com'
                AcceptedLockStates = $Accepted
                MinLockedDays      = 365
                DeleteMaxSizeGB    = 1.0
            }
        }

        function script:New-LockIndex {
            param([object[]]$Entry = @())
            $items = foreach ($e in $Entry) {
                $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $e.Url
                [PSCustomObject]@{ Url = $e.Url; UrlKey = $key; SiteId = $e.SiteId; LockedOn = $e.LockedOn; Source = 'lot1.csv' }
            }

            $import = [PSCustomObject]@{ Name = 'lot1.csv'; RowCount = @($items).Count; Entries = @($items) }
            & $script:Module { param($i) Merge-SPSLifecycleLockDate -Import @($i) } $import
        }

        function script:New-ExclusionIndex {
            param([string[]]$Url = @())
            $keys = @{}
            foreach ($u in $Url) {
                $keys[(& $script:Module { param($x) ConvertTo-SPSLifecycleUrlKey -Url $x } $u)] = 'exclusions.csv'
            }

            [PSCustomObject]@{ Keys = $keys; Imports = @() }
        }

        $script:OldLock = [System.DateTime]::new(2025, 9, 18, 0, 0, 0, [System.DateTimeKind]::Utc)

        function script:Invoke-TestActVerdict {
            param(
                $Row = (New-ActRow),
                $Live = (New-LiveRecord),
                $GroupState = 'Active',
                $Setting = (New-ActSetting),
                $LockIndex = (New-LockIndex -Entry @(@{ Url = $script:UrlA; SiteId = $script:SiteA; LockedOn = $script:OldLock })),
                $ExclusionIndex = (New-ExclusionIndex),
                [string]$HomeSiteUrl = ''
            )

            & $script:Module { param($l, $g) $script:StubData.Live = $l; $script:StubData.GroupState = $g } $Live $GroupState
            $parameters = @{
                Row = $Row; Session = [PSCustomObject]@{ Connection = 'a connection' }; Setting = $Setting; LockDateIndex = $LockIndex
                ExclusionIndex = $ExclusionIndex; HomeSiteUrl = $HomeSiteUrl; Now = $script:Now
            }
            & $script:Module { param($p) Get-SPSLifecycleActVerdict @p } $parameters
        }
    }

    Context 'The verdict of a row, from the live state of the site' {
        It 'gives <Expected> to <Name>' -ForEach @(
            @{ Name = 'a quiet site with an active group, when it is to be deleted'; Case = 'group'; Expected = 'DELETE-VIA-GROUP' }
            @{ Name = 'a site without a group, when it is to be deleted'; Case = 'nogroup'; Expected = 'DELETE-SITE' }
            @{ Name = 'a site whose group ID is all zeros'; Case = 'zerogroup'; Expected = 'DELETE-SITE' }
            @{ Name = 'a site to archive'; Case = 'archive'; Expected = 'ARCHIVE' }
            @{ Name = 'an unlocked site to lock'; Case = 'lock'; Expected = 'LOCK' }
            @{ Name = 'a site that is not there any more'; Case = 'gone'; Expected = 'SKIP-NOT-FOUND' }
            @{ Name = 'an address that now belongs to another site'; Case = 'reused'; Expected = 'SKIP-SITEID-MISMATCH' }
            @{ Name = 'a site whose content changed after the report'; Case = 'modified'; Expected = 'REVIEW-CONTENT-MODIFIED' }
            @{ Name = 'a site whose content changed a second after the report'; Case = 'modified1s'; Expected = 'REVIEW-CONTENT-MODIFIED' }
            @{ Name = 'a site whose content changed at the very second of the report'; Case = 'modifiedsame'; Expected = 'DELETE-VIA-GROUP' }
            @{ Name = 'a site whose content date cannot be read'; Case = 'nodate'; Expected = 'REVIEW-CONTENT-MODIFIED' }
            @{ Name = 'a site that has a hold'; Case = 'hold'; Expected = 'REVIEW-RETENTION' }
            @{ Name = 'a site whose hold is not reported: an unread safeguard is not a green light'; Case = 'holdunknown'; Expected = 'REVIEW-RETENTION' }
            @{ Name = 'a site whose hold is reported as something that is not a flag'; Case = 'holdtext'; Expected = 'REVIEW-RETENTION' }
            @{ Name = 'a site that has no hold'; Case = 'nohold'; Expected = 'DELETE-VIA-GROUP' }
            @{ Name = 'a site that has a hold and was changed: the change is told first'; Case = 'holdmodified'; Expected = 'REVIEW-CONTENT-MODIFIED' }
            @{ Name = 'a site whose group is in the recycle bin'; Case = 'softdeleted'; Expected = 'REVIEW-GROUP-SOFTDELETED' }
            @{ Name = 'a site whose group is not there'; Case = 'groupgone'; Expected = 'REVIEW-GROUP-NOTFOUND' }
            @{ Name = 'a site whose group state is not one that the engine knows'; Case = 'groupodd'; Expected = 'REVIEW-GROUP-NOTFOUND' }
            @{ Name = 'a read-only site when only an unlocked one is accepted'; Case = 'lockstate'; Expected = 'SKIP-LOCK-STATE' }
            @{ Name = 'a site that is locked out'; Case = 'noaccess'; Expected = 'SKIP-LOCK-STATE' }
            @{ Name = 'a site that is in an exclusion list'; Case = 'excluded'; Expected = 'SKIP-EXCLUDED' }
            @{ Name = 'a read-only site with no lock date'; Case = 'nolockdate'; Expected = 'SKIP-NO-LOCK-DATE' }
            @{ Name = 'a site locked 100 days ago'; Case = 'recentlock'; Expected = 'SKIP-TOO-RECENT-LOCK' }
            @{ Name = 'the home site'; Case = 'home'; Expected = 'SKIP-PROTECTED' }
            @{ Name = 'a hub site'; Case = 'hub'; Expected = 'SKIP-PROTECTED' }
            @{ Name = 'a system site'; Case = 'system'; Expected = 'SKIP-PROTECTED' }
            @{ Name = 'a channel site'; Case = 'channel'; Expected = 'SKIP-CHANNEL-SITE' }
            @{ Name = 'an archived site'; Case = 'archived'; Expected = 'SKIP-ALREADY-ARCHIVED' }
            @{ Name = 'a site that cannot be archived'; Case = 'unarchivable'; Expected = 'SKIP-NOT-ARCHIVABLE' }
            @{ Name = 'a site that is too large to delete'; Case = 'large'; Expected = 'SKIP-TOO-LARGE-TO-DELETE' }
            @{ Name = 'a site whose size is unknown, when it is to be deleted'; Case = 'nosize'; Expected = 'REVIEW-NO-SIZE' }
            @{ Name = 'a large site, when it is to be archived'; Case = 'largearchive'; Expected = 'ARCHIVE' }
            @{ Name = 'an excluded site that was changed: the exclusion is told first'; Case = 'excludedmodified'; Expected = 'SKIP-EXCLUDED' }
            @{ Name = 'a protected site that has a hold: the protection is told first'; Case = 'homehold'; Expected = 'SKIP-PROTECTED' }
        ) {
            $parameters = @{}
            switch ($Case) {
                'nogroup' { $parameters.Live = New-LiveRecord -Override @{ GroupId = '' } }
                'zerogroup' { $parameters.Live = New-LiveRecord -Override @{ GroupId = '00000000-0000-0000-0000-000000000000' } }
                'archive' { $parameters.Row = New-ActRow -Decision 'Archive' }
                'lock' {
                    $parameters.Row = New-ActRow -Decision 'Lock'
                    $parameters.Live = New-LiveRecord -Override @{ LockState = 'Unlock' }
                }
                'gone' { $parameters.Live = $null }
                'reused' { $parameters.Live = New-LiveRecord -Override @{ SiteId = $script:SiteB } }
                'modified' { $parameters.Live = New-LiveRecord -Override @{ LastContentModified = $script:GeneratedOn.AddHours(5) } }
                'modified1s' { $parameters.Live = New-LiveRecord -Override @{ LastContentModified = $script:GeneratedOn.AddSeconds(1) } }
                'modifiedsame' { $parameters.Live = New-LiveRecord -Override @{ LastContentModified = $script:GeneratedOn } }
                'nodate' { $parameters.Live = New-LiveRecord -Override @{ LastContentModified = $null } }
                'hold' { $parameters.Live = New-LiveRecord -Override @{ HasHolds = $true } }
                'holdunknown' { $parameters.Live = New-LiveRecord -Override @{ HasHolds = $null } }
                'holdtext' { $parameters.Live = New-LiveRecord -Override @{ HasHolds = 'False' } }
                'nohold' { $parameters.Live = New-LiveRecord -Override @{ HasHolds = $false } }
                'holdmodified' { $parameters.Live = New-LiveRecord -Override @{ HasHolds = $true; LastContentModified = $script:GeneratedOn.AddHours(5) } }
                'softdeleted' { $parameters.GroupState = 'SoftDeleted' }
                'groupgone' { $parameters.GroupState = 'NotFound' }
                'groupodd' { $parameters.GroupState = 'Surprise' }
                'lockstate' { $parameters.Setting = New-ActSetting -Accepted 'Unlock' }
                'noaccess' { $parameters.Live = New-LiveRecord -Override @{ LockState = 'NoAccess' } }
                'excluded' { $parameters.ExclusionIndex = New-ExclusionIndex -Url $script:UrlA }
                'nolockdate' { $parameters.LockIndex = New-LockIndex }
                'recentlock' { $parameters.LockIndex = New-LockIndex -Entry @(@{ Url = $script:UrlA; SiteId = $script:SiteA; LockedOn = $script:Now.AddDays(-100) }) }
                'home' { $parameters.HomeSiteUrl = $script:UrlA }
                'hub' { $parameters.Live = New-LiveRecord -Override @{ IsHubSite = $true } }
                'system' { $parameters.Live = New-LiveRecord -Override @{ Template = 'APPCATALOG#0' } }
                'channel' { $parameters.Live = New-LiveRecord -Override @{ Template = 'TEAMCHANNEL#1' } }
                'archived' { $parameters.Live = New-LiveRecord -Override @{ ArchiveStatus = 'RecentlyArchived' } }
                'unarchivable' {
                    $parameters.Row = New-ActRow -Decision 'Archive'
                    $parameters.Live = New-LiveRecord -Override @{ Template = 'BLANKINTERNET#0' }
                }
                'large' { $parameters.Live = New-LiveRecord -Override @{ StorageUsedMB = [System.Int64]5000 } }
                'nosize' { $parameters.Live = New-LiveRecord -Override @{ StorageUsedMB = $null } }
                'largearchive' {
                    $parameters.Row = New-ActRow -Decision 'Archive'
                    $parameters.Live = New-LiveRecord -Override @{ StorageUsedMB = [System.Int64]5000 }
                }
                'excludedmodified' {
                    $parameters.ExclusionIndex = New-ExclusionIndex -Url $script:UrlA
                    $parameters.Live = New-LiveRecord -Override @{ LastContentModified = $script:GeneratedOn.AddHours(5) }
                }
                'homehold' {
                    $parameters.HomeSiteUrl = $script:UrlA
                    $parameters.Live = New-LiveRecord -Override @{ HasHolds = $true }
                }
            }

            $result = Invoke-TestActVerdict @parameters

            $result.Verdict | Should -BeExactly $Expected
            $result.ReadError | Should -BeExactly ''
        }

        It 'gives the live record, the state of the group and the lock date with the verdict' {
            $live = New-LiveRecord

            $result = Invoke-TestActVerdict -Live $live

            $result.Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
            [object]::ReferenceEquals($result.Site, $live) | Should -BeTrue
            $result.GroupState | Should -BeExactly 'Active'
            $result.LockedOn | Should -Be $script:OldLock
            $result.PSObject.Properties.Name | Should -Be @('Verdict', 'ReadError', 'Site', 'GroupState', 'LockedOn')
        }

        It 'says None for the group of a site that has none, and does not ask for it' {
            $result = Invoke-TestActVerdict -Live (New-LiveRecord -Override @{ GroupId = '' })

            $result.GroupState | Should -BeExactly 'None'
            (Get-StubLog | Where-Object { $_ -like 'group*' }) | Should -HaveCount 0
        }

        It 'gives no live record when the site is not there' {
            $result = Invoke-TestActVerdict -Live $null

            $null -eq $result.Site | Should -BeTrue
            $result.GroupState | Should -BeExactly ''
        }

        It 'does not read what a decision of a person could lift: <Decision>' -ForEach @(
            @{ Decision = 'Delete' }
            @{ Decision = 'Archive' }
            @{ Decision = 'Lock' }
        ) {
            # Whatever the decision, a site that is protected, excluded or too recently locked, or a group that is not active, is never an action.
            foreach ($gate in @(
                    @{ Live = (New-LiveRecord -Override @{ IsHubSite = $true; LockState = 'Unlock' }) }
                    @{ Live = (New-LiveRecord -Override @{ LockState = 'Unlock' }); ExclusionIndex = (New-ExclusionIndex -Url $script:UrlA); Setting = (New-ActSetting -Accepted 'Unlock') }
                    @{ Live = (New-LiveRecord -Override @{ LastContentModified = $script:GeneratedOn.AddHours(1); LockState = 'Unlock' }); Setting = (New-ActSetting -Accepted 'Unlock') }
                    @{ Live = (New-LiveRecord -Override @{ HasHolds = $true; LockState = 'Unlock' }); Setting = (New-ActSetting -Accepted 'Unlock') }
                    @{ Live = (New-LiveRecord -Override @{ LockState = 'Unlock' }); GroupState = 'SoftDeleted'; Setting = (New-ActSetting -Accepted 'Unlock') }
                    @{ Live = (New-LiveRecord -Override @{ LockState = 'Unlock' }); GroupState = ''; Setting = (New-ActSetting -Accepted 'Unlock') }
                )) {
                $result = Invoke-TestActVerdict -Row (New-ActRow -Decision $Decision) @gate

                $result.Verdict | Should -Not -BeIn @('LOCK', 'ARCHIVE', 'DELETE-SITE', 'DELETE-VIA-GROUP')
                $result.Verdict | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'The group is read only when the verdict needs it' {
        It 'reads it, with its ID, when every gate before it is passed' {
            $null = Invoke-TestActVerdict

            Get-StubLog | Should -Be @("site url=$script:UrlA", "group id=$script:GroupA")
        }

        It 'does not read it when a gate before it stops the row: <Name>' -ForEach @(
            @{ Name = 'a lock state that is not accepted'; Case = 'lockstate' }
            @{ Name = 'a hub site'; Case = 'hub' }
            @{ Name = 'an exclusion'; Case = 'excluded' }
            @{ Name = 'a site that is not there'; Case = 'gone' }
        ) {
            $parameters = @{}
            switch ($Case) {
                'lockstate' { $parameters.Setting = New-ActSetting -Accepted 'Unlock' }
                'hub' { $parameters.Live = New-LiveRecord -Override @{ IsHubSite = $true } }
                'excluded' { $parameters.ExclusionIndex = New-ExclusionIndex -Url $script:UrlA }
                'gone' { $parameters.Live = $null }
            }

            $null = Invoke-TestActVerdict @parameters

            (Get-StubLog | Where-Object { $_ -like 'group*' }) | Should -HaveCount 0
        }
    }

    Context 'A read that fails is not a verdict' {
        It 'gives the message and no verdict when the site cannot be read, and reads nothing else' {
            & $script:Module { $script:StubData.SiteFails = "The site 'https://contoso.sharepoint.com/sites/a' could not be read from the tenant: Access denied." }

            $result = Invoke-TestActVerdict

            $result.Verdict | Should -BeExactly ''
            $result.ReadError | Should -BeExactly "The site 'https://contoso.sharepoint.com/sites/a' could not be read from the tenant: Access denied."
            $null -eq $result.Site | Should -BeTrue
            (Get-StubLog | Where-Object { $_ -like 'group*' }) | Should -HaveCount 0
        }

        It 'gives the message and no verdict when the group cannot be read, with the site that was read' {
            $live = New-LiveRecord
            & $script:Module { $script:StubData.GroupFails = 'The Microsoft 365 group could not be read: Forbidden.' }

            $result = Invoke-TestActVerdict -Live $live

            $result.Verdict | Should -BeExactly ''
            $result.ReadError | Should -BeExactly 'The Microsoft 365 group could not be read: Forbidden.'
            [object]::ReferenceEquals($result.Site, $live) | Should -BeTrue
            $result.GroupState | Should -BeExactly ''
        }

        It 'does not turn a read that failed into a site that is not there: a throw is an error, a null is a site that is not there' {
            & $script:Module { $script:StubData.SiteFails = 'Cannot get site https://contoso.sharepoint.com/sites/a.' }

            $result = Invoke-TestActVerdict

            $result.Verdict | Should -BeExactly ''
            $result.ReadError | Should -Not -BeNullOrEmpty
        }

        It 'gives an error and no verdict when the tenant answers with the site of another address: <Name>' -ForEach @(
            @{ Name = 'another site'; Url = 'https://contoso.sharepoint.com/sites/other' }
            @{ Name = 'no address'; Url = '' }
        ) {
            $result = Invoke-TestActVerdict -Live (New-LiveRecord -Override @{ Url = $Url })

            $result.Verdict | Should -BeExactly ''
            $result.ReadError | Should -BeLike '*another address*'
        }

        It 'accepts the same address spelled another way' {
            $result = Invoke-TestActVerdict -Live (New-LiveRecord -Override @{ Url = 'HTTPS://Contoso.SharePoint.com/Sites/A/' })

            $result.Verdict | Should -BeExactly 'DELETE-VIA-GROUP'
        }

        It 'gives an error and no verdict when the group ID of the site is not a GUID: a site that is taken for one without a group would be deleted as a site' {
            $result = Invoke-TestActVerdict -Live (New-LiveRecord -Override @{ GroupId = 'not-a-guid' })

            $result.Verdict | Should -BeExactly ''
            $result.ReadError | Should -BeLike '*group ID*not a GUID*'
            (Get-StubLog | Where-Object { $_ -like 'group*' }) | Should -HaveCount 0
        }

        It 'stops when the decision is not one that the tool knows, and does not read anything: <Decision>' -ForEach @(
            @{ Decision = 'Remove' }
            @{ Decision = 'delete' }
            @{ Decision = 'DELETE' }
            @{ Decision = "Dele$([char]0x200B)te" }
        ) {
            { Invoke-TestActVerdict -Row (New-ActRow -Decision $Decision) } | Should -Throw -ExpectedMessage '*Decision*(line 2) is not Delete, Archive or Lock*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops when the row has no decision, no site ID, no address or no date: <Name>' -ForEach @(
            @{ Name = 'no decision'; Field = 'Decision'; Value = ''; Message = "Decision '' (line 2) is not Delete, Archive or Lock*" }
            @{ Name = 'no site ID'; Field = 'SiteId'; Value = ''; Message = 'The row at line 2 has no usable SiteId*' }
            @{ Name = 'a site ID that is all zeros'; Field = 'SiteId'; Value = '00000000-0000-0000-0000-000000000000'; Message = 'The row at line 2 has no usable SiteId*' }
            @{ Name = 'no address'; Field = 'Url'; Value = ''; Message = 'The row at line 2 has no Url.' }
            @{ Name = 'a blank address'; Field = 'Url'; Value = '   '; Message = 'The row at line 2 has no Url.' }
            @{ Name = 'no date'; Field = 'GeneratedOn'; Value = $null; Message = 'The row at line 2 has no GeneratedOn*' }
        ) {
            $row = New-ActRow
            $row.$Field = $Value

            { Invoke-TestActVerdict -Row $row } | Should -Throw -ExpectedMessage $Message

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'It reads and never writes' {
        It 'asks the adapters that read, once each, and nothing else' {
            $null = Invoke-TestActVerdict

            Get-StubLog | Should -Be @("site url=$script:UrlA", "group id=$script:GroupA")
        }
    }
}
