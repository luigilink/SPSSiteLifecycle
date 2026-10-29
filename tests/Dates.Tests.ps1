BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
}

Describe 'ConvertTo-SPSLifecycleDate' {
    Context 'ISO 8601 dates, whatever the culture' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        BeforeEach {
            $script:PreviousCulture = [System.Globalization.CultureInfo]::CurrentCulture
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
        }

        AfterEach {
            [System.Globalization.CultureInfo]::CurrentCulture = $script:PreviousCulture
        }

        It 'reads <Text> as <Expected> UTC' -ForEach @(
            @{ Text = '2026-10-28'; Expected = '2026-10-28T00:00:00' }
            @{ Text = '2026-10-28T16:30:00Z'; Expected = '2026-10-28T16:30:00' }
            @{ Text = '2026-10-28T18:30:00+02:00'; Expected = '2026-10-28T16:30:00' }
            @{ Text = '2026-10-28 16:30'; Expected = '2026-10-28T16:30:00' }
            @{ Text = '2026-10-28T16:30:00.1234567Z'; Expected = '2026-10-28T16:30:00' }
            @{ Text = '20261028'; Expected = '2026-10-28T00:00:00' }
            @{ Text = '20261028T163000Z'; Expected = '2026-10-28T16:30:00' }
            @{ Text = '  2026-10-28  '; Expected = '2026-10-28T00:00:00' }
        ) {
            $date = & $script:Module { param($t) ConvertTo-SPSLifecycleDate -Text $t } $Text

            $date.ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be $Expected
            $date.Kind | Should -Be 'Utc'
        }

        It 'never guesses an ambiguous date: <Text> is refused without a format' -ForEach @(
            @{ Text = '03/04/2026' }
            @{ Text = '28/10/2026' }
            @{ Text = '10/28/2026' }
            @{ Text = '28.10.2026' }
            @{ Text = 'October 28, 2026' }
        ) {
            { & $script:Module { param($t) ConvertTo-SPSLifecycleDate -Text $t } $Text } | Should -Throw -ExpectedMessage '*CsvDateFormats*'
        }

        It 'reads 03/04/2026 with the format dd/MM/yyyy, as the 3rd of April, not with the culture' {
            $date = & $script:Module { ConvertTo-SPSLifecycleDate -Text '03/04/2026' -DateFormat 'dd/MM/yyyy' }

            $date.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be '2026-04-03'
        }
    }

    Context 'Empty values' {
        It 'gives $null for <Name>' -ForEach @(
            @{ Name = 'an empty text'; Text = '' }
            @{ Name = 'spaces'; Text = '   ' }
            @{ Name = 'a null'; Text = $null }
        ) {
            & $script:Module { param($t) ConvertTo-SPSLifecycleDate -Text $t } $Text | Should -BeNullOrEmpty
        }
    }

    Context 'Extra formats' {
        It 'tries the formats in order' {
            $date = & $script:Module { ConvertTo-SPSLifecycleDate -Text '28-10-2026' -DateFormat @('dd/MM/yyyy', 'dd-MM-yyyy') }

            $date.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be '2026-10-28'
        }

        It 'accepts the date patterns of the current culture when the format is Culture' {
            $previous = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
                $date = & $script:Module { ConvertTo-SPSLifecycleDate -Text '28/10/2026' -DateFormat 'Culture' }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }

            $date.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) | Should -Be '2026-10-28'
        }

        It 'names the value and the setting when the date cannot be read' {
            { & $script:Module { ConvertTo-SPSLifecycleDate -Text '2026-13-45' -DateFormat 'dd/MM/yyyy' } } | Should -Throw -ExpectedMessage "*'2026-13-45'*CsvDateFormats*'dd/MM/yyyy'*"
        }
    }
}
