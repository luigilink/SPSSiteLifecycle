BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ScanFixture.ps1')

    function script:Invoke-TestScan {
        param($Run, [string]$ConfigFile = '')

        if (-not $ConfigFile) { $ConfigFile = $Run.Config }
        $summary = Invoke-SPSLifecycleScan -ConfigFile $ConfigFile -Now $script:Now -InformationAction SilentlyContinue -InformationVariable info
        [PSCustomObject]@{ Summary = $summary; Text = @($info | ForEach-Object { "$($_.MessageData)" }) }
    }

    function script:Read-RunReport {
        param([string]$Path)
        @(Import-Csv -LiteralPath $Path)
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Invoke-SPSLifecycleScan' {
    BeforeEach {
        Set-ScanStub
    }

    AfterEach {
        Clear-ModuleStub
    }

    Context 'The report' {
        It 'writes one row for each site that the Scan reads, with its verdict, in the output folder of the settings' {
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            $result.Summary.ReportPath | Should -BeExactly (Join-Path -Path $run.Reports -ChildPath 'sites-20261030T090000Z.csv')
            $rows = Read-RunReport -Path $result.Summary.ReportPath
            $rows | Should -HaveCount 5
            @($rows.Url) | Should -Be @(1..5 | ForEach-Object { "https://contoso.sharepoint.com/sites/site$_" })
            @($rows.Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-SITE', 'ARCHIVE', 'SKIP-RECENT-ACTIVITY', 'SKIP-PROTECTED')
            @($rows.SuggestedAction) | Should -Be @('Delete', 'Delete', 'Archive', '', '')
            @($rows.Decision | Where-Object { $_ }) | Should -HaveCount 0
            @($rows.GeneratedOn | Select-Object -Unique) | Should -Be @('20261030T090000Z')
        }

        It 'writes the columns of the report in their order' {
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            $header = (Get-Content -LiteralPath $result.Summary.ReportPath -TotalCount 1).TrimStart([char]0xFEFF)
            $header | Should -BeExactly ((& $script:Module { Get-SPSLifecycleReportColumn } | ForEach-Object { $_.Name }) -join ',')
        }

        It 'writes the delimiter that the settings ask for' {
            $run = New-RunFolder -Delimiter ';'

            $result = Invoke-TestScan -Run $run

            (Get-Content -LiteralPath $result.Summary.ReportPath -TotalCount 1) | Should -BeLike '*Url;Verdict;SuggestedAction;Decision;*'
        }

        It 'reads the dates of the reports and of the lock date lists in the formats of the settings, and stops when a date is in another one' {
            $header = 'Report Refresh Date,Site Id,Site URL,Owner Display Name,Is Deleted,Last Activity Date,Root Web Template,Report Period'
            $rows = foreach ($index in 1..5) {
                $id = '{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index
                $last = if ($index -eq 4) { '01/10/2026' } else { '10/01/2025' }
                "29/10/2026,$id,https://contoso.sharepoint.com/sites/site$index,Owner,False,$last,Group,180"
            }
            $usage = $header + "`r`n" + ($rows -join "`r`n") + "`r`n"
            $lockRows = foreach ($index in 1..5) { "https://contoso.sharepoint.com/sites/site$index,18/09/2025,$('{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index)" }
            $locks = "Url,LockedOn,SiteId`r`n" + ($lockRows -join "`r`n") + "`r`n"

            $with = New-RunFolder -Settings "CsvDateFormats = @('dd/MM/yyyy')" -Usage $usage -Locks $locks
            $result = Invoke-TestScan -Run $with

            @((Read-RunReport -Path $result.Summary.ReportPath).Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-SITE', 'ARCHIVE', 'SKIP-RECENT-ACTIVITY', 'SKIP-PROTECTED')

            $without = New-RunFolder -Usage $usage -Locks $locks
            { Invoke-TestScan -Run $without } | Should -Throw -ExpectedMessage '*CsvDateFormats*'
        }

        It 'protects the home site that the tenant gives, and no other site' {
            & $script:Module { $script:StubData.HomeSite = 'https://contoso.sharepoint.com/sites/site1' }
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            $rows = Read-RunReport -Path $result.Summary.ReportPath
            @($rows.Verdict) | Should -Be @('SKIP-PROTECTED', 'DELETE-SITE', 'ARCHIVE', 'SKIP-RECENT-ACTIVITY', 'DELETE-VIA-GROUP')
        }

        It 'protects nothing as the home site when the tenant has none' {
            & $script:Module { $script:StubData.HomeSite = '' }
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            @((Read-RunReport -Path $result.Summary.ReportPath).Verdict) | Should -Be @('DELETE-VIA-GROUP', 'DELETE-SITE', 'ARCHIVE', 'SKIP-RECENT-ACTIVITY', 'DELETE-VIA-GROUP')
        }

        It 'uses the Teams activity report when it is given: a team that was active is not suggested' {
            $teams = "Report Refresh Date,Team Name,Team Id,Last Activity Date,Report Period`r`n2026-10-29,Sales,00000001-1111-4111-8111-000000000001,2026-10-20,180`r`n"
            $run = New-RunFolder -Teams $teams

            $result = Invoke-TestScan -Run $run

            @((Read-RunReport -Path $result.Summary.ReportPath).Verdict)[0] | Should -BeExactly 'SKIP-RECENT-ACTIVITY'
            @($result.Summary.ActivityReports) | Should -Be @('SharePoint', 'Teams')
        }

        It 'writes a report with the header only when the tenant has no site in the lock states that were asked for' {
            & $script:Module { $script:StubData.Pages = @(, @()) }
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            @(Read-RunReport -Path $result.Summary.ReportPath) | Should -HaveCount 0
            (Get-Content -LiteralPath $result.Summary.ReportPath -TotalCount 1) | Should -BeLike '*Url,Verdict*'
            $result.Summary.Scan.SitesListed | Should -Be 0
        }
    }

    Context 'The summary of the run' {
        It 'counts what was read, left out and suggested, and says how the listing went' {
            $run = New-RunFolder

            $summary = (Invoke-TestScan -Run $run).Summary

            $summary.Phase | Should -BeExactly 'Scan'
            $summary.TenantName | Should -BeExactly 'contoso'
            $summary.StartedOn | Should -Be $script:Now
            $summary.ElapsedSeconds | Should -BeGreaterOrEqual 0
            $summary.Scan.SitesRead | Should -Be 5
            $summary.Scan.SitesListed | Should -Be 5
            $summary.Scan.ByAction['Delete'] | Should -Be 2
            $summary.Scan.ByAction['Archive'] | Should -Be 1
            $summary.Scan.ByAction['None'] | Should -Be 2
            $summary.Scan.ByVerdict['SKIP-PROTECTED'] | Should -Be 1
            $summary.Listing.Source | Should -BeExactly 'Csom'
            $summary.Listing.PagesRead | Should -Be 2
            $summary.Listing.SitesRead | Should -Be 6
            $summary.Listing.OneDriveDropped | Should -Be 1
            $summary.Listing.SitesReturned | Should -Be 5
            @($summary.ActivityReports) | Should -Be @('SharePoint')
        }

        It 'tells the same in words, and where the report is, as information' {
            $run = New-RunFolder

            $result = Invoke-TestScan -Run $run

            $result.Text | Should -Contain "Report: $($result.Summary.ReportPath)"
            $result.Text[0] | Should -BeLike "Scan of the tenant contoso ended in *. It only reads: nothing was changed in the tenant."
            ($result.Text -join "`n") | Should -BeLike '*Suggested actions: Delete 2, Archive 1, Lock 0, nothing 2.*'
        }

        It 'gives a summary that belongs to this run, and not to an earlier one' {
            $first = (Invoke-TestScan -Run (New-RunFolder)).Summary
            $second = (Invoke-TestScan -Run (New-RunFolder)).Summary

            [object]::ReferenceEquals($first.Scan, $second.Scan) | Should -BeFalse
            [object]::ReferenceEquals($first.Listing, $second.Listing) | Should -BeFalse
            $second.Scan.SitesListed | Should -Be 5
        }
    }

    Context 'It only reads' {
        It 'asks the tenant for the home site and the sites, and for nothing else, and ends the session' {
            $run = New-RunFolder

            $null = Invoke-TestScan -Run $run

            Get-StubLog | Should -Be @('open', 'home site', 'api checked', 'page start=[]', 'page start=[t1]', 'close')
        }
    }

    Context 'What stops it, and when' {
        It 'stops before the sign-in when a setting is wrong: <Name>' -ForEach @(
            @{ Name = 'a tenant that is refused'; Settings = "RefusedTenants = @('contoso')" }
            @{ Name = 'a setting that does not exist'; Settings = 'NoSuchSetting = 1' }
        ) {
            $run = New-RunFolder -Settings $Settings

            { Invoke-TestScan -Run $run } | Should -Throw

            Get-StubLog | Should -HaveCount 0
            Test-Path -LiteralPath $run.Reports | Should -BeFalse
        }

        It 'stops before the sign-in when the settings file is not there' {
            { Invoke-SPSLifecycleScan -ConfigFile (Join-Path -Path $TestDrive -ChildPath 'no-such-file.psd1') -Now $script:Now } | Should -Throw -ExpectedMessage '*no-such-file*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before the sign-in when an activity report cannot be used, and names it' {
            $run = New-RunFolder -Usage "Site Id,Site URL`r`n"

            { Invoke-TestScan -Run $run } | Should -Throw -ExpectedMessage '*usage.csv*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before the sign-in when a lock date list cannot be used' {
            $run = New-RunFolder
            Set-Content -LiteralPath (Join-Path -Path $run.Folder -ChildPath 'lot1.csv') -Value "Nothing,Useful`r`n"

            { Invoke-TestScan -Run $run } | Should -Throw -ExpectedMessage '*lot1.csv*'

            Get-StubLog | Should -HaveCount 0
        }

        It 'stops before the first page, and ends the session, when the home site cannot be read' {
            & $script:Module { $script:StubData.HomeSiteFails = 'The home site of the tenant could not be read: Access denied.' }
            $run = New-RunFolder

            { Invoke-TestScan -Run $run } | Should -Throw -ExpectedMessage '*home site*could not be read*'

            Get-StubLog | Should -Be @('open', 'home site', 'close')
            @(Get-ChildItem -LiteralPath $run.Reports -Filter 'sites-*' -ErrorAction SilentlyContinue) | Should -HaveCount 0
        }

        It 'leaves no report that looks complete when the listing fails half-way, and takes the listing up when it is run again' {
            $run = New-RunFolder
            & $script:Module { $script:StubData.FailAt = 't1' }

            { Invoke-TestScan -Run $run } | Should -Throw -ExpectedMessage '*page 2*'

            @(Get-ChildItem -LiteralPath $run.Reports -File | Where-Object { $_.Name -like 'sites-*' }) | Should -HaveCount 0
            & $script:Module { $script:StubData.FailAt = $null; $script:StubLog.Clear() }

            $result = Invoke-TestScan -Run $run

            $result.Summary.Listing.Resumed | Should -BeTrue
            (Read-RunReport -Path $result.Summary.ReportPath) | Should -HaveCount 5
            (Get-StubLog | Where-Object { $_ -like 'page*' }) | Should -Be @('page start=[t1]')
            ($result.Text -join "`n") | Should -BeLike '*an interrupted listing was taken up*'
        }

        It 'does not replace a report that exists' {
            $run = New-RunFolder
            $null = New-Item -Path $run.Reports -ItemType Directory
            Set-Content -LiteralPath (Join-Path -Path $run.Reports -ChildPath 'sites-20261030T090000Z.csv') -Value 'reviewed'

            { Invoke-TestScan -Run $run } | Should -Throw -ExpectedMessage '*already exists*'

            Get-Content -LiteralPath (Join-Path -Path $run.Reports -ChildPath 'sites-20261030T090000Z.csv') | Should -BeExactly 'reviewed'
            Get-StubLog | Should -HaveCount 0
        }
    }
}

Describe 'Format-SPSLifecycleScanSummary' {
    BeforeAll {
        function script:New-RunSummaryObject {
            param([hashtable]$Listing = @{}, [hashtable]$Scan = @{}, [double]$Elapsed = 125.4, [string]$Path = '/reports/sites-20261030T090000Z.csv')

            $listingValues = [ordered]@{
                Source = 'Csom'; FallbackReason = ''; Resumed = $false; StartReason = ''; PagesFromCheckpoint = 0; SitesFromCheckpoint = 0
                PagesRead = 17; SitesRead = 25123; OneDriveDropped = 7; DuplicatesDropped = 0; SitesReturned = 25116; Retries = 0
            }
            foreach ($key in $Listing.Keys) { $listingValues[$key] = $Listing[$key] }
            $scanValues = [ordered]@{
                SitesRead = 25116; SitesListed = 1223; LeftOutOneDrive = 3; LeftOutLockState = 23890
                ByVerdict = @{ 'DELETE-SITE' = 12; 'ARCHIVE' = 3; 'SKIP-NO-LOCK-DATE' = 1200; 'SKIP-RECENT-ACTIVITY' = 8 }
                ByAction = @{ Delete = 12; Archive = 3; None = 1208 }
            }
            foreach ($key in $Scan.Keys) { $scanValues[$key] = $Scan[$key] }

            [PSCustomObject][ordered]@{
                Phase = 'Scan'; TenantName = 'contoso'; ElapsedSeconds = $Elapsed; ReportPath = $Path
                ActivityReports = @('SharePoint'); Scan = [PSCustomObject]$scanValues; Listing = [PSCustomObject]$listingValues
            }
        }

        function script:Format-TestSummary {
            param($Summary)
            @(& $script:Module { param($s) Format-SPSLifecycleScanSummary -Summary $s } $Summary)
        }
    }

    It 'tells the run in a few lines, with the numbers written the same way whatever the culture' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject)

        $lines | Should -Be @(
            'Scan of the tenant contoso ended in 2 min 5 s. It only reads: nothing was changed in the tenant.'
            'Listing: the paged call of the SharePoint admin API; 17 pages and 25,123 sites read from the tenant; left out by the listing: 7 OneDrive sites, 0 sites that came twice; 0 pages asked again.'
            'Sites in the report: 1,223. Left out by the Scan: 3 for a OneDrive address or an address that SharePoint does not give, 23,890 for a lock state that the settings do not list.'
            'Suggested actions: Delete 12, Archive 3, Lock 0, nothing 1,208.'
            'Verdicts: SKIP-NO-LOCK-DATE 1,200, DELETE-SITE 12, SKIP-RECENT-ACTIVITY 8, ARCHIVE 3.'
            'Report: /reports/sites-20261030T090000Z.csv'
            'Next: review the report. Decision is empty on every row: a person fills it in (Delete, Archive or Lock) before the Act phase reads the file.'
        )
    }

    It 'writes the same numbers under another culture' {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
            $lines = Format-TestSummary -Summary (New-RunSummaryObject -Elapsed 3.26)
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }

        $lines[0] | Should -BeExactly 'Scan of the tenant contoso ended in 3.2 s. It only reads: nothing was changed in the tenant.'
        $lines[1] | Should -BeLike '*25,123 sites*'
    }

    It 'writes the time as <Expected>' -ForEach @(
        @{ Elapsed = 0.04; Expected = '0.0 s' }
        @{ Elapsed = 59.94; Expected = '59.9 s' }
        @{ Elapsed = 60.0; Expected = '1 min 0 s' }
        @{ Elapsed = 3599.9; Expected = '59 min 59 s' }
        @{ Elapsed = 3600.0; Expected = '1 h 0 min 0 s' }
        @{ Elapsed = 7384.2; Expected = '2 h 3 min 4 s' }
    ) {
        (Format-TestSummary -Summary (New-RunSummaryObject -Elapsed $Elapsed))[0] | Should -BeExactly "Scan of the tenant contoso ended in $Expected. It only reads: nothing was changed in the tenant."
    }

    It 'says that the cmdlet was used, and why' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ Source = 'Cmdlet'; FallbackReason = 'This PnP.PowerShell has no paged call.' })

        $lines[1] | Should -BeLike 'Listing: Get-PnPTenantSite (the paged call cannot be used: This PnP.PowerShell has no paged call); *'
    }

    It 'says that the cmdlet was asked for when no reason is given' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ Source = 'Cmdlet' })

        $lines[1] | Should -BeLike 'Listing: Get-PnPTenantSite (as it was asked); *'
    }

    It 'says that an interrupted listing was taken up, and what came from its checkpoint' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ Resumed = $true; PagesFromCheckpoint = 12; SitesFromCheckpoint = 17999; PagesRead = 5; SitesRead = 7124 })

        $lines | Should -Contain 'Checkpoint: an interrupted listing was taken up: 12 pages (17,999 sites) came from its checkpoint.'
        $lines[1] | Should -BeLike '*5 pages and 7,124 sites read from the tenant*'
    }

    It 'says why a checkpoint was not taken up, when there was one' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ StartReason = 'The checkpoint was made with another filter.' })

        $lines | Should -Contain 'Checkpoint: not taken up: The checkpoint was made with another filter.'
    }

    It 'says nothing of a checkpoint when there was none' {
        (Format-TestSummary -Summary (New-RunSummaryObject)) | Should -Not -BeLike 'Checkpoint*'
    }

    It 'says how many pages were asked again' {
        (Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ Retries = 3 }))[1] | Should -BeLike '*; 3 pages asked again.'
    }

    It 'writes a singular for one: <Name>' -ForEach @(
        @{ Name = 'a page and a site'; Listing = @{ PagesRead = 1; SitesRead = 1 }; Expected = '*; 1 page and 1 site read from the tenant; *' }
        @{ Name = 'a OneDrive site left out'; Listing = @{ OneDriveDropped = 1 }; Expected = '*left out by the listing: 1 OneDrive site, *' }
        @{ Name = 'a site that came twice'; Listing = @{ DuplicatesDropped = 1 }; Expected = '*, 1 site that came twice; *' }
        @{ Name = 'a page asked again'; Listing = @{ Retries = 1 }; Expected = '*; 1 page asked again.' }
    ) {
        (Format-TestSummary -Summary (New-RunSummaryObject -Listing $Listing))[1] | Should -BeLike $Expected
    }

    It 'writes a singular for one page and one site of a checkpoint' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Listing @{ Resumed = $true; PagesFromCheckpoint = 1; SitesFromCheckpoint = 1 })

        $lines | Should -Contain 'Checkpoint: an interrupted listing was taken up: 1 page (1 site) came from its checkpoint.'
    }

    It 'says so, and does not send the person on to the review, when the report holds no site' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Scan @{ SitesListed = 0; ByVerdict = @{}; ByAction = @{} })

        $lines | Should -Contain 'Verdicts: none.'
        $lines | Should -Contain 'Suggested actions: Delete 0, Archive 0, Lock 0, nothing 0.'
        $lines | Should -Contain 'The report holds no site: check Scan.LockStates and the lock states of the sites.'
        @($lines | Where-Object { $_ -like 'Next:*' }) | Should -HaveCount 0
        @($lines | Where-Object { $_ -like 'Report:*' }) | Should -HaveCount 1
    }

    It 'sorts the verdicts by their count and then by their name, whatever the order of the table' {
        $lines = Format-TestSummary -Summary (New-RunSummaryObject -Scan @{ ByVerdict = @{ 'B' = 2; 'A' = 2; 'C' = 5; 'a-lower' = 2 } })

        ($lines | Where-Object { $_ -like 'Verdicts:*' }) | Should -BeExactly 'Verdicts: C 5, A 2, B 2, a-lower 2.'
    }
}
