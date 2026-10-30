BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
    $script:WikiFolder = Join-Path -Path $PSScriptRoot -ChildPath '../wiki'
}

Describe 'The generated wiki pages' {
    It 'has a committed <Name> page that matches the schema and the catalog' -ForEach @(
        @{ Name = 'Configuration'; Generator = 'Get-SPSLifecycleConfigurationPage' }
        @{ Name = 'Verdicts'; Generator = 'Get-SPSLifecycleVerdictPage' }
        @{ Name = 'Report'; Generator = 'Get-SPSLifecycleReportPage' }
        @{ Name = 'App-Registration'; Generator = 'Get-SPSLifecycleAppRegistrationPage' }
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

    It 'documents every column of the report' {
        $page = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath 'Report.md') -Raw
        foreach ($column in @(& $script:Module { Get-SPSLifecycleReportColumn })) {
            $page | Should -Match ([regex]::Escape("``$($column.Name)``")) -Because "the page must document the column $($column.Name)"
        }
    }

    It 'writes the columns in the order that D10 of the design decisions lists them' {
        $design = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath 'Design-Decisions.md')
        $line = @($design | Where-Object { $_ -match '^- \*\*Columns:\*\*' })
        $line | Should -HaveCount 1 -Because 'D10 must list the columns on one line that starts with "- **Columns:**"'

        $named = @([System.Text.RegularExpressions.Regex]::Matches($line[0], '`([A-Za-z]+)`') | ForEach-Object { $_.Groups[1].Value })
        $coded = @(& $script:Module { Get-SPSLifecycleReportColumn } | ForEach-Object { $_.Name })

        ($coded -join ',') | Should -BeExactly ($named -join ',') -Because 'the table of the report columns and D10 must say the same thing'
    }

    It 'is linked from the sidebar and the home page' {
        foreach ($file in '_Sidebar.md', 'Home.md') {
            $text = Get-Content -LiteralPath (Join-Path -Path $script:WikiFolder -ChildPath $file) -Raw
            $text | Should -Match 'Configuration' -Because "$file must link to the Configuration page"
            $text | Should -Match 'Verdicts' -Because "$file must link to the Verdicts page"
            $text | Should -Match 'Report' -Because "$file must link to the Report page"
            $text | Should -Match 'App-Registration' -Because "$file must link to the App-Registration page"
        }
    }
}
