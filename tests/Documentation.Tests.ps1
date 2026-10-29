BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
    $script:WikiFolder = Join-Path -Path $PSScriptRoot -ChildPath '../wiki'
}

Describe 'The generated wiki pages' {
    It 'has a committed <Name> page that matches the schema and the catalog' -ForEach @(
        @{ Name = 'Configuration'; Generator = 'Get-SPSLifecycleConfigurationPage' }
        @{ Name = 'Verdicts'; Generator = 'Get-SPSLifecycleVerdictPage' }
    ) {
        $path = Join-Path -Path $script:WikiFolder -ChildPath "$Name.md"
        Test-Path -LiteralPath $path | Should -BeTrue -Because "wiki/$Name.md must exist: run tools/Update-Documentation.ps1"

        $committed = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        $generated = & $script:Module { param($g) & $g } $Generator

        $committed | Should -BeExactly $generated -Because "wiki/$Name.md is out of date: run tools/Update-Documentation.ps1 and commit the result"
    }

    It 'documents every setting of the schema' {
        $page = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath 'Configuration.md') -Raw
        foreach ($row in @(& $script:Module { Get-SPSLifecycleSettingSchema })) {
            $page | Should -Match ([regex]::Escape("``$($row.Name)``")) -Because "the page must document $($row.Name)"
        }
    }

    It 'documents every verdict of the catalog' {
        $page = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath 'Verdicts.md') -Raw
        foreach ($row in @(& $script:Module { Get-SPSLifecycleVerdictCatalog })) {
            $page | Should -Match ([regex]::Escape("``$($row.Verdict)``")) -Because "the page must document $($row.Verdict)"
        }
    }

    It 'is linked from the sidebar and the home page' {
        foreach ($file in '_Sidebar.md', 'Home.md') {
            $text = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath $file) -Raw
            $text | Should -Match 'Configuration' -Because "$file must link to the Configuration page"
            $text | Should -Match 'Verdicts' -Because "$file must link to the Verdicts page"
        }
    }
}
