BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
}

Describe 'Initialize-SPSLifecycleListingSummary' {
    It 'starts with nothing read, nothing resumed and no time' {
        $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

        $summary.PSObject.Properties.Name | Should -Be @(
            'Source', 'FallbackReason', 'Filter', 'PersonalSites', 'HomeSiteUrl', 'StartedOn', 'FinishedOn', 'ElapsedSeconds',
            'Resumed', 'StartReason', 'StartCode', 'PagesFromCheckpoint', 'SitesFromCheckpoint', 'PagesRead', 'SitesRead',
            'OneDriveDropped', 'DuplicatesDropped', 'SitesReturned', 'Retries', 'PageSecondsTotal', 'PageSecondsMax'
        )
        $summary.Source | Should -BeExactly ''
        $summary.FallbackReason | Should -BeExactly ''
        $summary.Filter | Should -BeExactly ''
        $summary.PersonalSites | Should -BeExactly ''
        $summary.HomeSiteUrl | Should -BeExactly ''
        $null -eq $summary.StartedOn | Should -BeTrue
        $null -eq $summary.FinishedOn | Should -BeTrue
        $summary.ElapsedSeconds | Should -Be 0
        $summary.Resumed | Should -BeFalse
        $summary.StartReason | Should -BeExactly ''
        $summary.StartCode | Should -BeExactly ''
        foreach ($name in 'PagesFromCheckpoint', 'SitesFromCheckpoint', 'PagesRead', 'SitesRead', 'OneDriveDropped', 'DuplicatesDropped', 'SitesReturned', 'Retries') {
            $summary.$name | Should -Be 0 -Because $name
            $summary.$name | Should -BeOfType [int]
        }

        $summary.PageSecondsTotal | Should -Be 0
        $summary.PageSecondsMax | Should -Be 0
    }

    It 'belongs to one run: each call gives a new object' {
        $first = & $script:Module { Initialize-SPSLifecycleListingSummary }
        $first.SitesRead = 5
        $second = & $script:Module { Initialize-SPSLifecycleListingSummary }

        $second.SitesRead | Should -Be 0
        [object]::ReferenceEquals($first, $second) | Should -BeFalse
    }
}
