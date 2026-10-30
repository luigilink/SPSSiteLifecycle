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

    function script:Invoke-UnderCulture {
        param([string]$Culture, [scriptblock]$Action)

        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            & $Action
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }

    # The row of the schema of a setting, and the value of that row as the settings file reader checks it.
    function script:Get-TestRow {
        param([string]$Name)
        @(& $script:Module { Get-SPSLifecycleSettingSchema } | Where-Object { $_.Name -ceq $Name })[0]
    }

    function script:Resolve-TestValue {
        param([string]$Name, $Value)
        & $script:Module { param($r, $v) Resolve-SPSLifecycleSettingValue -Row $r -Value $v -BaseFolder '.' } (Get-TestRow -Name $Name) $Value
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

Describe 'The names that the settings hold' {
    Context 'TenantName is ASCII, whatever the culture and the case folding' {
        It 'accepts <Name> under <Culture>' -ForEach @(
            foreach ($culture in 'en-US', 'fr-FR', 'de-DE', 'tr-TR') {
                @{ Culture = $culture; Name = 'a name in lowercase'; Value = 'contoso' }
                @{ Culture = $culture; Name = 'a name with a capital'; Value = 'Contoso' }
                @{ Culture = $culture; Name = 'a name in capitals'; Value = 'CONTOSO' }
                @{ Culture = $culture; Name = 'one letter'; Value = 'a' }
                @{ Culture = $culture; Name = 'a hyphen inside'; Value = 'a-b' }
                @{ Culture = $culture; Name = 'a digit first'; Value = '1abc' }
                @{ Culture = $culture; Name = 'the letters i and k in capitals, which a Turkish machine reads differently'; Value = 'KIWI-IKI' }
                @{ Culture = $culture; Name = 'a name of 63 characters'; Value = ('a' * 63) }
            }
        ) {
            Invoke-UnderCulture -Culture $Culture -Action {
                $result = Resolve-TestValue -Name 'TenantName' -Value $Value

                $result.Error | Should -BeExactly ''
                $result.Value | Should -BeExactly $Value
            }
        }

        It 'refuses <Name> under <Culture>, and writes the character that it is about as \uXXXX' -ForEach @(
            foreach ($culture in 'en-US', 'fr-FR', 'de-DE', 'tr-TR') {
                @{ Culture = $culture; Name = 'the Kelvin sign'; Value = "cont$([char]0x212A)so"; Shown = 'cont\u212Aso' }
                @{ Culture = $culture; Name = 'a capital I with a dot above'; Value = "cont$([char]0x0130)so"; Shown = 'cont\u0130so' }
                @{ Culture = $culture; Name = 'a dotless i'; Value = "cont$([char]0x0131)so"; Shown = 'cont\u0131so' }
                @{ Culture = $culture; Name = 'a full-width letter'; Value = "cont$([char]0xFF4F)so"; Shown = 'cont\uFF4Fso' }
                @{ Culture = $culture; Name = 'a soft hyphen'; Value = "cont$([char]0xAD)oso"; Shown = 'cont\u00ADoso' }
                @{ Culture = $culture; Name = 'a zero-width space'; Value = "cont$([char]0x200B)oso"; Shown = 'cont\u200Boso' }
                @{ Culture = $culture; Name = 'an accented letter'; Value = 'contoso-é'; Shown = 'contoso-\u00E9' }
                @{ Culture = $culture; Name = 'a name of 64 characters'; Value = ('a' * 64); Shown = ('a' * 64) }
                @{ Culture = $culture; Name = 'a name that starts with a hyphen'; Value = '-contoso'; Shown = '-contoso' }
                @{ Culture = $culture; Name = 'a URL'; Value = 'https://contoso.sharepoint.com'; Shown = 'https://contoso.sharepoint.com' }
                @{ Culture = $culture; Name = 'a space inside'; Value = 'con toso'; Shown = 'con toso' }
            }
        ) {
            Invoke-UnderCulture -Culture $Culture -Action {
                $result = Resolve-TestValue -Name 'TenantName' -Value $Value

                $result.Value | Should -BeNullOrEmpty
                $result.Error | Should -BeLike 'must be letters, digits and hyphens only*not a URL (now: ''*'').'
                $result.Error | Should -BeLike "*(now: '$Shown')."
            }
        }

        It 'lowercases the name that it accepts, under <Culture>' -ForEach @(
            @{ Culture = 'en-US' }
            @{ Culture = 'tr-TR' }
        ) {
            $path = New-TestConfig -Body "@{ TenantName = 'KIWI-IKI'; ClientId = '11111111-2222-3333-4444-555555555555'; Scan = @{ SharePointUsageReport = 'usage.csv' } }"
            Set-Content -LiteralPath (Join-Path -Path (Split-Path -Path $path -Parent) -ChildPath 'usage.csv') -Value 'x'
            Invoke-UnderCulture -Culture $Culture -Action {
                $setting = Get-TestSetting -Path $path -Phase Scan

                $setting.TenantName | Should -BeExactly 'kiwi-iki'
                $setting.AdminUrl | Should -BeExactly 'https://kiwi-iki-admin.sharepoint.com'
            }
        }

        It 'refuses a Kelvin sign in the settings file, and does not read it as the letter k' {
            $path = New-TestConfig -Body "@{ TenantName = 'cont$([char]0x212A)so'; ClientId = '11111111-2222-3333-4444-555555555555' }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*TenantName*(now: ''cont\u212Aso'')*'
        }
    }

    Context 'RefusedTenants holds tenant names only' {
        It 'refuses the entry <Name>, which could never be the name of a tenant, and writes it so that it can be read' -ForEach @(
            @{ Name = 'with a Kelvin sign'; Value = "cont$([char]0x212A)so"; Shown = 'cont\u212Aso' }
            @{ Name = 'with a dotted capital I'; Value = "$([char]0x0130)stanbul"; Shown = '\u0130stanbul' }
            @{ Name = 'that is the address of a site'; Value = 'contoso.sharepoint.com'; Shown = 'contoso.sharepoint.com' }
            @{ Name = 'that is the address of the admin site'; Value = 'contoso-admin.sharepoint.com'; Shown = 'contoso-admin.sharepoint.com' }
            @{ Name = 'with a space'; Value = 'con toso'; Shown = 'con toso' }
            @{ Name = 'with a zero-width space'; Value = "con$([char]0x200B)toso"; Shown = 'con\u200Btoso' }
        ) {
            $result = Resolve-TestValue -Name 'RefusedTenants' -Value @('fabrikam', $Value)

            @($result.Value) | Should -HaveCount 0
            $result.Error | Should -BeLike 'has an entry that must be letters, digits and hyphens only*not a URL (now: ''*'').'
            $result.Error | Should -BeLike "*(now: '$Shown')."
        }

        It 'accepts a list of tenant names, in any case, and an empty list' {
            (Resolve-TestValue -Name 'RefusedTenants' -Value @('Fabrikam', 'KIWI-IKI', '1abc')).Error | Should -BeExactly ''
            (Resolve-TestValue -Name 'RefusedTenants' -Value @()).Error | Should -BeExactly ''
        }

        It 'stops the tool when the settings file lists an entry that is not a tenant name' {
            $path = New-TestConfig -Body "@{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; RefusedTenants = @('fabrikam', 'contoso.sharepoint.com') }"

            { Get-TestSetting -Path $path -Phase Scan } | Should -Throw -ExpectedMessage '*RefusedTenants*has an entry that must be*(now: ''contoso.sharepoint.com'')*'
        }
    }

    Context 'The names of the settings are compared one character at a time' {
        BeforeAll {
            $script:Hidden = [string][char]0x200B
            $script:Soft = [string][char]0xAD
        }

        BeforeEach {
            $script:Folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $script:Folder -ItemType Directory
            Set-Content -LiteralPath (Join-Path -Path $script:Folder -ChildPath 'usage.csv') -Value 'x'
            Set-Content -LiteralPath (Join-Path -Path $script:Folder -ChildPath 'lock.csv') -Value 'x'
            $script:Path = Join-Path -Path $script:Folder -ChildPath 'settings.psd1'
        }

        It 'stops on <Name>, and shows the hidden character, instead of dropping the setting without a word' -ForEach @(
            @{ Name = 'a shared setting with a zero-width space in its name'; Body = "@{{ TenantName = 'contosoprod'; ClientId = '11111111-2222-3333-4444-555555555555'; 'Refused{0}Tenants' = @('contosoprod'); Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Message = "*Unknown setting 'Refused\u200BTenants'*Did you mean 'RefusedTenants'*" }
            @{ Name = 'a shared setting with a soft hyphen in its name'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; 'Min{1}LockedDays' = 0; Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Message = "*Unknown setting 'Min\u00ADLockedDays'*Did you mean 'MinLockedDays'*" }
            @{ Name = 'a section with a zero-width space in its name'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; 'Sc{0}an' = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Message = "*Unknown setting 'Sc\u200Ban'*Did you mean 'Scan'*" }
            @{ Name = 'a setting of a section with a zero-width space in its name'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Scan = @{{ 'Inactive{0}Days' = 1; SharePointUsageReport = 'usage.csv' }} }}"; Message = "*Scan section: Unknown setting 'Inactive\u200BDays'*Did you mean 'InactiveDays'*" }
        ) {
            Set-Content -LiteralPath $script:Path -Value ($Body -f $script:Hidden, $script:Soft) -Encoding utf8

            { Get-TestSetting -Path $script:Path -Phase Scan } | Should -Throw -ExpectedMessage $Message
        }

        It 'still reads <Written> written in another case, under <Culture>' -ForEach @(
            foreach ($culture in 'en-US', 'tr-TR') {
                @{ Culture = $culture; Written = 'MINLOCKEDDAYS'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; MINLOCKEDDAYS = 10; Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Check = 'Shared' }
                @{ Culture = $culture; Written = 'minlockeddays'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; minlockeddays = 10; Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Check = 'Shared' }
                @{ Culture = $culture; Written = 'a section and a setting of it'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; scan = @{{ inactivedays = 10; sharepointusagereport = 'usage.csv' }} }}"; Check = 'Scan' }
                @{ Culture = $culture; Written = 'LOCKDATEFILES'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; LOCKDATEFILES = @('lock.csv'); Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Check = 'Files' }
            }
        ) {
            Set-Content -LiteralPath $script:Path -Value ($Body -f 0) -Encoding utf8
            Invoke-UnderCulture -Culture $Culture -Action {
                $s = Get-TestSetting -Path $script:Path -Phase Scan

                switch ($Check) {
                    'Shared' { $s.MinLockedDays | Should -Be 10 }
                    'Scan' { $s.Scan.InactiveDays | Should -Be 10 }
                    'Files' { @($s.LockDateFiles) | Should -HaveCount 1 }
                }
            }
        }

        It 'says where a setting belongs when it is written in another case in the wrong place: <Name>' -ForEach @(
            @{ Name = 'a shared setting in Scan'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; Scan = @{{ tenantname = 'x' }} }}"; Message = "*'TenantName' is a shared setting*" }
            @{ Name = 'an Act setting at the top'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; maxactions = 5 }}"; Message = "*'MaxActions' belongs in the Act section*" }
        ) {
            Set-Content -LiteralPath $script:Path -Value ($Body -f 0) -Encoding utf8

            { Get-TestSetting -Path $script:Path -Phase Scan } | Should -Throw -ExpectedMessage $Message
        }

        It 'reads a choice written in another case, and gives the spelling of the schema: <Written>' -ForEach @(
            @{ Written = 'culture'; Expected = 'Culture' }
            @{ Written = 'TAB'; Expected = 'Tab' }
            @{ Written = ' ; '; Expected = ';' }
        ) {
            $result = Resolve-TestValue -Name 'CsvDelimiter' -Value $Written

            $result.Error | Should -BeExactly ''
            $result.Value | Should -BeExactly $Expected
        }

        It 'refuses a value of a choice that has a hidden character, and shows it: <Name>' -ForEach @(
            @{ Name = 'a lock state'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; AcceptedLockStates = @('Read{1}Only'); Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Message = "*AcceptedLockStates*must hold values among: ReadOnly, Unlock (now: 'Read\u00ADOnly')*" }
            @{ Name = 'a separator'; Body = "@{{ TenantName = 'contoso'; ClientId = '11111111-2222-3333-4444-555555555555'; CsvDelimiter = 'Cult{0}ure'; Scan = @{{ SharePointUsageReport = 'usage.csv' }} }}"; Message = "*CsvDelimiter*must be one of*(now: 'Cult\u200Bure')*" }
        ) {
            Set-Content -LiteralPath $script:Path -Value ($Body -f $script:Hidden, $script:Soft) -Encoding utf8

            { Get-TestSetting -Path $script:Path -Phase Scan } | Should -Throw -ExpectedMessage $Message
        }

        It 'still reads a value of a choice in another case: <Value>' -ForEach @(
            @{ Value = 'readonly' }
            @{ Value = 'READONLY' }
        ) {
            $result = Resolve-TestValue -Name 'AcceptedLockStates' -Value @($Value)

            $result.Error | Should -BeExactly ''
            @($result.Value) | Should -Be @('ReadOnly')
        }
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
