BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:UrlA = 'https://contoso.sharepoint.com/sites/a'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-WriteSession {
        param([hashtable]$Override = @{})

        $values = [ordered]@{
            Connection     = 'a connection'
            TenantName     = 'contoso'
            AdminUrl       = 'https://contoso-admin.sharepoint.com'
            RefusedTenants = @()
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

Describe 'Assert-SPSLifecycleWriteTarget' {
    BeforeAll {
        function script:Assert-Target {
            param($Session = (New-WriteSession), [string]$Url, [string]$GroupId)

            if ($PSBoundParameters.ContainsKey('GroupId')) {
                & $script:Module { param($s, $g) Assert-SPSLifecycleWriteTarget -Session $s -GroupId $g } $Session $GroupId
            }
            else {
                & $script:Module { param($s, $u) Assert-SPSLifecycleWriteTarget -Session $s -Url $u } $Session $Url
            }
        }
    }

    It 'accepts the address of a site of the tenant of the session: <Url>' -ForEach @(
        @{ Url = 'https://contoso.sharepoint.com/sites/a' }
        @{ Url = 'https://contoso.sharepoint.com/teams/a' }
        @{ Url = 'HTTPS://Contoso.SharePoint.com/Sites/A/' }
        @{ Url = 'https://contoso.sharepoint.com:443/sites/a' }
        @{ Url = 'https://contoso.sharepoint.com/sites/some-team%20site' }
        @{ Url = 'https://contoso.sharepoint.com/sites/%C3%A9quipe' }
        @{ Url = 'https://contoso.sharepoint.com/sites/a.b' }
        @{ Url = 'https://contoso.sharepoint.com/sites/a/b' }
    ) {
        { Assert-Target -Url $Url } | Should -Not -Throw
    }

    It 'refuses an address that is not one that the tool acts on: <Name>' -ForEach @(
        @{ Name = 'another tenant'; Url = 'https://fabrikam.sharepoint.com/sites/a'; Expected = '*another tenant*' }
        @{ Name = 'a OneDrive host'; Url = 'https://contoso-my.sharepoint.com/personal/someone_contoso_com'; Expected = '*another tenant*' }
        @{ Name = 'the admin site'; Url = 'https://contoso-admin.sharepoint.com/sites/a'; Expected = '*another tenant*' }
        @{ Name = 'the root site'; Url = 'https://contoso.sharepoint.com'; Expected = '*root*' }
        @{ Name = 'the root site with a slash'; Url = 'https://contoso.sharepoint.com/'; Expected = '*root*' }
        @{ Name = 'the root site, as an encoded slash'; Url = 'https://contoso.sharepoint.com/%2f'; Expected = '*encoded*' }
        @{ Name = 'the root site, as an encoded slash in capitals'; Url = 'https://contoso.sharepoint.com/%2F'; Expected = '*encoded*' }
        @{ Name = 'an encoded backslash'; Url = 'https://contoso.sharepoint.com/sites%5ca'; Expected = '*encoded*' }
        @{ Name = 'an encoded slash inside a name'; Url = 'https://contoso.sharepoint.com/sites/a%2fb'; Expected = '*encoded*' }
        @{ Name = 'a double encoding'; Url = 'https://contoso.sharepoint.com/%252f'; Expected = '*encoded*' }
        @{ Name = 'a backslash instead of the first slash'; Url = 'https://contoso.sharepoint.com\sites\a'; Expected = '*not the web address*' }
        @{ Name = 'a backslash in the path'; Url = 'https://contoso.sharepoint.com/sites\a'; Expected = '*backslash*' }
        @{ Name = 'a dot segment that leads to the root'; Url = 'https://contoso.sharepoint.com/sites/..'; Expected = '*dot segment*' }
        @{ Name = 'a dot segment inside'; Url = 'https://contoso.sharepoint.com/sites/./a'; Expected = '*dot segment*' }
        @{ Name = 'a dot segment that leaves the site'; Url = 'https://contoso.sharepoint.com/sites/a/../../b'; Expected = '*dot segment*' }
        @{ Name = 'an encoded dot segment'; Url = 'https://contoso.sharepoint.com/sites/%2e%2e/a'; Expected = '*dot segment*' }
        @{ Name = 'two slashes in a row'; Url = 'https://contoso.sharepoint.com/sites//a'; Expected = '*two slashes*' }
        @{ Name = 'two slashes at the start'; Url = 'https://contoso.sharepoint.com//sites/a'; Expected = '*two slashes*' }
        @{ Name = 'http'; Url = 'http://contoso.sharepoint.com/sites/a'; Expected = '*https*' }
        @{ Name = 'a port'; Url = 'https://contoso.sharepoint.com:8443/sites/a'; Expected = '*port*' }
        @{ Name = 'user information'; Url = 'https://user@contoso.sharepoint.com/sites/a'; Expected = '*user information*' }
        @{ Name = 'a query'; Url = 'https://contoso.sharepoint.com/sites/a?x=1'; Expected = '*query*' }
        @{ Name = 'a fragment'; Url = 'https://contoso.sharepoint.com/sites/a#top'; Expected = '*fragment*' }
        @{ Name = 'the dot of the DNS root'; Url = 'https://contoso.sharepoint.com./sites/a'; Expected = '*another tenant*' }
        @{ Name = 'a host with a letter that looks like another'; Url = "https://cont$([char]0x043E)so.sharepoint.com/sites/a"; Expected = '*another tenant*' }
        @{ Name = 'a space'; Url = 'https://contoso.sharepoint.com/sites/a b'; Expected = '*not the web address*' }
        @{ Name = 'a hidden character'; Url = "https://contoso.sharepoint.com/sites/a$([char]0x200B)"; Expected = '*not the web address*' }
        @{ Name = 'a path'; Url = '/sites/a'; Expected = '*not the web address*' }
        @{ Name = 'a text'; Url = 'sales'; Expected = '*not the web address*' }
        @{ Name = 'an empty text'; Url = ''; Expected = '*not the web address*' }
    ) {
        { Assert-Target -Url $Url } | Should -Throw -ExpectedMessage $Expected
    }

    It 'names the address that it refuses, with the hidden characters written out' {
        { Assert-Target -Url "https://contoso.sharepoint.com/sites/a$([char]0x200B)" } | Should -Throw -ExpectedMessage '*sites/a\u200B*'
        { Assert-Target -Url 'https://fabrikam.sharepoint.com/sites/a' } | Should -Throw -ExpectedMessage "*'https://fabrikam.sharepoint.com/sites/a'*"
        { Assert-Target -Url 'https://contoso.sharepoint.com/sites/a?x=1' } | Should -Throw -ExpectedMessage "*'https://contoso.sharepoint.com/sites/a?x=1'*"
    }

    It 'refuses every address when the tenant of the session is refused or is not a tenant: <Name>' -ForEach @(
        @{ Name = 'a Microsoft tenant'; Override = @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' }; Url = 'https://microsoft.sharepoint.com/sites/a' }
        @{ Name = 'a tenant of the settings'; Override = @{ RefusedTenants = @('contoso') }; Url = 'https://contoso.sharepoint.com/sites/a' }
        @{ Name = 'a tenant that is not a name'; Override = @{ TenantName = 'con toso'; AdminUrl = 'https://con toso-admin.sharepoint.com' }; Url = 'https://contoso.sharepoint.com/sites/a' }
        @{ Name = 'no tenant'; Override = @{ TenantName = '' }; Url = 'https://contoso.sharepoint.com/sites/a' }
        @{ Name = 'an admin address for another tenant'; Override = @{ AdminUrl = 'https://fabrikam-admin.sharepoint.com' }; Url = 'https://contoso.sharepoint.com/sites/a' }
    ) {
        { Assert-Target -Session (New-WriteSession -Override $Override) -Url $Url } | Should -Throw
    }

    It 'refuses a session that is not one' {
        { Assert-Target -Session ([PSCustomObject]@{ Connection = 'a connection' }) -Url $script:UrlA } | Should -Throw
    }

    It 'accepts the ID of a group: <GroupId>' -ForEach @(
        @{ GroupId = '11111111-1111-1111-1111-111111111111' }
        @{ GroupId = 'AAAAAAAA-1111-1111-1111-111111111111' }
    ) {
        { Assert-Target -GroupId $GroupId } | Should -Not -Throw
    }

    It 'refuses what is not the ID of a group: <Name>' -ForEach @(
        @{ Name = 'an empty text'; GroupId = '' }
        @{ Name = 'all zeros'; GroupId = '00000000-0000-0000-0000-000000000000' }
        @{ Name = 'a name'; GroupId = 'Sales' }
        @{ Name = 'a GUID with a space'; GroupId = ' 11111111-1111-1111-1111-111111111111' }
        @{ Name = 'a GUID with braces'; GroupId = '{11111111-1111-1111-1111-111111111111}' }
        @{ Name = 'a GUID with a hidden character'; GroupId = "11111111-1111-1111-1111-11111111111$([char]0x200B)1" }
    ) {
        { Assert-Target -GroupId $GroupId } | Should -Throw -ExpectedMessage '*group*not a GUID*'
    }

    It 'refuses the ID of a group too when the tenant of the session is refused' {
        { Assert-Target -Session (New-WriteSession -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' }) -GroupId $script:GroupA } | Should -Throw -ExpectedMessage '*refused*'
    }
}

Describe 'The adapters that change the tenant' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Set-PnPTenantSite'            = @'
[CmdletBinding()]
param($Identity, $LockState, $Owners, $Connection)
$script:StubLog.Add("Set-PnPTenantSite Identity=$Identity LockState=$LockState Owners=$(@($Owners) -join ',') OwnersType=$(if ($null -ne $Owners) { $Owners.GetType().Name }) Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
if ($script:StubData.WritesError) { Write-Error 'Access denied.'; return }
'@
            'Remove-PnPTenantSite'         = @'
[CmdletBinding()]
param($Url, [switch]$Force, [switch]$SkipRecycleBin, $Connection)
$script:StubLog.Add("Remove-PnPTenantSite Url=$Url Force=$($Force.IsPresent) SkipRecycleBin=$($SkipRecycleBin.IsPresent) Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
if ($script:StubData.WritesError) { Write-Error 'Access denied.'; return }
'@
            'Remove-PnPMicrosoft365Group'  = @'
[CmdletBinding()]
param($Identity, $Connection)
$script:StubLog.Add("Remove-PnPMicrosoft365Group Identity=$Identity IsGuid=$($Identity -is [System.Guid]) Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
if ($script:StubData.WritesError) { Write-Error 'Access denied.'; return }
'@
            'Set-PnPSiteArchiveState'      = @'
[CmdletBinding()]
param($Identity, $ArchiveState, [switch]$NoWait, [switch]$Force, $Connection)
$script:StubLog.Add("Set-PnPSiteArchiveState Identity=$Identity ArchiveState=$ArchiveState NoWait=$($NoWait.IsPresent) Force=$($Force.IsPresent) Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
if ($script:StubData.WritesError) { Write-Error 'Access denied.'; return }
'@
        } -Data @{ Fails = ''; WritesError = $false }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Invoke-Writer {
            param([string]$Name, [hashtable]$Parameter, $Session = (New-WriteSession))

            & $script:Module { param($n, $s, $p) & $n -Session $s @p } $Name $Session $Parameter
        }
    }

    Context 'Set-SPSLifecycleSiteLockState' {
        It 'sets the lock state of the site, through the connection of the session: <State>' -ForEach @(
            @{ State = 'Unlock' }
            @{ State = 'ReadOnly' }
        ) {
            Invoke-Writer -Name Set-SPSLifecycleSiteLockState -Parameter @{ Url = $script:UrlA; State = $State }

            Get-StubLog | Should -Be @("Set-PnPTenantSite Identity=$script:UrlA LockState=$State Owners= OwnersType= Connection=a connection")
        }

        It 'never sets NoAccess, and no other word' {
            { Invoke-Writer -Name Set-SPSLifecycleSiteLockState -Parameter @{ Url = $script:UrlA; State = 'NoAccess' } } | Should -Throw

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'Remove-SPSLifecycleSite' {
        It 'deletes the site into the recycle bin: it never skips it' {
            Invoke-Writer -Name Remove-SPSLifecycleSite -Parameter @{ Url = $script:UrlA }

            Get-StubLog | Should -Be @("Remove-PnPTenantSite Url=$script:UrlA Force=True SkipRecycleBin=False Connection=a connection")
        }
    }

    Context 'Remove-SPSLifecycleGroup' {
        It 'deletes the group by its ID as a GUID' {
            Invoke-Writer -Name Remove-SPSLifecycleGroup -Parameter @{ GroupId = $script:GroupA }

            Get-StubLog | Should -Be @("Remove-PnPMicrosoft365Group Identity=$script:GroupA IsGuid=True Connection=a connection")
        }
    }

    Context 'Request-SPSLifecycleSiteArchive' {
        It 'asks for the archive without waiting for it' {
            Invoke-Writer -Name Request-SPSLifecycleSiteArchive -Parameter @{ Url = $script:UrlA }

            Get-StubLog | Should -Be @("Set-PnPSiteArchiveState Identity=$script:UrlA ArchiveState=Archived NoWait=True Force=True Connection=a connection")
        }
    }

    Context 'Add-SPSLifecycleSiteAdmin' {
        It 'adds the account to the administrators of the site collection, as a list' {
            Invoke-Writer -Name Add-SPSLifecycleSiteAdmin -Parameter @{ Url = $script:UrlA; Account = 'admin@contoso.example' }

            Get-StubLog | Should -Be @("Set-PnPTenantSite Identity=$script:UrlA LockState= Owners=admin@contoso.example OwnersType=List``1 Connection=a connection")
        }

        It 'refuses what is not the address of an account: <Account>' -ForEach @(
            @{ Account = '' }
            @{ Account = 'admin' }
            @{ Account = 'admin@contoso.example, other@contoso.example' }
            @{ Account = 'admin @contoso.example' }
            @{ Account = "admin@contoso.example$([char]0x200B)" }
        ) {
            { Invoke-Writer -Name Add-SPSLifecycleSiteAdmin -Parameter @{ Url = $script:UrlA; Account = $Account } } | Should -Throw -ExpectedMessage '*account*'

            Get-StubLog | Should -HaveCount 0
        }
    }

    Context 'Whichever the adapter' {
        It 'stops before it calls the tenant when the target is not one: <Name>' -ForEach @(
            @{ Name = 'a lock'; Adapter = 'Set-SPSLifecycleSiteLockState'; Parameter = @{ Url = 'https://fabrikam.sharepoint.com/sites/a'; State = 'Unlock' } }
            @{ Name = 'a deletion'; Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso.sharepoint.com' } }
            @{ Name = 'a deletion of a OneDrive'; Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso-my.sharepoint.com/personal/someone_contoso_com' } }
            @{ Name = 'an archive'; Adapter = 'Request-SPSLifecycleSiteArchive'; Parameter = @{ Url = 'http://contoso.sharepoint.com/sites/a' } }
            @{ Name = 'a change of administrators'; Adapter = 'Add-SPSLifecycleSiteAdmin'; Parameter = @{ Url = 'https://contoso.sharepoint.com/'; Account = 'admin@contoso.example' } }
            @{ Name = 'a deletion of a group'; Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '00000000-0000-0000-0000-000000000000' } }
        ) {
            { Invoke-Writer -Name $Adapter -Parameter $Parameter } | Should -Throw

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before it calls the tenant when the tenant of the session is refused: <Adapter>' -ForEach @(
            @{ Adapter = 'Set-SPSLifecycleSiteLockState'; Parameter = @{ Url = 'https://microsoft.sharepoint.com/sites/a'; State = 'Unlock' } }
            @{ Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://microsoft.sharepoint.com/sites/a' } }
            @{ Adapter = 'Request-SPSLifecycleSiteArchive'; Parameter = @{ Url = 'https://microsoft.sharepoint.com/sites/a' } }
            @{ Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '11111111-1111-1111-1111-111111111111' } }
        ) {
            $session = New-WriteSession -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' }

            { Invoke-Writer -Name $Adapter -Parameter $Parameter -Session $session } | Should -Throw -ExpectedMessage '*refused*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'says what could not be done, and why, when the tenant refuses: <Adapter>' -ForEach @(
            @{ Adapter = 'Set-SPSLifecycleSiteLockState'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; State = 'Unlock' }; Expected = "*lock state*https://contoso.sharepoint.com/sites/a*could not be set to Unlock*Access denied*" }
            @{ Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' }; Expected = "*site*https://contoso.sharepoint.com/sites/a*could not be deleted*Access denied*" }
            @{ Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '11111111-1111-1111-1111-111111111111' }; Expected = '*group 11111111-1111-1111-1111-111111111111*could not be deleted*Access denied*' }
            @{ Adapter = 'Request-SPSLifecycleSiteArchive'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' }; Expected = "*archive*https://contoso.sharepoint.com/sites/a*could not be requested*Access denied*" }
            @{ Adapter = 'Add-SPSLifecycleSiteAdmin'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; Account = 'admin@contoso.example' }; Expected = "*administrator*https://contoso.sharepoint.com/sites/a*could not be added*Access denied*" }
        ) {
            & $script:Module { $script:StubData.Fails = 'Access denied.' }

            { Invoke-Writer -Name $Adapter -Parameter $Parameter } | Should -Throw -ExpectedMessage $Expected
        }

        It 'changes nothing when it is run with -WhatIf, whatever the adapter: <Adapter>' -ForEach @(
            @{ Adapter = 'Set-SPSLifecycleSiteLockState'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; State = 'Unlock' } }
            @{ Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' } }
            @{ Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '11111111-1111-1111-1111-111111111111' } }
            @{ Adapter = 'Request-SPSLifecycleSiteArchive'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' } }
            @{ Adapter = 'Add-SPSLifecycleSiteAdmin'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; Account = 'admin@contoso.example' } }
        ) {
            Invoke-Writer -Name $Adapter -Parameter ($Parameter + @{ WhatIf = $true })

            Get-StubLog | Should -HaveCount 0
        }

        It 'still checks its target when it is run with -WhatIf: <Adapter>' -ForEach @(
            @{ Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso.sharepoint.com' } }
            @{ Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '00000000-0000-0000-0000-000000000000' } }
        ) {
            { Invoke-Writer -Name $Adapter -Parameter ($Parameter + @{ WhatIf = $true }) } | Should -Throw
        }

        It 'stops when the cmdlet reports an error without throwing: <Adapter>' -ForEach @(
            @{ Adapter = 'Set-SPSLifecycleSiteLockState'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; State = 'Unlock' } }
            @{ Adapter = 'Remove-SPSLifecycleSite'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' } }
            @{ Adapter = 'Remove-SPSLifecycleGroup'; Parameter = @{ GroupId = '11111111-1111-1111-1111-111111111111' } }
            @{ Adapter = 'Request-SPSLifecycleSiteArchive'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a' } }
            @{ Adapter = 'Add-SPSLifecycleSiteAdmin'; Parameter = @{ Url = 'https://contoso.sharepoint.com/sites/a'; Account = 'admin@contoso.example' } }
        ) {
            & $script:Module { $script:StubData.WritesError = $true }

            { Invoke-Writer -Name $Adapter -Parameter $Parameter } | Should -Throw -ExpectedMessage '*Access denied*'
        }
    }
}

Describe 'Get-SPSLifecycleArchiveEnabled' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-PnPTenant' = @'
[CmdletBinding()]
param($Connection)
$script:StubLog.Add("Get-PnPTenant Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
$script:StubData.Tenant
'@
        } -Data @{ Fails = ''; Tenant = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Get-TestArchiveEnabled {
            & $script:Module { Get-SPSLifecycleArchiveEnabled -Session ([PSCustomObject]@{ Connection = 'a connection' }) }
        }
    }

    It 'says whether Microsoft 365 Archive is on for sites: <Name>' -ForEach @(
        @{ Name = 'on'; Tenant = [PSCustomObject]@{ EnableSiteArchive = $true }; Expected = $true }
        @{ Name = 'off'; Tenant = [PSCustomObject]@{ EnableSiteArchive = $false }; Expected = $false }
        @{ Name = 'not said: the tenant has no such property'; Tenant = [PSCustomObject]@{ Other = 1 }; Expected = $null }
        @{ Name = 'not said: a text'; Tenant = [PSCustomObject]@{ EnableSiteArchive = 'True' }; Expected = $null }
        @{ Name = 'not said: nothing'; Tenant = $null; Expected = $null }
    ) {
        & $script:Module { param($t) $script:StubData.Tenant = $t } $Tenant

        $answer = Get-TestArchiveEnabled

        if ($null -eq $Expected) { $null -eq $answer | Should -BeTrue } else { $answer | Should -Be $Expected }
        Get-StubLog | Should -Be @('Get-PnPTenant Connection=a connection')
    }

    It 'stops, and says why, when the tenant cannot be read' {
        & $script:Module { $script:StubData.Fails = 'Access denied.' }

        { Get-TestArchiveEnabled } | Should -Throw -ExpectedMessage '*Microsoft 365 Archive*could not be read*Access denied*'
    }
}

Describe 'Get-SPSLifecycleSignedInAccount' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-PnPAccessToken' = @'
[CmdletBinding()]
param([switch]$Decoded, $ResourceTypeName, $Connection)
$script:StubLog.Add("Get-PnPAccessToken Decoded=$($Decoded.IsPresent) ResourceTypeName=$ResourceTypeName Connection=$Connection")
if ($script:StubData.Fails) { throw $script:StubData.Fails }
$script:StubData.Token
'@
        } -Data @{ Fails = ''; Token = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:New-TestToken {
            param([hashtable]$Claim)
            $claims = foreach ($key in $Claim.Keys) { [PSCustomObject]@{ Type = $key; Value = $Claim[$key] } }
            [PSCustomObject]@{ Claims = @($claims) }
        }

        function script:Get-TestAccount {
            & $script:Module { Get-SPSLifecycleSignedInAccount -Session ([PSCustomObject]@{ Connection = 'a connection' }) }
        }
    }

    It 'gives the account that signed in, from its claim, asking for the decoded token of SharePoint' {
        & $script:Module { param($t) $script:StubData.Token = $t } (New-TestToken -Claim @{ upn = 'admin@contoso.example'; name = 'The Admin' })

        Get-TestAccount | Should -BeExactly 'admin@contoso.example'

        Get-StubLog | Should -Be @('Get-PnPAccessToken Decoded=True ResourceTypeName=SharePoint Connection=a connection')
    }

    It 'reads the claims in order, and takes the first that is an address: <Name>' -ForEach @(
        @{ Name = 'upn first'; Claim = [ordered]@{ upn = 'one@contoso.example'; unique_name = 'two@contoso.example' }; Expected = 'one@contoso.example' }
        @{ Name = 'unique_name when there is no upn'; Claim = [ordered]@{ unique_name = 'two@contoso.example'; preferred_username = 'three@contoso.example' }; Expected = 'two@contoso.example' }
        @{ Name = 'preferred_username when the others are not addresses'; Claim = [ordered]@{ upn = 'not an address'; unique_name = 'x'; preferred_username = 'three@contoso.example' }; Expected = 'three@contoso.example' }
        @{ Name = 'email as the last one'; Claim = [ordered]@{ email = 'four@contoso.example' }; Expected = 'four@contoso.example' }
    ) {
        & $script:Module { param($t) $script:StubData.Token = $t } (New-TestToken -Claim $Claim)

        Get-TestAccount | Should -BeExactly $Expected
    }

    It 'stops when the token holds no claim that is an address, and says so' {
        & $script:Module { param($t) $script:StubData.Token = $t } (New-TestToken -Claim @{ name = 'The Admin'; oid = '11111111-1111-1111-1111-111111111111' })

        { Get-TestAccount } | Should -Throw -ExpectedMessage '*account*cannot be told*'
    }

    It 'stops, and says why, when the token cannot be read' {
        & $script:Module { $script:StubData.Fails = 'The connection has no token.' }

        { Get-TestAccount } | Should -Throw -ExpectedMessage '*account*could not be read*no token*'
    }

    It 'stops when the cmdlet gives no token' {
        { Get-TestAccount } | Should -Throw -ExpectedMessage '*account*cannot be told*'
    }
}
