BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Tenant = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:Set-WebStub {
        param($Answer, [string]$Throw = '')

        Set-ModuleStub -Stub @{
            'Invoke-RestMethod' = @'
[CmdletBinding()]
param([string]$Uri, [string]$Method, [int]$TimeoutSec)
$script:StubLog.Add("get $Uri | method=$Method | timeout=$TimeoutSec | stop=$($ErrorActionPreference -eq 'Stop' -or $PSBoundParameters.ContainsKey('ErrorAction'))")
if ($script:StubData.Throw) { throw $script:StubData.Throw }
$script:StubData.Answer
'@
        } -Data @{ Answer = $Answer; Throw = $Throw }
    }

    function script:Get-TenantId {
        param([string]$Domain = 'contoso.onmicrosoft.com')

        & $script:Module { param($d) Get-SPSLifecycleTenantId -TenantDomain $d } $Domain
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Get-SPSLifecycleTenantId' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'reads the ID of the tenant from the public OpenID configuration of its domain, which holds no secret and needs no sign-in' {
        Set-WebStub -Answer ([PSCustomObject]@{ token_endpoint = "https://login.microsoftonline.com/$script:Tenant/oauth2/v2.0/token"; issuer = "https://login.microsoftonline.com/$script:Tenant/v2.0" })

        Get-TenantId | Should -BeExactly $script:Tenant

        @(Get-StubLog) | Should -Be @('get https://login.microsoftonline.com/contoso.onmicrosoft.com/.well-known/openid-configuration | method=Get | timeout=20 | stop=True')
    }

    It 'reads it from the issuer when the token endpoint holds none, and gives it in lowercase' {
        Set-WebStub -Answer ([PSCustomObject]@{ token_endpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'; issuer = "https://sts.windows.net/$($script:Tenant.ToUpperInvariant())/" })

        Get-TenantId | Should -BeExactly $script:Tenant
    }

    It 'says that it could not read it when the answer holds none, or only zeros: <Name>' -ForEach @(
        @{ Name = 'nothing'; Answer = $null }
        @{ Name = 'a text'; Answer = 'not an OpenID configuration' }
        @{ Name = 'no GUID'; Answer = [PSCustomObject]@{ token_endpoint = 'https://login.microsoftonline.com/common/oauth2/token'; issuer = 'https://example.org/' } }
        @{ Name = 'zeros'; Answer = [PSCustomObject]@{ token_endpoint = 'https://login.microsoftonline.com/00000000-0000-0000-0000-000000000000/oauth2/token' } }
    ) {
        Set-WebStub -Answer $Answer

        { Get-TenantId } | Should -Throw -ExpectedMessage '*holds no tenant ID*'
    }

    It 'says that it could not read it, and why, when the call fails' {
        Set-WebStub -Answer $null -Throw 'The remote name could not be resolved.'

        { Get-TenantId } | Should -Throw -ExpectedMessage '*could not be read*openid-configuration*remote name could not be resolved*'
    }

    It 'calls nothing for a domain that is not one of the tenant: <Domain>' -ForEach @(
        @{ Domain = 'contoso.com' }
        @{ Domain = 'contoso.sharepoint.com' }
        @{ Domain = 'contoso.onmicrosoft.com/evil' }
        @{ Domain = 'evil.example/contoso.onmicrosoft.com' }
        @{ Domain = 'contoso.onmicrosoft.com?x=1' }
        @{ Domain = '..onmicrosoft.com' }
        @{ Domain = 'a b.onmicrosoft.com' }
        @{ Domain = '' }
    ) {
        Set-WebStub -Answer ([PSCustomObject]@{ token_endpoint = "https://login.microsoftonline.com/$script:Tenant/oauth2/token" })

        { Get-TenantId -Domain $Domain } | Should -Throw -ExpectedMessage '*not the initial domain of a tenant*'

        Get-StubLog | Should -HaveCount 0
    }
}
