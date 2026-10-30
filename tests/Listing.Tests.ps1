BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:Filter = "LockState -eq 'ReadOnly'"
    $script:Options = 'Source=Csom;PersonalSites=Excluded'
    $script:Columns = @('Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified')

    function script:New-TestFolder {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $folder
    }

    function script:New-TestRecord {
        param([int]$Index = 1, [hashtable]$Override = @{})

        $values = [ordered]@{
            Url                     = "https://contoso.sharepoint.com/sites/site$Index"
            SiteId                  = '{0:x8}-0000-4000-8000-{1:x12}' -f $Index, $Index
            Title                   = "Site $Index"
            Template                = 'GROUP#0'
            LockState               = 'ReadOnly'
            GroupId                 = '{0:x8}-1111-4111-8111-{1:x12}' -f $Index, $Index
            IsHubSite               = $false
            IsTeamsConnected        = $true
            IsTeamsChannelConnected = $false
            ArchiveStatus           = 'NotArchived'
            StorageUsedMB           = [long](10 + $Index)
            LastContentModified     = [System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc).AddTicks($Index)
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    # Pages of made-up sites: Sizes gives the number of sites of each page, and the sites are numbered from 1 across the pages.
    function script:New-TestPages {
        param([int[]]$Sizes)

        $number = 0
        $pages = [System.Collections.Generic.List[System.Object]]::new()
        foreach ($size in $Sizes) {
            $records = [System.Collections.Generic.List[System.Object]]::new()
            for ($i = 0; $i -lt $size; $i++) {
                $number++
                $records.Add((New-TestRecord -Index $number))
            }

            $pages.Add($records.ToArray())
        }

        , $pages.ToArray()
    }

    # A source of pages. The page n (from 0) is asked with the token '' for the first and tn for the others, and gives tn+1 as
    # the token of the next one, or none after the last. Failures says how many times a token fails before it works.
    function script:New-TestSource {
        param($Pages, $Calls, [hashtable]$Failures = @{})

        {
            param([string]$StartIndex)
            $Calls.Add($StartIndex)
            if ($Failures.ContainsKey($StartIndex) -and $Failures[$StartIndex] -gt 0) {
                $Failures[$StartIndex] = $Failures[$StartIndex] - 1
                throw 'The server did not answer.'
            }

            $index = if ($StartIndex -eq '') { 0 } else { [int]$StartIndex.Substring(1) }
            $next = if ($index + 1 -lt $Pages.Count) { 't' + ($index + 1) } else { '' }
            [PSCustomObject]@{ Items = @($Pages[$index]); NextStartIndex = $next }
        }.GetNewClosure()
    }

    function script:Invoke-TestListing {
        param(
            [scriptblock]$Source,
            [string]$Folder,
            $Summary = $null,
            [string]$Tenant = 'contoso',
            [string]$Filter = $script:Filter,
            [string]$Options = $script:Options,
            $Now = $script:Now,
            [switch]$Restart,
            [scriptblock]$OnProgress = $null,
            [int]$PageAttempts = 3,
            [int]$MaxPages = 100000
        )

        if ($null -eq $Summary) {
            $Summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
        }

        $parameters = @{
            PageSource = $Source; CheckpointFolder = $Folder; Tenant = $Tenant; Filter = $Filter; Options = $Options
            Summary = $Summary; Now = $Now; RetryDelaySeconds = 0; PageAttempts = $PageAttempts; MaxPages = $MaxPages
        }
        if ($Restart) {
            $parameters.Restart = $true
        }

        if ($null -ne $OnProgress) {
            $parameters.OnProgress = $OnProgress
        }

        $result = & $script:Module {
            param($p)
            $records = @(Invoke-SPSLifecycleSiteListing @p -WarningVariable warnings -WarningAction SilentlyContinue)
            [PSCustomObject]@{ Records = $records; Warnings = @($warnings | ForEach-Object { "$_" }) }
        } $parameters

        [PSCustomObject]@{ Records = $result.Records; Warnings = $result.Warnings; Summary = $Summary }
    }

    # What a record is, to the tick and the type, as text.
    function script:Get-TestRecordKey {
        param($Record)
        (@($script:Columns | ForEach-Object {
                    $value = $Record.$_
                    if ($null -eq $value) { "$_=<null>" }
                    elseif ($value -is [System.DateTime]) { "$_=$($value.Ticks):$($value.Kind)" }
                    else { "$_=$value`:$($value.GetType().Name)" }
                }) -join '|')
    }

    function script:Get-TestFiles {
        param([string]$Folder)
        @(Get-ChildItem -LiteralPath $Folder -Name | Sort-Object)
    }
}

Describe 'Invoke-SPSLifecycleSiteListing' {
    Context 'A listing from the first page to the last' {
        It 'gives the sites of every page, in order, asking each page with the token of the one before' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = New-TestPages -Sizes 3, 2, 4

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $calls | Should -Be @('', 't1', 't2')
            $result.Records | Should -HaveCount 9
            ($result.Records | ForEach-Object { $_.Title }) | Should -Be @(1..9 | ForEach-Object { "Site $_" })
            $result.Warnings | Should -HaveCount 0
        }

        It 'gives the records of the page source as they are' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = New-TestPages -Sizes 2

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            Get-TestRecordKey -Record $result.Records[0] | Should -BeExactly (Get-TestRecordKey -Record $pages[0][0])
            Get-TestRecordKey -Record $result.Records[1] | Should -BeExactly (Get-TestRecordKey -Record $pages[0][1])
        }

        It 'counts and times what it did in the summary' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = New-TestPages -Sizes 3, 2, 4

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder
            $summary = $result.Summary

            $summary.PagesRead | Should -Be 3
            $summary.SitesRead | Should -Be 9
            $summary.SitesReturned | Should -Be 9
            $summary.PagesFromCheckpoint | Should -Be 0
            $summary.SitesFromCheckpoint | Should -Be 0
            $summary.Resumed | Should -BeFalse
            $summary.StartReason | Should -BeExactly ''
            $summary.OneDriveDropped | Should -Be 0
            $summary.DuplicatesDropped | Should -Be 0
            $summary.Retries | Should -Be 0
            $summary.Filter | Should -BeExactly $script:Filter
            $summary.StartedOn | Should -Be $script:Now
            $summary.FinishedOn | Should -BeGreaterOrEqual $script:Now
            $summary.ElapsedSeconds | Should -BeGreaterOrEqual 0
            $summary.PageSecondsTotal | Should -BeGreaterOrEqual 0
            $summary.PageSecondsMax | Should -BeLessOrEqual $summary.PageSecondsTotal
        }

        It 'leaves a manifest that says the listing finished, and no page, when it is over' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()

            $null = Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 3, 2) -Calls $calls) -Folder $folder

            Get-TestFiles -Folder $folder | Should -Be @('listing.lock', 'manifest.json')
            $json = Get-Content -LiteralPath (Join-Path $folder 'manifest.json') -Raw | ConvertFrom-Json
            $json.State | Should -BeExactly 'Completed'
            $json.ListingComplete | Should -BeTrue
        }

        It 'saves each page before it gives its sites, and does not ask for the next page before they are taken' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $source = New-TestSource -Pages (New-TestPages -Sizes 2, 2, 2) -Calls $calls
            $seen = [System.Collections.Generic.List[string]]::new()
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

            & $script:Module {
                param($s, $f, $sum, $now, $o, $log, $folderPath)
                Invoke-SPSLifecycleSiteListing -PageSource $s -CheckpointFolder $f -Tenant 'contoso' -Filter $o.Filter -Options $o.Options -Summary $sum -Now $now -RetryDelaySeconds 0 |
                    ForEach-Object { $log.Add(('{0}|calls={1}|files={2}' -f $_.Title, $o.Calls.Count, ((Get-ChildItem -LiteralPath $folderPath -Name | Where-Object { $_ -like 'page-*' } | Sort-Object) -join ','))) }
            } $source $folder $summary $script:Now @{ Filter = $script:Filter; Options = $script:Options; Calls = $calls } $seen $folder

            $seen | Should -Be @(
                'Site 1|calls=1|files=page-000001.csv'
                'Site 2|calls=1|files=page-000001.csv'
                'Site 3|calls=2|files=page-000001.csv,page-000002.csv'
                'Site 4|calls=2|files=page-000001.csv,page-000002.csv'
                'Site 5|calls=3|files=page-000001.csv,page-000002.csv,page-000003.csv'
                'Site 6|calls=3|files=page-000001.csv,page-000002.csv,page-000003.csv'
            )
        }

        It 'lists a tenant of no site: one empty page' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()

            $result = Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 0) -Calls $calls) -Folder $folder

            $result.Records | Should -HaveCount 0
            $result.Summary.PagesRead | Should -Be 1
            $result.Summary.SitesReturned | Should -Be 0
        }

        It 'goes on through pages that are empty, as a filter makes them' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()

            $result = Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 0, 0, 2, 0, 1, 0) -Calls $calls) -Folder $folder

            $result.Records | Should -HaveCount 3
            $result.Summary.PagesRead | Should -Be 6
            $calls | Should -HaveCount 6
        }

        It 'does not change the type of a text that looks like something else' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = , @((New-TestRecord -Index 1 -Override @{ Title = '2026-10-14' }))

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $result.Records[0].Title | Should -BeOfType [string]
            $result.Records[0].Title | Should -BeExactly '2026-10-14'
        }
    }

    Context 'The sites that it drops' {
        It 'drops the OneDrive sites that the call gave although it was asked not to, and counts them' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = , @(
                (New-TestRecord -Index 1)
                (New-TestRecord -Index 2 -Override @{ Template = 'SPSPERS#10'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com' })
                (New-TestRecord -Index 3 -Override @{ Url = 'https://contoso-my.sharepoint.com/personal/b_contoso_com' })
                (New-TestRecord -Index 4)
            )

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            ($result.Records | ForEach-Object { $_.Title }) | Should -Be @('Site 1', 'Site 4')
            $result.Summary.OneDriveDropped | Should -Be 2
            $result.Summary.SitesRead | Should -Be 4
            $result.Summary.SitesReturned | Should -Be 2
        }

        It 'drops a site whose address is not in the form that SharePoint gives, as the Scan core does' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = , @((New-TestRecord -Index 1), (New-TestRecord -Index 2 -Override @{ Url = 'http://contoso.sharepoint.com/sites/site2' }))

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $result.Records | Should -HaveCount 1
            $result.Summary.OneDriveDropped | Should -Be 1
        }

        It 'does not keep a dropped site in the checkpoint' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = New-TestPages -Sizes 3, 3
            $pages[0][1].Template = 'SPSPERS#10'

            $failing = New-TestSource -Pages $pages -Calls $calls -Failures @{ t1 = 99 }
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source $failing -Folder $folder -Summary $summary } | Should -Throw

            $state = & $script:Module { param($f, $n) Read-SPSLifecycleListingCheckpoint -Folder $f -Tenant 'contoso' -Filter "LockState -eq 'ReadOnly'" -Options 'Source=Csom;PersonalSites=Excluded' -Now $n } $folder $script:Now
            $state.Usable | Should -BeTrue
            $state.Manifest.Pages[0].Read | Should -Be 3
            $state.Manifest.Pages[0].Sites | Should -Be 2
        }

        It 'keeps a site that has no address, so that the Scan core says what is wrong with it' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = , @((New-TestRecord -Index 1 -Override @{ Url = '' }))

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $result.Records | Should -HaveCount 1
            $result.Summary.OneDriveDropped | Should -Be 0
        }

        It 'gives a site once when the tenant gives it twice, in the same page or in two, and counts the second' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $pages = @(
                , @((New-TestRecord -Index 1), (New-TestRecord -Index 2), (New-TestRecord -Index 2 -Override @{ Title = 'Site 2 again' }))
                , @((New-TestRecord -Index 1 -Override @{ Title = 'Site 1 again' }), (New-TestRecord -Index 3))
            )

            $result = Invoke-TestListing -Source (New-TestSource -Pages @($pages[0], $pages[1]) -Calls $calls) -Folder $folder

            ($result.Records | ForEach-Object { $_.Title }) | Should -Be @('Site 1', 'Site 2', 'Site 3')
            $result.Summary.DuplicatesDropped | Should -Be 2
            $result.Summary.SitesRead | Should -Be 5
        }
    }

    Context 'A page that cannot be read' {
        It 'asks the page again when it fails, and goes on: <Failures> failure(s)' -ForEach @(
            @{ Failures = 1 }
            @{ Failures = 2 }
        ) {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $source = New-TestSource -Pages (New-TestPages -Sizes 2, 2) -Calls $calls -Failures @{ t1 = $Failures }

            $result = Invoke-TestListing -Source $source -Folder $folder

            $result.Records | Should -HaveCount 4
            $result.Summary.Retries | Should -Be $Failures
            @($calls | Where-Object { $_ -eq 't1' }) | Should -HaveCount ($Failures + 1)
        }

        It 'stops when a page fails every time, and says which page, how many times and why' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $source = New-TestSource -Pages (New-TestPages -Sizes 2, 2, 2) -Calls $calls -Failures @{ t2 = 99 }
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

            { Invoke-TestListing -Source $source -Folder $folder -Summary $summary } | Should -Throw -ExpectedMessage '*page 3*3 attempts*did not answer*'

            @($calls | Where-Object { $_ -eq 't2' }) | Should -HaveCount 3
            $summary.Retries | Should -Be 2
            $summary.PagesRead | Should -Be 2
        }

        It 'does not ask again when it is told to try once' {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $source = New-TestSource -Pages (New-TestPages -Sizes 2, 2) -Calls $calls -Failures @{ t1 = 1 }

            { Invoke-TestListing -Source $source -Folder $folder -PageAttempts 1 } | Should -Throw -ExpectedMessage '*1 attempt*'

            @($calls | Where-Object { $_ -eq 't1' }) | Should -HaveCount 1
        }

        It 'stops when the source gives no page, which is a defect and not a failure to retry: <Name>' -ForEach @(
            @{ Name = 'nothing'; Body = { param($s) $null } }
            @{ Name = 'a page without sites'; Body = { param($s) [PSCustomObject]@{ NextStartIndex = '' } } }
        ) {
            $folder = New-TestFolder
            $calls = [System.Collections.Generic.List[string]]::new()
            $counter = $calls
            $source = { param([string]$StartIndex) $counter.Add($StartIndex); & $Body $StartIndex }.GetNewClosure()

            { Invoke-TestListing -Source $source -Folder $folder } | Should -Throw -ExpectedMessage '*no page*'

            $calls | Should -HaveCount 1
        }
    }

    Context 'A listing that does not end' {
        It 'stops when the next token is one that was already asked: <Name>' -ForEach @(
            @{ Name = 'the same token'; Tokens = @('', 'a', 'a') }
            @{ Name = 'a token of two pages ago'; Tokens = @('', 'a', 'b', 'a') }
        ) {
            $folder = New-TestFolder
            $order = $Tokens
            $source = {
                param([string]$StartIndex)
                $at = [System.Array]::IndexOf($order, $StartIndex)
                [PSCustomObject]@{ Items = @(); NextStartIndex = $order[$at + 1] }
            }.GetNewClosure()

            { Invoke-TestListing -Source $source -Folder $folder } | Should -Throw -ExpectedMessage '*does not advance*'
        }

        It 'stops after the number of pages that it is allowed' {
            $folder = New-TestFolder
            $source = { param([string]$StartIndex) [PSCustomObject]@{ Items = @(); NextStartIndex = [guid]::NewGuid().ToString() } }

            { Invoke-TestListing -Source $source -Folder $folder -MaxPages 5 } | Should -Throw -ExpectedMessage '*5 pages*'
        }
    }

    Context 'A listing that was interrupted' {
        It 'is taken up where it stopped: the saved pages first, then only the pages that are missing' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4, 1
            $firstCalls = [System.Collections.Generic.List[string]]::new()
            $firstSummary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $firstCalls -Failures @{ t2 = 99 }) -Folder $folder -Summary $firstSummary } | Should -Throw

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $calls | Should -Be @('t2', 't3')
            ($result.Records | ForEach-Object { $_.Title }) | Should -Be @(1..10 | ForEach-Object { "Site $_" })
            $result.Summary.Resumed | Should -BeTrue
            $result.Summary.PagesFromCheckpoint | Should -Be 2
            $result.Summary.SitesFromCheckpoint | Should -Be 5
            $result.Summary.PagesRead | Should -Be 2
            $result.Summary.SitesRead | Should -Be 5
            $result.Summary.SitesReturned | Should -Be 10
            $result.Summary.StartReason | Should -BeExactly ''
            $result.Warnings | Should -HaveCount 0
            Get-TestFiles -Folder $folder | Should -Be @('listing.lock', 'manifest.json')
        }

        It 'gives the same records after a resume as it would without one, to the tick and the type' {
            $pages = New-TestPages -Sizes 3, 2, 4
            $plainFolder = New-TestFolder
            $plain = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $plainFolder

            $folder = New-TestFolder
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw
            $resumed = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder

            $resumed.Summary.Resumed | Should -BeTrue
            $resumed.Records | Should -HaveCount $plain.Records.Count
            for ($i = 0; $i -lt $plain.Records.Count; $i++) {
                Get-TestRecordKey -Record $resumed.Records[$i] | Should -BeExactly (Get-TestRecordKey -Record $plain.Records[$i])
            }
        }

        It 'is taken up when every page was read and the run stopped before it said so' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 2, 2
            $firstCalls = [System.Collections.Generic.List[string]]::new()
            $failAtTheEnd = { param($progress) if ($progress.Pages -ge 2) { throw 'The report cannot be written.' } }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $firstCalls) -Folder $folder -OnProgress $failAtTheEnd } | Should -Throw -ExpectedMessage '*report*'

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $calls | Should -HaveCount 0
            $result.Records | Should -HaveCount 4
            $result.Summary.Resumed | Should -BeTrue
            $result.Summary.PagesRead | Should -Be 0
            Get-TestFiles -Folder $folder | Should -Be @('listing.lock', 'manifest.json')
        }

        It 'is taken up when the one who reads the sites stopped early' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 2, 2, 2
            $firstCalls = [System.Collections.Generic.List[string]]::new()
            $source = New-TestSource -Pages $pages -Calls $firstCalls
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

            $some = @(& $script:Module {
                    param($s, $f, $sum, $now)
                    Invoke-SPSLifecycleSiteListing -PageSource $s -CheckpointFolder $f -Tenant 'contoso' -Filter "LockState -eq 'ReadOnly'" -Options 'Source=Csom;PersonalSites=Excluded' -Summary $sum -Now $now -RetryDelaySeconds 0 | Select-Object -First 3
                } $source $folder $summary $script:Now)
            $some | Should -HaveCount 3

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $result.Records | Should -HaveCount 6
            $result.Summary.Resumed | Should -BeTrue
            $calls | Should -Be @('t2')
        }

        It 'starts again, and says why, when <Name>' -ForEach @(
            @{ Name = 'the filter changed'; Run = @{ Filter = "LockState -eq 'Unlock'" }; Expected = '*filter*'; Warn = $true }
            @{ Name = 'the filter was dropped'; Run = @{ Filter = '' }; Expected = '*filter*'; Warn = $true }
            @{ Name = 'the tenant is another'; Run = @{ Tenant = 'fabrikam' }; Expected = '*tenant*'; Warn = $true }
            @{ Name = 'the way the sites are asked changed'; Run = @{ Options = 'Source=Cmdlet' }; Expected = '*asked*'; Warn = $true }
            @{ Name = 'the checkpoint is older than 24 hours'; Run = @{ Hours = 25 }; Expected = '*24 hours*'; Warn = $true }
        ) {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $firstSummary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $firstSummary } | Should -Throw

            $parameters = @{ Folder = $folder }
            foreach ($key in $Run.Keys) {
                if ($key -eq 'Hours') { $parameters.Now = $script:Now.AddHours($Run.Hours) } else { $parameters[$key] = $Run[$key] }
            }

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) @parameters

            $calls | Should -Be @('', 't1', 't2')
            $result.Records | Should -HaveCount 9
            $result.Summary.Resumed | Should -BeFalse
            $result.Summary.PagesFromCheckpoint | Should -Be 0
            $result.Summary.StartReason | Should -BeLike $Expected
            $result.Warnings | Should -HaveCount 1
            $result.Warnings[0] | Should -BeLike $Expected
        }

        It 'takes up a checkpoint that is exactly 24 hours old' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw

            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder -Now $script:Now.AddHours(24)

            $result.Summary.Resumed | Should -BeTrue
        }

        It 'starts again, and says that a page is damaged, when a page of the checkpoint was changed' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw
            Add-Content -LiteralPath (Join-Path $folder 'page-000001.csv') -Value 'x' -NoNewline

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $calls | Should -Be @('', 't1', 't2')
            $result.Records | Should -HaveCount 9
            $result.Summary.StartReason | Should -BeLike '*damaged*page 1*'
            $result.Warnings | Should -HaveCount 1
        }

        It 'starts again, and does not call it a problem, when the previous listing finished' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2
            $null = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder

            $calls | Should -Be @('', 't1')
            $result.Summary.Resumed | Should -BeFalse
            $result.Summary.StartReason | Should -BeLike '*finished*'
            $result.Warnings | Should -HaveCount 0
        }

        It 'starts again, and says that it was asked to, with Restart, and removes the old pages' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw

            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls $calls) -Folder $folder -Restart

            $calls | Should -Be @('', 't1', 't2')
            $result.Summary.Resumed | Should -BeFalse
            $result.Summary.StartReason | Should -BeLike '*Restart*'
            Get-TestFiles -Folder $folder | Should -Be @('listing.lock', 'manifest.json')
        }

        It 'does not take up pages of a listing that started again: the new run numbers its pages from 1' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw

            $failing = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 1, 1) -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t1 = 99 }) -Folder $folder -Summary $failing -Filter '' } | Should -Throw

            Get-TestFiles -Folder $folder | Should -Be @('listing.lock', 'manifest.json', 'page-000001.csv')
        }
    }

    Context 'One run at a time' {
        It 'refuses to run while another run holds the checkpoint' {
            $folder = New-TestFolder
            $lock = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
            try {
                $calls = [System.Collections.Generic.List[string]]::new()

                { Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 2) -Calls $calls) -Folder $folder } | Should -Throw -ExpectedMessage '*another*'

                $calls | Should -HaveCount 0
            }
            finally {
                $lock.Dispose()
            }
        }

        It 'gives the lock back when it ends, whether it finished or failed' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 2, 2
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t1 = 99 }) -Folder $folder -Summary $summary } | Should -Throw
            $afterFailure = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
            $afterFailure.Dispose()

            $null = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder
            $afterSuccess = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
            $afterSuccess.Dispose()
        }
    }

    Context 'The progress' {
        It 'tells what was done after each page' {
            $folder = New-TestFolder
            $log = [System.Collections.Generic.List[object]]::new()
            $onProgress = { param($progress) $log.Add($progress) }.GetNewClosure()

            $null = Invoke-TestListing -Source (New-TestSource -Pages (New-TestPages -Sizes 3, 2, 4) -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder -OnProgress $onProgress

            $log | Should -HaveCount 3
            ($log | ForEach-Object { $_.Pages }) | Should -Be @(1, 2, 3)
            ($log | ForEach-Object { $_.SitesReturned }) | Should -Be @(3, 5, 9)
            ($log | ForEach-Object { $_.FromCheckpoint }) | Should -Be @($false, $false, $false)
            $log[2].ElapsedSeconds | Should -BeGreaterOrEqual 0
            $log[2].SitesPerSecond | Should -BeGreaterOrEqual 0
            $log[2].PageSeconds | Should -BeGreaterOrEqual 0
        }

        It 'tells the pages that it took from the checkpoint, and says so' {
            $folder = New-TestFolder
            $pages = New-TestPages -Sizes 3, 2, 4
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t2 = 99 }) -Folder $folder -Summary $summary } | Should -Throw
            $log = [System.Collections.Generic.List[object]]::new()
            $onProgress = { param($progress) $log.Add($progress) }.GetNewClosure()

            $null = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder -OnProgress $onProgress

            ($log | ForEach-Object { '{0}:{1}:{2}' -f $_.Pages, $_.SitesReturned, $_.FromCheckpoint }) | Should -Be @('1:3:True', '2:5:True', '3:9:False')
        }
    }

    Context 'The culture of the machine' {
        It 'gives the same sites after a resume under <Culture>' -ForEach @(
            @{ Culture = 'en-US' }
            @{ Culture = 'fr-FR' }
            @{ Culture = 'tr-TR' }
        ) {
            $previous = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                $folder = New-TestFolder
                $pages = New-TestPages -Sizes 2, 2
                $pages[0][0].Title = 'Ilık İşler 1.5'
                $pages[0][0].StorageUsedMB = [long]1234567
                $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
                { Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new()) -Failures @{ t1 = 99 }) -Folder $folder -Summary $summary } | Should -Throw

                $result = Invoke-TestListing -Source (New-TestSource -Pages $pages -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder

                $result.Summary.Resumed | Should -BeTrue
                $result.Records[0].Title | Should -BeExactly 'Ilık İşler 1.5'
                $result.Records[0].StorageUsedMB | Should -Be 1234567
                $result.Records[0].LastContentModified.Ticks | Should -Be $pages[0][0].LastContentModified.Ticks
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }
        }
    }

    Context 'Size' {
        # The pages of a listing of made-up sites, and the checkpoint that goes with them. On Windows, PowerShell copies the string
        # arguments of every .NET method call into a log message for AMSI (D9), so a function that gave a whole page, or the
        # whole checkpoint, to a method for each site would be quadratic there: this test runs two sizes and compares the times.
        It 'lists and takes up a large listing in a time that grows with its size' -Tag 'Slow' {
            $measure = {
                param([int]$Pages)
                $folder = New-TestFolder
                $sizes = @(for ($i = 0; $i -lt $Pages; $i++) { 1500 })
                $pageData = New-TestPages -Sizes $sizes
                $firstCalls = [System.Collections.Generic.List[string]]::new()
                $half = [int]($Pages / 2)
                $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                $caught = $false
                try { $null = Invoke-TestListing -Source (New-TestSource -Pages $pageData -Calls $firstCalls -Failures @{ "t$half" = 99 }) -Folder $folder -Summary $summary } catch { $caught = $true }
                $first = $watch.Elapsed.TotalSeconds
                $watch.Restart()
                $result = Invoke-TestListing -Source (New-TestSource -Pages $pageData -Calls ([System.Collections.Generic.List[string]]::new())) -Folder $folder
                [PSCustomObject]@{ Caught = $caught; First = $first; Second = $watch.Elapsed.TotalSeconds; Result = $result; Expected = $Pages * 1500 }
            }

            $null = & $measure 2
            $small = & $measure 4
            $large = & $measure 16

            $large.Caught | Should -BeTrue
            $large.Result.Records | Should -HaveCount $large.Expected
            $large.Result.Summary.SitesReturned | Should -Be $large.Expected
            $large.Result.Summary.Resumed | Should -BeTrue
            ($large.First + $large.Second) | Should -BeLessThan 120
            (($large.First + $large.Second) / ($small.First + $small.Second)) | Should -BeLessThan 10
        }
    }
}
