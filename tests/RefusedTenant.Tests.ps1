BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    function script:Get-TestList {
        param([string[]]$RefusedTenant = @())
        @(& $script:Module { param($r) Get-SPSLifecycleRefusedTenantList -RefusedTenant $r } $RefusedTenant)
    }

    function script:Test-TestRefused {
        param([string]$TenantName, [string[]]$RefusedTenant = @())
        & $script:Module { param($t, $r) Test-SPSLifecycleRefusedTenant -TenantName $t -RefusedTenant $r } $TenantName $RefusedTenant
    }

    function script:New-TestSetting {
        param([hashtable]$Override = @{})
        $values = [ordered]@{
            TenantName     = 'contoso'
            AdminUrl       = 'https://contoso-admin.sharepoint.com'
            RefusedTenants = @('microsoft', 'microsoftonline')
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    function script:Assert-TestAllowed {
        param($Setting)
        & $script:Module { param($s) Assert-SPSLifecycleTenantAllowed -Setting $s } $Setting
    }
}

Describe 'Get-SPSLifecycleRefusedTenantList' {
    It 'always holds the Microsoft corporate tenants, first' {
        Get-TestList | Should -Be @('microsoft', 'microsoftonline')
    }

    It 'adds the tenants of the settings, in lowercase, once each' {
        Get-TestList -RefusedTenant @('Fabrikam', 'FABRIKAM', 'microsoft', 'Northwind') | Should -Be @('microsoft', 'microsoftonline', 'fabrikam', 'northwind')
    }

    It 'lowercases without the rules of a culture: <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            Get-TestList -RefusedTenant @('FABRIKAM-TIGER') | Should -Contain 'fabrikam-tiger'
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }
}

Describe 'Test-SPSLifecycleRefusedTenant' {
    It 'refuses a tenant of the built-in list, whatever the case: <Name>' -ForEach @(
        @{ Name = 'microsoft' }
        @{ Name = 'MICROSOFT' }
        @{ Name = 'Microsoft' }
        @{ Name = 'microsoftonline' }
        @{ Name = 'MicrosoftOnline' }
        @{ Name = '  microsoft  ' }
    ) {
        Test-TestRefused -TenantName $Name | Should -BeTrue
    }

    It 'refuses a tenant of the settings, whatever the case' {
        Test-TestRefused -TenantName 'FABRIKAM' -RefusedTenant @('fabrikam') | Should -BeTrue
        Test-TestRefused -TenantName 'fabrikam' -RefusedTenant @('Fabrikam') | Should -BeTrue
    }

    It 'accepts another tenant: <Name>' -ForEach @(
        @{ Name = 'contoso' }
        @{ Name = 'microsoft2' }
        @{ Name = 'notmicrosoft' }
        @{ Name = 'micro-soft' }
    ) {
        Test-TestRefused -TenantName $Name | Should -BeFalse
    }

    It 'refuses the Microsoft tenants under every culture, the Turkish one included, where a capital I is not an i for the culture' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'tr-TR' }
        @{ Culture = 'az-Latn-AZ' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            Test-TestRefused -TenantName 'MICROSOFT' | Should -BeTrue
            Test-TestRefused -TenantName 'MICROSOFTONLINE' | Should -BeTrue
            Test-TestRefused -TenantName 'FABRIKAM' -RefusedTenant @('fabrikam') | Should -BeTrue
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }

    It 'refuses an empty name: nothing can say which tenant it is' {
        Test-TestRefused -TenantName '' | Should -BeTrue
        Test-TestRefused -TenantName '   ' | Should -BeTrue
    }
}

Describe 'Assert-SPSLifecycleTenantAllowed' {
    It 'accepts a tenant that is not refused, with the admin address of that tenant' {
        { Assert-TestAllowed -Setting (New-TestSetting) } | Should -Not -Throw
    }

    It 'accepts the admin address in capitals and with a slash at the end' {
        { Assert-TestAllowed -Setting (New-TestSetting -Override @{ AdminUrl = 'HTTPS://CONTOSO-ADMIN.sharepoint.com/' }) } | Should -Not -Throw
    }

    It 'stops on a tenant that is refused, and says which, right before the sign-in: <Name>' -ForEach @(
        @{ Name = 'a Microsoft tenant'; Tenant = 'microsoft'; Admin = 'https://microsoft-admin.sharepoint.com'; Refused = @() }
        @{ Name = 'a Microsoft tenant in capitals'; Tenant = 'MICROSOFT'; Admin = 'https://microsoft-admin.sharepoint.com'; Refused = @() }
        @{ Name = 'a tenant of the settings'; Tenant = 'fabrikam'; Admin = 'https://fabrikam-admin.sharepoint.com'; Refused = @('fabrikam') }
    ) {
        $setting = New-TestSetting -Override @{ TenantName = $Tenant; AdminUrl = $Admin; RefusedTenants = $Refused }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "*'$($Tenant.ToLowerInvariant())'*refused*"
    }

    It 'stops when the admin address is the one of a refused tenant, whatever the name says' {
        $setting = New-TestSetting -Override @{ TenantName = 'contoso'; AdminUrl = 'https://microsoft-admin.sharepoint.com' }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "*'microsoft'*refused*"
    }

    It 'stops when the admin address is for another tenant than the name, so that the sign-in cannot go elsewhere' {
        $setting = New-TestSetting -Override @{ TenantName = 'contoso'; AdminUrl = 'https://fabrikam-admin.sharepoint.com' }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage '*another tenant*'
    }

    It 'stops when the admin address is not the one that SharePoint gives: <Name>' -ForEach @(
        @{ Name = 'empty'; Admin = '' }
        @{ Name = 'http'; Admin = 'http://contoso-admin.sharepoint.com' }
        @{ Name = 'the tenant site'; Admin = 'https://contoso.sharepoint.com' }
        @{ Name = 'a path'; Admin = 'https://contoso-admin.sharepoint.com/sites/x' }
        @{ Name = 'a port'; Admin = 'https://contoso-admin.sharepoint.com:8443' }
        @{ Name = 'another host'; Admin = 'https://contoso-admin.example.org' }
        @{ Name = 'user information'; Admin = 'https://someone@contoso-admin.sharepoint.com' }
        @{ Name = 'a text that is not an address'; Admin = 'contoso' }
    ) {
        $setting = New-TestSetting -Override @{ AdminUrl = $Admin }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage '*AdminUrl*'
    }

    It 'stops when there is no tenant name' {
        { Assert-TestAllowed -Setting (New-TestSetting -Override @{ TenantName = '' }) } | Should -Throw -ExpectedMessage '*TenantName*'
    }

    It 'refuses the Microsoft tenants even when the settings forgot the list' {
        $setting = New-TestSetting -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com'; RefusedTenants = $null }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage '*refused*'
    }
}
