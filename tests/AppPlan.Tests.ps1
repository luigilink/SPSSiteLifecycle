BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)

    function script:New-AppPlan {
        param([hashtable]$Parameter = @{})

        $arguments = @{ TenantName = 'Contoso'; ApplicationName = 'SPSSiteLifecycle'; Kind = 'Interactive'; Now = $script:Now }
        foreach ($key in $Parameter.Keys) {
            $arguments[$key] = $Parameter[$key]
        }

        & $script:Module { param($a) Get-SPSLifecycleAppPlan @a } $arguments
    }

    function script:Get-PlanLine {
        param($Plan)

        @(& $script:Module { param($p) Format-SPSLifecycleAppPlan -Plan $p } $Plan)
    }
}

Describe 'Get-SPSLifecycleAppPermission' {
    BeforeAll {
        $script:Permissions = @(& $script:Module { Get-SPSLifecycleAppPermission })
    }

    It 'gives a reason for every permission, so that the plan and the wiki say what each one is for' {
        $script:Permissions.Count | Should -BeGreaterThan 0
        foreach ($row in $script:Permissions) {
            "$($row.Reason)".Length | Should -BeGreaterThan 40 -Because "$($row.Resource) $($row.Name) must say what it is used for"
            "$($row.UsedBy)" | Should -Not -BeNullOrEmpty
        }
    }

    It 'names the resource, the kind and the type of every permission, and nothing else' {
        foreach ($row in $script:Permissions) {
            $row.Resource | Should -BeIn @('Graph', 'SharePoint')
            $row.Kind | Should -BeIn @('Certificate', 'Interactive')
            $row.Type | Should -BeIn @('Application', 'Delegated')
            $row.Name | Should -MatchExactly '^[A-Za-z]+(\.[A-Za-z]+)*$'
        }
    }

    It 'asks an app that signs in alone for application permissions only, and an app that a person signs in for delegated ones only' {
        @($script:Permissions | Where-Object { $_.Kind -eq 'Certificate' -and $_.Type -ne 'Application' }) | Should -HaveCount 0
        @($script:Permissions | Where-Object { $_.Kind -eq 'Interactive' -and $_.Type -ne 'Delegated' }) | Should -HaveCount 0
        @($script:Permissions | Where-Object { $_.Kind -eq 'Certificate' }).Count | Should -BeGreaterThan 0
        @($script:Permissions | Where-Object { $_.Kind -eq 'Interactive' }).Count | Should -BeGreaterThan 0
    }

    It 'lists a permission once for each kind' {
        $keys = @($script:Permissions | ForEach-Object { "$($_.Kind)|$($_.Resource)|$($_.Name)" })
        @($keys | Select-Object -Unique) | Should -HaveCount $keys.Count
    }

    It 'asks for what the tool uses today: the SharePoint admin API and the Microsoft 365 group, in each kind' {
        $certificate = @($script:Permissions | Where-Object { $_.Kind -eq 'Certificate' } | ForEach-Object { "$($_.Resource):$($_.Name)" } | Sort-Object)
        $interactive = @($script:Permissions | Where-Object { $_.Kind -eq 'Interactive' } | ForEach-Object { "$($_.Resource):$($_.Name)" } | Sort-Object)

        $certificate | Should -Be @('Graph:Group.ReadWrite.All', 'SharePoint:Sites.FullControl.All')
        $interactive | Should -Be @('Graph:Group.ReadWrite.All', 'SharePoint:AllSites.FullControl')
    }

    It 'does not ask for the reports permission: the tool does not download the reports itself yet' {
        @($script:Permissions | Where-Object { $_.Name -like 'Reports.*' }) | Should -HaveCount 0
    }

    It 'says what the tool does with the SharePoint admin API and with the group, in each kind' {
        foreach ($row in @($script:Permissions | Where-Object { $_.Resource -eq 'SharePoint' })) {
            $row.Reason | Should -Match 'lists every site collection with its lock state, template and size \(Scan\)'
            $row.Reason | Should -Match 'locks or unlocks it, deletes it and requests its archive \(Act\)'
        }

        foreach ($row in @($script:Permissions | Where-Object { $_.Resource -eq 'Graph' })) {
            $row.Reason | Should -Match 'Reads the Microsoft 365 group of a site before an action, and deletes it'
            $row.UsedBy | Should -BeExactly 'Act'
        }
    }

    It 'never asks for a permission that reads or writes the mail, the files or the users of the tenant' {
        foreach ($row in $script:Permissions) {
            $row.Name | Should -Not -Match '^(Mail|Files|User|Directory|Application|RoleManagement|Sites\.ReadWrite)'
        }
    }
}

