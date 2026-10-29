BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
    $script:ExamplePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/config/SPSSiteLifecycle.example.psd1'

    function script:New-TestConfig {
        param([string]$Body, [string]$Name = 'settings.psd1')
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $path = Join-Path -Path $folder -ChildPath $Name
        Set-Content -LiteralPath $path -Value $Body -Encoding utf8
        $path
    }

    function script:Get-TestSetting {
        param([string]$Path, [string]$Phase = 'Scan')
        Get-SPSLifecycleSetting -Path $Path -Phase $Phase
    }

    $script:Valid = @"
@{
    TenantName = 'Contoso'
    ClientId   = '11111111-2222-3333-4444-555555555555'
    Scan       = @{ SharePointUsageReport = 'usage.csv' }
    Act        = @{ InputFile = 'sites.csv' }
}
"@
}

Describe 'Get-SPSLifecycleSetting' {
    Context 'A valid file' {
        BeforeAll {
            $script:Path = New-TestConfig -Body $script:Valid
            $folder = Split-Path -Path $script:Path -Parent
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'usage.csv') -Value 'x'
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'sites.csv') -Value 'x'
            $script:Folder = $folder
            $script:Setting = Get-TestSetting -Path $script:Path -Phase Scan
        }

        It 'lowercases the tenant name and builds the URLs' {
            $script:Setting.TenantName | Should -Be 'contoso'
            $script:Setting.TenantUrl | Should -Be 'https://contoso.sharepoint.com'
            $script:Setting.AdminUrl | Should -Be 'https://contoso-admin.sharepoint.com'
        }

        It 'applies the defaults' {
            $script:Setting.MinLockedDays | Should -Be 365
            $script:Setting.DeleteMaxSizeGB | Should -Be 1
            $script:Setting.AcceptedLockStates | Should -HaveCount 1
            $script:Setting.AcceptedLockStates[0] | Should -Be 'ReadOnly'
            $script:Setting.Scan.InactiveDays | Should -Be 365
            $script:Setting.Scan.LockStates[0] | Should -Be 'ReadOnly'
            $script:Setting.Act.Execute | Should -BeFalse
            $script:Setting.Act.MaxActions | Should -Be 25
            $script:Setting.Act.DelaySeconds | Should -Be 2
            $script:Setting.Act.MaxCsvAgeDays | Should -Be 30
            $script:Setting.CsvDelimiter | Should -Be 'Culture'
            @($script:Setting.LockDateFiles) | Should -HaveCount 0
        }

        It 'resolves the relative paths against the folder of the file, not the current folder' {
            $script:Setting.OutputFolder | Should -Be (Join-Path -Path $script:Folder -ChildPath 'Reports')
            $script:Setting.LockJournal | Should -Be (Join-Path -Path (Join-Path -Path $script:Folder -ChildPath 'Reports') -ChildPath 'lock-journal.csv')
            $script:Setting.Scan.SharePointUsageReport | Should -Be (Join-Path -Path $script:Folder -ChildPath 'usage.csv')
        }

        It 'always refuses the Microsoft tenants and adds the ones of the settings' {
            $path = New-TestConfig -Body ($script:Valid -replace "Scan       =", "RefusedTenants = @('ContosoProd')`n    Scan       =")
            $folder = Split-Path -Path $path -Parent
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'usage.csv') -Value 'x'
            $setting = Get-TestSetting -Path $path -Phase Scan

            $setting.RefusedTenants | Should -Contain 'microsoft'
            $setting.RefusedTenants | Should -Contain 'microsoftonline'
            $setting.RefusedTenants | Should -Contain 'contosoprod'
        }

        It 'does not need the Act settings for a Scan' {
            $path = New-TestConfig -Body $script:Valid.Replace("Act        = @{ InputFile = 'sites.csv' }", '')
            $folder = Split-Path -Path $path -Parent
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'usage.csv') -Value 'x'

            { Get-TestSetting -Path $path -Phase Scan } | Should -Not -Throw
        }

        It 'needs InputFile for an Act, and checks that the file exists' {
            $path = New-TestConfig -Body $script:Valid
            $folder = Split-Path -Path $path -Parent

            { Get-TestSetting -Path $path -Phase Act } | Should -Throw -ExpectedMessage "*Act.InputFile*was not found*"

            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'sites.csv') -Value 'x'
            (Get-TestSetting -Path $path -Phase Act).Act.InputFile | Should -Be (Join-Path -Path $folder -ChildPath 'sites.csv')
        }

        It 'does not check the Scan reports for an Act' {
            $path = New-TestConfig -Body $script:Valid
            $folder = Split-Path -Path $path -Parent
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'sites.csv') -Value 'x'

            { Get-TestSetting -Path $path -Phase Act } | Should -Not -Throw
        }
    }

    Context 'Problems in the file' {
        It 'stops on an unknown setting and suggests the closest one' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Act = @{ MaxAction = 5 } }"

            { Get-TestSetting -Path $path -Phase Act } | Should -Throw -ExpectedMessage "*Unknown setting 'MaxAction'*Did you mean 'MaxActions'*"
        }

        It 'says when a setting is in the wrong section: <Name>' -ForEach @(
            @{ Name = 'Execute at the top'; Body = "@{ Execute = `$true }"; Message = "*'Execute' belongs in the Act section*" }
            @{ Name = 'MaxActions at the top'; Body = "@{ MaxActions = 5 }"; Message = "*'MaxActions' belongs in the Act section*" }
            @{ Name = 'a Scan setting in Act'; Body = "@{ Act = @{ InactiveDays = 5 } }"; Message = "*'InactiveDays' belongs in the Scan section*" }
            @{ Name = 'a shared setting in Scan'; Body = "@{ Scan = @{ TenantName = 'x' } }"; Message = "*'TenantName' is a shared setting*" }
        ) {
            $path = New-TestConfig -Body $Body

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage $Message
        }

        It 'refuses <Name>' -ForEach @(
            @{ Name = 'the text false for a boolean'; Section = 'Act'; Key = 'Execute'; Value = "'false'"; Message = '*Act.Execute*$true or $false*' }
            @{ Name = 'the text 25 for a number'; Section = 'Act'; Key = 'MaxActions'; Value = "'25'"; Message = '*Act.MaxActions*whole number*' }
            @{ Name = 'a number out of range'; Section = 'Act'; Key = 'MaxActions'; Value = '0'; Message = '*Act.MaxActions*between 1 and 10000*' }
            @{ Name = 'a decimal for a whole number'; Section = 'Shared'; Key = 'MinLockedDays'; Value = '1.5'; Message = '*MinLockedDays*whole number*' }
            @{ Name = 'the text 1 for a size'; Section = 'Shared'; Key = 'DeleteMaxSizeGB'; Value = "'1'"; Message = '*DeleteMaxSizeGB*number*' }
            @{ Name = 'a URL for the tenant name'; Section = 'Shared'; Key = 'TenantName'; Value = "'contoso.sharepoint.com'"; Message = '*TenantName*not a URL*' }
            @{ Name = 'NoAccess among the accepted lock states'; Section = 'Shared'; Key = 'AcceptedLockStates'; Value = "@('ReadOnly', 'NoAccess')"; Message = '*AcceptedLockStates*ReadOnly, Unlock*' }
            @{ Name = 'a text that is not a GUID for ClientId'; Section = 'Shared'; Key = 'ClientId'; Value = "'abc'"; Message = '*ClientId*GUID*' }
            @{ Name = 'an unknown separator'; Section = 'Shared'; Key = 'CsvDelimiter'; Value = "'|'"; Message = '*CsvDelimiter*one of*' }
        ) {
            $entries = [ordered]@{ TenantName = "'contoso'"; ClientId = "'11111111-2222-3333-4444-555555555555'" }
            if ($Section -eq 'Shared') {
                $entries[$Key] = $Value
            }
            else {
                $entries[$Section] = "@{ $Key = $Value }"
            }

            $body = '@{ ' + (($entries.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join '; ') + ' }'
            $path = New-TestConfig -Body $body

            { Get-TestSetting -Path $path -Phase Act } | Should -Throw -ExpectedMessage $Message
        }

        It 'refuses the tenant <Tenant>' -ForEach @(
            @{ Tenant = 'microsoft' }
            @{ Tenant = 'Microsoft' }
            @{ Tenant = 'microsoftonline' }
        ) {
            $path = New-TestConfig -Body "@{ TenantName = '$Tenant'; ClientId = '11111111-2222-3333-4444-555555555555'; RefusedTenants = @() }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*is refused*'
        }

        It 'refuses a tenant listed in RefusedTenants' {
            $path = New-TestConfig -Body "@{ TenantName = 'contosoprod'; ClientId = '11111111-2222-3333-4444-555555555555'; RefusedTenants = @('ContosoProd') }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*is refused*'
        }

        It 'needs at least one activity report for a Scan' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555' }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*at least one activity report*'
        }

        It 'says that a report file is missing' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Scan = @{ TeamsActivityReport = 'nope.csv' } }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*Scan.TeamsActivityReport*was not found*nope.csv*'
        }

        It 'requires UnlockBeforeArchive with GrantSiteAdmin' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Act = @{ GrantSiteAdmin = `$true } }"

            { Get-TestSetting -Path $path -Phase Act } | Should -Throw -ExpectedMessage '*GrantSiteAdmin*UnlockBeforeArchive*'
        }

        It 'reports every problem at once' {
            $path = New-TestConfig -Body "@{ TenantName = 'x.y'; ClientId = 'abc'; Execute = `$true; Act = @{ MaxActions = 0 } }"
            $message = ''
            try { Get-TestSetting -Path $path -Phase Act } catch { $message = $_.Exception.Message }

            $message | Should -Match 'has 5 problem\(s\)'
            $message | Should -Match 'TenantName'
            $message | Should -Match 'ClientId'
            $message | Should -Match "'Execute'"
            $message | Should -Match 'Act.MaxActions'
            $message | Should -Match 'Act.InputFile'
        }

        It 'stops when the file does not exist' {
            { Get-TestSetting -Path (Join-Path -Path $TestDrive -ChildPath 'missing.psd1') } | Should -Throw -ExpectedMessage '*Settings file not found*'
        }

        It 'never runs code that is written in the file' {
            $marker = Join-Path -Path $TestDrive -ChildPath 'marker.txt'
            $path = New-TestConfig -Body "@{ TenantName = (New-Item -Path '$marker' -ItemType File -Force) }"

            { Get-TestSetting -Path $path } | Should -Throw -ExpectedMessage '*Cannot read the settings file*'
            Test-Path -LiteralPath $marker | Should -BeFalse
        }

        It 'stops when the file does not hold a hashtable' {
            $path = New-TestConfig -Body "'just a text'"

            { Get-TestSetting -Path $path } | Should -Throw
        }
    }

    Context 'Lock states and lists' {
        It 'accepts one text where a list is expected, and fixes the case' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; AcceptedLockStates = 'unlock'; Scan = @{ TeamsActivityReport = 'teams.csv' } }"
            Set-Content -LiteralPath (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath 'teams.csv') -Value 'x'
            $setting = Get-TestSetting -Path $path -Phase Scan

            $setting.AcceptedLockStates | Should -HaveCount 1
            $setting.AcceptedLockStates[0] | Should -Be 'Unlock'
        }

        It 'resolves the lock date files and checks that they exist' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; LockDateFiles = @('lot1.csv', 'lot2.csv'); Scan = @{ TeamsActivityReport = 'teams.csv' } }"
            $folder = Split-Path -Path $path -Parent
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'teams.csv') -Value 'x'
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'lot1.csv') -Value 'x'

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*LockDateFiles*lot2.csv*'
        }
    }

    Context 'CSV separator' {
        It 'follows the culture: <Culture> gives <Expected>' -ForEach @(
            @{ Culture = 'en-US'; Expected = ',' }
            @{ Culture = 'fr-FR'; Expected = ';' }
            @{ Culture = 'de-DE'; Expected = ';' }
        ) {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Scan = @{ TeamsActivityReport = 'teams.csv' } }"
            Set-Content -LiteralPath (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath 'teams.csv') -Value 'x'
            $previous = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                $setting = Get-TestSetting -Path $path -Phase Scan
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }

            "$($setting.CsvDelimiterChar)" | Should -Be $Expected
        }

        It 'follows the setting: <Value> gives <Expected>' -ForEach @(
            @{ Value = "','"; Expected = ',' }
            @{ Value = "';'"; Expected = ';' }
            @{ Value = "'Tab'"; Expected = "`t" }
        ) {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; CsvDelimiter = $Value; Scan = @{ TeamsActivityReport = 'teams.csv' } }"
            Set-Content -LiteralPath (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath 'teams.csv') -Value 'x'

            "$((Get-TestSetting -Path $path -Phase Scan).CsvDelimiterChar)" | Should -Be $Expected
        }
    }
}

