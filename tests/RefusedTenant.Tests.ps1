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

    It 'stops on a tenant name that is refused, and names the setting, even when the admin address is for another tenant' {
        $setting = New-TestSetting -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://contoso-admin.sharepoint.com' }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "TenantName: the tenant 'microsoft' is refused.*"
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

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "AdminUrl: '*' is not the address of the admin site of a tenant (https://<tenant>-admin.sharepoint.com)."
    }

    It 'stops when the tenant name is not the name of a tenant, and writes the character that it is about: <Name>' -ForEach @(
        @{ Name = 'a Kelvin sign'; Tenant = "cont$([char]0x212A)so"; Admin = "https://cont$([char]0x212A)so-admin.sharepoint.com"; Shown = 'cont\u212Aso' }
        @{ Name = 'a capital I with a dot above'; Tenant = "$([char]0x0130)stanbul"; Admin = "https://$([char]0x0130)stanbul-admin.sharepoint.com"; Shown = '\u0130stanbul' }
        @{ Name = 'a dotless i'; Tenant = "cont$([char]0x0131)so"; Admin = 'https://contoso-admin.sharepoint.com'; Shown = 'cont\u0131so' }
        @{ Name = 'a soft hyphen'; Tenant = "cont$([char]0xAD)oso"; Admin = 'https://contoso-admin.sharepoint.com'; Shown = 'cont\u00ADoso' }
        @{ Name = 'a name of 64 characters'; Tenant = ('a' * 64); Admin = "https://$('a' * 64)-admin.sharepoint.com"; Shown = ('a' * 64) }
        @{ Name = 'a name that starts with a hyphen'; Tenant = '-contoso'; Admin = 'https://-contoso-admin.sharepoint.com'; Shown = '-contoso' }
        @{ Name = 'an address'; Tenant = 'contoso.sharepoint.com'; Admin = 'https://contoso.sharepoint.com-admin.sharepoint.com'; Shown = 'contoso.sharepoint.com' }
    ) {
        $setting = New-TestSetting -Override @{ TenantName = $Tenant; AdminUrl = $Admin }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "TenantName: '$Shown' is not the name of a tenant: letters, digits and hyphens only, starting with a letter or a digit, 63 characters at most."
    }

    It 'stops when the admin address has a letter that only looks like the one of ASCII, and writes it as \uXXXX: <Name>' -ForEach @(
        @{ Name = 'a capital I with a dot above in admin'; Tenant = 'contoso'; Admin = "https://contoso-adm$([char]0x0130)n.sharepoint.com"; Shown = 'https://contoso-adm\u0130n.sharepoint.com' }
        @{ Name = 'a capital I with a dot above in sharepoint'; Tenant = 'contoso'; Admin = "https://contoso-admin.sharepo$([char]0x0130)nt.com"; Shown = 'https://contoso-admin.sharepo\u0130nt.com' }
        @{ Name = 'a Kelvin sign in the tenant of the address'; Tenant = 'kiwi'; Admin = "https://$([char]0x212A)iwi-admin.sharepoint.com"; Shown = 'https://\u212Aiwi-admin.sharepoint.com' }
        @{ Name = 'a full-width letter'; Tenant = 'contoso'; Admin = "https://contoso-admin.sharepoint.c$([char]0xFF4F)m"; Shown = 'https://contoso-admin.sharepoint.c\uFF4Fm' }
    ) {
        $setting = New-TestSetting -Override @{ TenantName = $Tenant; AdminUrl = $Admin }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage "AdminUrl: '$Shown' is not the address of the admin site of a tenant (https://<tenant>-admin.sharepoint.com)."
    }

    It 'accepts the names that the rule allows, under <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            { Assert-TestAllowed -Setting (New-TestSetting -Override @{ TenantName = 'KIWI-IKI'; AdminUrl = 'https://kiwi-iki-admin.sharepoint.com' }) } | Should -Not -Throw
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }

    It 'stops when there is no tenant name' {
        { Assert-TestAllowed -Setting (New-TestSetting -Override @{ TenantName = '' }) } | Should -Throw -ExpectedMessage 'TenantName: no tenant name was given, so the tool cannot tell which tenant it would sign in to.'
    }

    It 'refuses the Microsoft tenants even when the settings forgot the list' {
        $setting = New-TestSetting -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com'; RefusedTenants = $null }

        { Assert-TestAllowed -Setting $setting } | Should -Throw -ExpectedMessage '*refused*'
    }
}