Describe 'Get-SPSLifecycleAppPlan' {
    It 'names the tenant in lowercase, and the domain that the sign-in goes to' {
        $plan = New-AppPlan -Parameter @{ TenantName = 'ConToso' }

        $plan.TenantName | Should -BeExactly 'contoso'
        $plan.TenantDomain | Should -BeExactly 'contoso.onmicrosoft.com'
        $plan.ApplicationName | Should -BeExactly 'SPSSiteLifecycle'
    }

    It 'plans an app with no certificate for the interactive kind, with the delegated permissions' {
        $plan = New-AppPlan

        $plan.Kind | Should -BeExactly 'Interactive'
        $plan.Certificate | Should -BeNullOrEmpty
        @($plan.Permissions | ForEach-Object { $_.Type } | Select-Object -Unique) | Should -Be @('Delegated')
        $plan.Permissions.Count | Should -Be 2
    }

    It 'plans a certificate for the certificate kind, with the application permissions' {
        $plan = New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys/spslc' }

        $plan.Kind | Should -BeExactly 'Certificate'
        @($plan.Permissions | ForEach-Object { $_.Type } | Select-Object -Unique) | Should -Be @('Application')
        $plan.Certificate.ValidYears | Should -Be 2
        $plan.Certificate.Folder | Should -BeExactly '/keys/spslc'
        $plan.Certificate.PfxPath | Should -BeExactly (Join-Path -Path '/keys/spslc' -ChildPath 'SPSSiteLifecycle.pfx')
        $plan.Certificate.CerPath | Should -BeExactly (Join-Path -Path '/keys/spslc' -ChildPath 'SPSSiteLifecycle.cer')
        $plan.Certificate.Store | Should -BeExactly 'None'
    }

    It 'dates the end of the certificate from the time of the run and the number of years' -ForEach @(
        @{ Years = 1; Expected = '2027-10-30' }
        @{ Years = 2; Expected = '2028-10-30' }
        @{ Years = 5; Expected = '2031-10-30' }
    ) {
        $plan = New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys'; ValidYears = $Years }

        $plan.Certificate.ValidYears | Should -Be $Years
        $plan.Certificate.ExpiresOn.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) | Should -BeExactly $Expected
    }

    It 'puts the certificate in the store of the user when it is asked to' {
        $plan = New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys'; UseCertificateStore = $true }

        $plan.Certificate.Store | Should -BeExactly 'CurrentUser'
    }

    It 'signs in with a browser, or with a device code when it is asked to' {
        (New-AppPlan).SignIn | Should -BeExactly 'Browser'
        (New-AppPlan -Parameter @{ DeviceLogin = $true }).SignIn | Should -BeExactly 'DeviceCode'
    }

    It 'says which roles create the app and which give the consent, as Microsoft Learn does' {
        $interactive = New-AppPlan
        $certificate = New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' }

        $interactive.CreatorRoles | Should -Match 'Application Developer'
        $interactive.CreatorRoles | Should -Match 'Global Administrator'
        $interactive.ConsentRoles | Should -Match 'Application Administrator'
        $interactive.ConsentRoles | Should -Match 'Global Administrator'

        $certificate.ConsentRoles | Should -Match 'Privileged Role Administrator'
        $certificate.ConsentRoles | Should -Match 'Global Administrator'
        $certificate.ConsentRoles | Should -Match 'not enough'
    }

    It 'refuses a certificate with no folder: the plan cannot say where the key goes' {
        { New-AppPlan -Parameter @{ Kind = 'Certificate' } } | Should -Throw '*folder*'
    }
}

