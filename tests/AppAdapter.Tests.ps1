BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)
    $script:ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'
    $script:Thumbprint = '0123456789abcdef0123456789abcdef01234567'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-AppPlan {
        param([string]$Kind = 'Interactive', [string]$TenantName = 'contoso', [string]$ApplicationName = 'SPSSiteLifecycle', [switch]$DeviceLogin)

        $parameters = @{ TenantName = $TenantName; ApplicationName = $ApplicationName; Kind = $Kind; Now = $script:Now; DeviceLogin = $DeviceLogin.IsPresent }
        if ($Kind -eq 'Certificate') { $parameters['Folder'] = '/keys/spslc'; $parameters['ValidYears'] = 3 }
        & $script:Module { param($p) Get-SPSLifecycleAppPlan @p } $parameters
    }

    # The record that PnP.PowerShell gives: property names with a slash and a space, and the whole certificate with its private key.
    function script:New-PnPRecord {
        param([hashtable]$Override = @{})

        $values = [ordered]@{ 'AzureAppId/ClientId' = $script:ClientId; 'Certificate Thumbprint' = $script:Thumbprint; Base64Encoded = 'THE-WHOLE-PFX-WITH-ITS-PRIVATE-KEY'; 'Pfx file' = '/keys/spslc/SPSSiteLifecycle.pfx'; 'Cer file' = '/keys/spslc/SPSSiteLifecycle.cer' }
        foreach ($key in $Override.Keys) { $values[$key] = $Override[$key] }
        [PSCustomObject]$values
    }

    function script:Set-PnPStub {
        param([object[]]$Output = @(), [string]$Throw = '', [bool]$PnPMissing = $false)

        $body = @'
[CmdletBinding()]
param($ApplicationName, $Tenant, $OutPath, $ValidYears, $CertificatePassword, $GraphApplicationPermissions, $SharePointApplicationPermissions, $GraphDelegatePermissions, $SharePointDelegatePermissions, [switch]$DeviceLogin, $Store)
$script:StubLog.Add('@@NAME@@')
$script:StubData.Bound = [ordered]@{} + $PSBoundParameters
if ($script:StubData.Throw) { throw $script:StubData.Throw }
foreach ($item in $script:StubData.Output) { $item }
'@
        Set-ModuleStub -Stub @{
            'Register-PnPEntraIDApp'                    = $body.Replace('@@NAME@@', 'Register-PnPEntraIDApp')
            'Register-PnPEntraIDAppForInteractiveLogin' = $body.Replace('@@NAME@@', 'Register-PnPEntraIDAppForInteractiveLogin')
            'Assert-SPSLifecyclePnPModule'              = @'
$script:StubLog.Add('pnp check')
if ($script:StubData.PnPMissing) { throw 'PnP.PowerShell is not installed.' }
'@
        } -Data @{ Output = $Output; Throw = $Throw; PnPMissing = $PnPMissing; Bound = $null }
    }

    function script:Invoke-Adapter {
        param($Plan, $Password = $null, [switch]$WhatIf)

        & $script:Module { param($p, $s, $w) Register-SPSLifecycleEntraApp -Plan $p -CertificatePassword $s -WhatIf:$w } $Plan $Password $WhatIf.IsPresent
    }

    function script:Get-Bound {
        & $script:Module { $script:StubData.Bound }
    }

    function script:ConvertTo-Secure {
        param([string]$Text)

        $secure = [System.Security.SecureString]::new()
        foreach ($character in $Text.ToCharArray()) { $secure.AppendChar($character) }
        $secure
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Register-SPSLifecycleEntraApp' {
    AfterEach {
        Clear-ModuleStub
    }

    Context 'An app that signs in alone, with a certificate' {
        It 'gives the cmdlet the tenant, the name, the application permissions, the folder, the years and the password, and nothing else' {
            Set-PnPStub -Output @('App created.', (New-PnPRecord))
            $password = ConvertTo-Secure -Text 'Correct-Horse-1'

            $null = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password $password

            Get-StubLog | Should -Be @('pnp check', 'Register-PnPEntraIDApp')
            $bound = Get-Bound
            @($bound.Keys | Sort-Object) | Should -Be @('ApplicationName', 'CertificatePassword', 'ErrorAction', 'GraphApplicationPermissions', 'OutPath', 'SharePointApplicationPermissions', 'Tenant', 'ValidYears')
            $bound.ApplicationName | Should -BeExactly 'SPSSiteLifecycle'
            $bound.Tenant | Should -BeExactly 'contoso.onmicrosoft.com'
            $bound.OutPath | Should -BeExactly '/keys/spslc'
            $bound.ValidYears | Should -Be 3
            $bound.CertificatePassword | Should -Be $password
            @($bound.GraphApplicationPermissions) | Should -Be @('Group.ReadWrite.All')
            @($bound.SharePointApplicationPermissions) | Should -Be @('Sites.FullControl.All')
            $bound.ErrorAction | Should -Be ([System.Management.Automation.ActionPreference]::Stop)
        }

        It 'never asks the cmdlet for the store: it adds the certificate before it knows that the app can be created' {
            Set-PnPStub -Output @((New-PnPRecord))

            $null = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password (ConvertTo-Secure -Text 'Correct-Horse-1')

            (Get-Bound).Keys | Should -Not -Contain 'Store'
        }

        It 'always gives the folder: without it the cmdlet writes the key in the current folder, which can be a repository' {
            Set-PnPStub -Output @((New-PnPRecord))

            $null = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password (ConvertTo-Secure -Text 'Correct-Horse-1')

            (Get-Bound).OutPath | Should -Not -BeNullOrEmpty
        }

        It 'asks for a device code when the plan says so' {
            Set-PnPStub -Output @((New-PnPRecord))

            $null = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate -DeviceLogin) -Password (ConvertTo-Secure -Text 'Correct-Horse-1')

            (Get-Bound).DeviceLogin.IsPresent | Should -BeTrue
        }

        It 'gives the client ID and the thumbprint, and nothing of what else the cmdlet reports: the key above all' {
            Set-PnPStub -Output @('App created.', (New-PnPRecord))

            $result = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password (ConvertTo-Secure -Text 'Correct-Horse-1')

            @($result.PSObject.Properties.Name) | Should -Be @('ClientId', 'Thumbprint')
            $result.ClientId | Should -BeExactly $script:ClientId
            $result.Thumbprint | Should -BeExactly '0123456789ABCDEF0123456789ABCDEF01234567'
            ($result | ConvertTo-Json -Compress) | Should -Not -BeLike '*PFX*'
            ($result | ConvertTo-Json -Compress) | Should -Not -BeLike '*PRIVATE KEY*'
        }

        It 'reads the record whatever comes before and after it, and the last one if there are two' {
            $other = New-PnPRecord -Override @{ 'AzureAppId/ClientId' = '11111111-2222-4333-8444-555555555555' }
            Set-PnPStub -Output @('one', $null, $other, (New-PnPRecord), 'two', 42)

            $result = Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password (ConvertTo-Secure -Text 'Correct-Horse-1')

            $result.ClientId | Should -BeExactly $script:ClientId
        }

        It 'stops when the thumbprint is not one: <Name>' -ForEach @(
            @{ Name = 'missing'; Value = $null }
            @{ Name = 'empty'; Value = '' }
            @{ Name = 'too short'; Value = 'ABCDEF' }
            @{ Name = 'not hexadecimal'; Value = ('G' * 40) }
            @{ Name = 'with a line break'; Value = ("$('A' * 40)`n") }
        ) {
            Set-PnPStub -Output @((New-PnPRecord -Override @{ 'Certificate Thumbprint' = $Value }))

            { Invoke-Adapter -Plan (New-AppPlan -Kind Certificate) -Password (ConvertTo-Secure -Text 'Correct-Horse-1') } | Should -Throw -ExpectedMessage '*unexpected result*thumbprint*'
        }
    }

    Context 'An app that a person signs in with' {
        It 'gives the cmdlet the tenant, the name and the delegated permissions, and no certificate' {
            Set-PnPStub -Output @('App created. You can now connect...', (New-PnPRecord -Override @{ 'Certificate Thumbprint' = $null }))

            $result = Invoke-Adapter -Plan (New-AppPlan -Kind Interactive)

            Get-StubLog | Should -Be @('pnp check', 'Register-PnPEntraIDAppForInteractiveLogin')
            $bound = Get-Bound
            @($bound.Keys | Sort-Object) | Should -Be @('ApplicationName', 'ErrorAction', 'GraphDelegatePermissions', 'SharePointDelegatePermissions', 'Tenant')
            $bound.Tenant | Should -BeExactly 'contoso.onmicrosoft.com'
            @($bound.GraphDelegatePermissions) | Should -Be @('Group.ReadWrite.All')
            @($bound.SharePointDelegatePermissions) | Should -Be @('AllSites.FullControl')
            $result.ClientId | Should -BeExactly $script:ClientId
            $result.Thumbprint | Should -BeExactly ''
        }

        It 'asks for a device code when the plan says so' {
            Set-PnPStub -Output @((New-PnPRecord))

            $null = Invoke-Adapter -Plan (New-AppPlan -Kind Interactive -DeviceLogin)

            (Get-Bound).DeviceLogin.IsPresent | Should -BeTrue
        }

        It 'does not ask a thumbprint of an app that has no certificate' {
            Set-PnPStub -Output @((New-PnPRecord -Override @{ 'Certificate Thumbprint' = 'not looked at' }))

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive) } | Should -Not -Throw
        }
    }

    Context 'What the cmdlet does not give, or gives wrong' {
        It 'gives nothing when the cmdlet reported nothing: the sign-in was cancelled' {
            Set-PnPStub -Output @()
            $null -eq (Invoke-Adapter -Plan (New-AppPlan -Kind Interactive)) | Should -BeTrue

            Set-PnPStub -Output @('just a text')
            $null -eq (Invoke-Adapter -Plan (New-AppPlan -Kind Interactive)) | Should -BeTrue
        }

        It 'stops when the client ID is not the ID of an app: <Name>' -ForEach @(
            @{ Name = 'not a GUID'; Value = 'not-a-guid' }
            @{ Name = 'empty'; Value = '' }
            @{ Name = 'all zeros'; Value = '00000000-0000-0000-0000-000000000000' }
            @{ Name = 'a hidden character'; Value = "$([char]0x200B)4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a" }
        ) {
            Set-PnPStub -Output @((New-PnPRecord -Override @{ 'AzureAppId/ClientId' = $Value }))

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive) } | Should -Throw -ExpectedMessage '*unexpected result*client ID*'
        }

        It 'says what the cmdlet said when it fails, as it said it, so that the failure can be told' {
            Set-PnPStub -Throw 'The application with name SPSSiteLifecycle already exists.'

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive) } | Should -Throw -ExpectedMessage 'The application with name SPSSiteLifecycle already exists.'
        }
    }

    Context 'Before it calls the cmdlet' {
        It 'never registers an app in a tenant that the tool refuses: <Tenant>' -ForEach @(
            @{ Tenant = 'microsoft' }
            @{ Tenant = 'MICROSOFT' }
            @{ Tenant = 'microsoftonline' }
            @{ Tenant = '' }
            @{ Tenant = 'contoso.sharepoint.com' }
        ) {
            Set-PnPStub -Output @((New-PnPRecord))

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive -TenantName $Tenant) } | Should -Throw -ExpectedMessage '*TenantName*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'never registers an app with a name that is not valid: <Name>' -ForEach @(
            @{ Name = '../x' }
            @{ Name = 'CON' }
            @{ Name = '' }
        ) {
            Set-PnPStub -Output @((New-PnPRecord))

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive -ApplicationName $Name) } | Should -Throw -ExpectedMessage '*ApplicationName*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops, without calling the cmdlet, when PnP.PowerShell is not there' {
            Set-PnPStub -Output @((New-PnPRecord)) -PnPMissing $true

            { Invoke-Adapter -Plan (New-AppPlan -Kind Interactive) } | Should -Throw -ExpectedMessage '*PnP.PowerShell is not installed*'

            Get-StubLog | Should -Be @('pnp check')
        }

        It 'does not call the cmdlet with -WhatIf' {
            Set-PnPStub -Output @((New-PnPRecord))

            $result = Invoke-Adapter -Plan (New-AppPlan -Kind Interactive) -WhatIf

            $null -eq $result | Should -BeTrue
            Get-StubLog | Should -Be @('pnp check')
        }
    }
}