Describe 'The settings schema' {
    BeforeAll {
        $script:Schema = @(& $script:Module { Get-SPSLifecycleSettingSchema })
    }

    It 'describes every setting' {
        foreach ($row in $script:Schema) {
            $row.Name | Should -Not -BeNullOrEmpty
            $row.Description | Should -Not -BeNullOrEmpty
            $row.Section | Should -BeIn 'Shared', 'Scan', 'Act'
            $row.Type | Should -BeIn 'String', 'Guid', 'Path', 'PathList', 'StringList', 'Choice', 'ChoiceList', 'Int', 'Double', 'Bool'
        }
    }

    It 'has no duplicate name' {
        @($script:Schema | Group-Object -Property Name | Where-Object { $_.Count -gt 1 }) | Should -HaveCount 0
    }

    It 'gives a default that its own rules accept: <Name>' -ForEach @(
        @{ Name = 'RefusedTenants' }, @{ Name = 'AcceptedLockStates' }, @{ Name = 'MinLockedDays' }, @{ Name = 'DeleteMaxSizeGB' }
        @{ Name = 'LockDateFiles' }, @{ Name = 'ExclusionFiles' }, @{ Name = 'CsvDelimiter' }, @{ Name = 'CsvDateFormats' }
        @{ Name = 'InactiveDays' }, @{ Name = 'LockStates' }, @{ Name = 'Execute' }, @{ Name = 'MaxActions' }
        @{ Name = 'DelaySeconds' }, @{ Name = 'MaxCsvAgeDays' }, @{ Name = 'GrantSiteAdmin' }, @{ Name = 'UnlockBeforeArchive' }
    ) {
        $row = $script:Schema | Where-Object { $_.Name -eq $Name }
        $result = & $script:Module { param($r, $f) Resolve-SPSLifecycleSettingValue -Row $r -Value $r.Default -BaseFolder $f } $row $TestDrive

        $result.Error | Should -BeNullOrEmpty
    }

    It 'documents the default of <Name> as it is: <Expected>' -ForEach @(
        @{ Name = 'OutputFolder'; Expected = '`Reports`' }
        @{ Name = 'RefusedTenants'; Expected = '`@()`' }
        @{ Name = 'AcceptedLockStates'; Expected = '`@(''ReadOnly'')`' }
        @{ Name = 'MinLockedDays'; Expected = '`365`' }
        @{ Name = 'DeleteMaxSizeGB'; Expected = '`1`' }
        @{ Name = 'LockDateFiles'; Expected = '`@()`' }
        @{ Name = 'ExclusionFiles'; Expected = '`@()`' }
        @{ Name = 'CsvDelimiter'; Expected = '`Culture`' }
        @{ Name = 'CsvDateFormats'; Expected = '`@()`' }
        @{ Name = 'InactiveDays'; Expected = '`365`' }
        @{ Name = 'LockStates'; Expected = '`@(''ReadOnly'')`' }
        @{ Name = 'Execute'; Expected = '`$false`' }
        @{ Name = 'MaxActions'; Expected = '`25`' }
        @{ Name = 'DelaySeconds'; Expected = '`2`' }
        @{ Name = 'MaxCsvAgeDays'; Expected = '`30`' }
        @{ Name = 'GrantSiteAdmin'; Expected = '`$false`' }
        @{ Name = 'UnlockBeforeArchive'; Expected = '`$false`' }
    ) {
        $row = $script:Schema | Where-Object { $_.Name -eq $Name }
        $default = $row.Default
        $text = switch ($row.Type) {
            'Int' { '`' + [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $default) + '`' }
            'Double' { '`' + [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $default) + '`' }
            'Bool' { '`$' + "$default".ToLowerInvariant() + '`' }
            'Choice' { '`' + $default + '`' }
            'ChoiceList' { '`@(' + ((@($default) | ForEach-Object { "'$_'" }) -join ', ') + ')`' }
            'StringList' { '`@(' + ((@($default) | ForEach-Object { "'$_'" }) -join ', ') + ')`' }
            'PathList' { '`@(' + ((@($default) | ForEach-Object { "'$_'" }) -join ', ') + ')`' }
            default { '`' + $default + '`' }
        }

        $row.DefaultText | Should -BeExactly $Expected
        $row.DefaultText | Should -BeExactly $text -Because 'DefaultText must describe the real default'
    }

    It 'is covered by the example file: every setting is written in it' {
        $text = Get-Content -LiteralPath $script:ExamplePath -Raw
        foreach ($row in $script:Schema) {
            $text | Should -Match "(?m)^\s*#?\s*$($row.Name)\s*=" -Because "the example file must show $($row.Name)"
        }
    }

    It 'has an example file whose values are all valid once uncommented' {
        $names = @($script:Schema | ForEach-Object { $_.Name }) -join '|'
        $lines = Get-Content -LiteralPath $script:ExamplePath | ForEach-Object { $_ -replace "^(\s*)#\s*((?:$names)\s*=)", '$1$2' }
        $path = Join-Path -Path $TestDrive -ChildPath 'uncommented.psd1'
        Set-Content -LiteralPath $path -Value $lines -Encoding utf8
        $data = Import-PowerShellDataFile -LiteralPath $path

        $problems = foreach ($row in $script:Schema) {
            $source = if ($row.Section -eq 'Shared') { $data } else { $data[$row.Section] }
            if (-not $source.ContainsKey($row.Name)) {
                "$($row.Name): not in the example"
                continue
            }

            $result = & $script:Module { param($r, $v, $f) Resolve-SPSLifecycleSettingValue -Row $r -Value $v -BaseFolder $f } $row $source[$row.Name] $TestDrive
            if ($result.Error) {
                "$($row.Name): $($result.Error)"
            }
        }

        @($problems) | Should -HaveCount 0
    }

    It 'loads the example file as it is, once its input files exist' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'example'
        $null = New-Item -Path (Join-Path -Path $folder -ChildPath 'Reports') -ItemType Directory -Force
        Copy-Item -LiteralPath $script:ExamplePath -Destination (Join-Path -Path $folder -ChildPath 'contoso.psd1')
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'SharePointSiteUsageDetail.csv') -Value 'x'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Reports/sites.csv') -Value 'x'

        { Get-TestSetting -Path (Join-Path -Path $folder -ChildPath 'contoso.psd1') -Phase Scan } | Should -Not -Throw
        { Get-TestSetting -Path (Join-Path -Path $folder -ChildPath 'contoso.psd1') -Phase Act } | Should -Not -Throw
    }
}

Describe 'Get-SPSLifecycleSimilarName' {
    It 'suggests <Expected> for <Name>' -ForEach @(
        @{ Name = 'MaxAction'; Expected = 'MaxActions' }
        @{ Name = 'maxactions'; Expected = 'MaxActions' }
        @{ Name = 'TenantNam'; Expected = 'TenantName' }
        @{ Name = 'Exectue'; Expected = 'Execute' }
        @{ Name = 'Completely different'; Expected = '' }
    ) {
        $candidates = @('MaxActions', 'TenantName', 'Execute', 'DelaySeconds')
        $result = & $script:Module { param($n, $c) Get-SPSLifecycleSimilarName -Name $n -Candidate $c } $Name $candidates

        $result | Should -Be $Expected
    }
}