Describe 'Format-SPSLifecycleAppPlan' {
    It 'says that nothing has been changed yet, and names the tenant, its domain and the app' {
        $lines = Get-PlanLine -Plan (New-AppPlan)

        $lines[0] | Should -Match 'nothing has been changed'
        ($lines -join "`n") | Should -Match 'contoso \(contoso\.onmicrosoft\.com\)'
        ($lines -join "`n") | Should -Match 'SPSSiteLifecycle'
    }

    It 'lists every permission with the reason that the table gives for it' {
        foreach ($kind in 'Interactive', 'Certificate') {
            $plan = New-AppPlan -Parameter @{ Kind = $kind; Folder = '/keys' }
            $text = (Get-PlanLine -Plan $plan) -join "`n"

            foreach ($row in $plan.Permissions) {
                $text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape($row.Name))
                $text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape($row.Reason))
            }
        }
    }

    It 'says which type of permission is requested: delegated for a person, application for the app' {
        ((Get-PlanLine -Plan (New-AppPlan)) -join "`n") | Should -Match 'Delegated permissions requested'
        ((Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' })) -join "`n") | Should -Match 'Application permissions requested'
    }

    It 'writes the date that the certificate ends the same way whatever the culture of the machine, a calendar that is not Gregorian included' {
        $thai = [System.Globalization.CultureInfo]::new('th-TH')
        if ($thai.DateTimeFormat.Calendar -isnot [System.Globalization.ThaiBuddhistCalendar]) {
            Set-ItResult -Skipped -Because 'this machine has no culture data for the Buddhist calendar'
            return
        }

        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = $thai
            $text = (Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' })) -join "`n"
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }

        $text | Should -Match '2028-10-30'
    }

    It 'says what each kind of app is, and that a person signs in or that the app does' {
        ((Get-PlanLine -Plan (New-AppPlan)) -join "`n") | Should -Match 'Interactive.*person signs in'
        ((Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' })) -join "`n") | Should -Match 'Certificate.*signs in alone'
    }

    It 'says where the key and the certificate go, how long the certificate lives and that the key is for the user only' {
        $text = (Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys/spslc'; ValidYears = 2 })) -join "`n"

        $text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape((Join-Path -Path '/keys/spslc' -ChildPath 'SPSSiteLifecycle.pfx')))
        $text | Should -Match ([System.Text.RegularExpressions.Regex]::Escape((Join-Path -Path '/keys/spslc' -ChildPath 'SPSSiteLifecycle.cer')))
        $text | Should -Match '2 years'
        $text | Should -Match '2028-10-30'
        $text | Should -Match 'only you can read'
        $text | Should -Match 'password'
    }

    It 'speaks of the certificate store only when it is asked for' {
        $without = (Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' })) -join "`n"
        $with = (Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys'; UseCertificateStore = $true })) -join "`n"

        $without | Should -Not -Match 'store'
        $with | Should -Match 'CurrentUser'
    }

    It 'speaks of no certificate for the interactive kind' {
        $text = (Get-PlanLine -Plan (New-AppPlan)) -join "`n"

        $text | Should -Not -Match '\.pfx'
        $text | Should -Not -Match 'password'
        $text | Should -Match 'no certificate'
    }

    It 'says how the person signs in: a browser, or a device code' {
        ((Get-PlanLine -Plan (New-AppPlan)) -join "`n") | Should -Match 'browser'
        ((Get-PlanLine -Plan (New-AppPlan -Parameter @{ DeviceLogin = $true })) -join "`n") | Should -Match 'device code'
    }

    It 'says which roles are needed, and what to do when the consent cannot be given' {
        $text = (Get-PlanLine -Plan (New-AppPlan -Parameter @{ Kind = 'Certificate'; Folder = '/keys' })) -join "`n"

        $text | Should -Match 'Privileged Role Administrator'
        $text | Should -Match 'Application Developer'
        $text | Should -Match 'consent'
        $text | Should -Match 'Microsoft Entra admin center'
    }

    It 'says that no secret goes into the settings file or the repository, and that no site is touched' {
        $text = (Get-PlanLine -Plan (New-AppPlan)) -join "`n"

        $text | Should -Match 'no secret'
        $text | Should -Match 'touches no site'
    }
}
