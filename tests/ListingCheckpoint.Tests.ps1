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

    # A site record, as ConvertTo-SPSLifecycleSiteRecord gives it.
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

    function script:Save-TestPage {
        param($Folder, $Manifest, [int]$From = 1, [int]$Count = 3, [string]$Token = '', [string]$NextToken = 'next-1', $Records = $null)
        $recordList = @(if ($null -ne $Records) { $Records } else { $From..($From + $Count - 1) | ForEach-Object { New-TestRecord -Index $_ } })
        & $script:Module {
            param($f, $m, $r, $t, $n, $now)
            Save-SPSLifecycleListingPage -Folder $f -Manifest $m -Record $r -Token $t -NextToken $n -Read $r.Count -Seconds 2.5 -Now $now
        } $Folder $Manifest $recordList $Token $NextToken $script:Now
    }

    function script:New-TestManifest {
        param([string]$Tenant = 'contoso', $Now = $script:Now)
        & $script:Module { param($t, $f, $o, $n) Initialize-SPSLifecycleListingManifest -Tenant $t -Filter $f -Options $o -Now $n } $Tenant $script:Filter $script:Options $Now
    }

    function script:Read-TestCheckpoint {
        param($Folder, [string]$Tenant = 'contoso', [string]$Filter = $script:Filter, [string]$Options = $script:Options, $Now = $script:Now)
        & $script:Module { param($f, $t, $fl, $o, $n) Read-SPSLifecycleListingCheckpoint -Folder $f -Tenant $t -Filter $fl -Options $o -Now $n } $Folder $Tenant $Filter $Options $Now
    }

    function script:Edit-TestFile {
        param([string]$Path, [string]$Pattern, [string]$Replacement)
        $text = [System.IO.File]::ReadAllText($Path)
        $changed = [regex]::Replace($text, $Pattern, $Replacement)
        if ($changed -ceq $text) {
            throw "The pattern '$Pattern' was not found in '$Path'."
        }

        [System.IO.File]::WriteAllText($Path, $changed, [System.Text.UTF8Encoding]::new($false))
    }
}

Describe 'Open-SPSLifecycleListingLock' {
    It 'creates the folder and holds the lock until it is disposed' {
        $folder = Join-Path -Path (New-TestFolder) -ChildPath 'checkpoint'

        $lock = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
        try {
            Test-Path -LiteralPath $folder -PathType Container | Should -BeTrue
            $lock | Should -BeOfType [System.IO.FileStream]
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'refuses a second run while the first holds it, and says so' {
        $folder = New-TestFolder
        $first = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
        try {
            { & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder } | Should -Throw -ExpectedMessage '*another*'
        }
        finally {
            $first.Dispose()
        }
    }

    It 'gives the lock again once the first run is over, even if it did not finish' {
        $folder = New-TestFolder
        $first = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
        $first.Dispose()

        $second = & $script:Module { param($f) Open-SPSLifecycleListingLock -Folder $f } $folder
        $second.Dispose()
    }
}

Describe 'The pages of a checkpoint' {
    It 'gives back the records that were saved, with the same values and the same types' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $records = @(1..3 | ForEach-Object { New-TestRecord -Index $_ })
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records $records

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $back | Should -HaveCount 3
        for ($i = 0; $i -lt 3; $i++) {
            $back[$i].PSObject.Properties.Name | Should -Be $script:Columns
            foreach ($name in $script:Columns) {
                $expected = $records[$i].$name
                $actual = $back[$i].$name
                if ($expected -is [System.DateTime]) {
                    $actual | Should -BeOfType [System.DateTime]
                    $actual.Kind | Should -Be ([System.DateTimeKind]::Utc)
                    $actual.Ticks | Should -Be $expected.Ticks -Because "$name of record $i"
                }
                elseif ($expected -is [bool]) {
                    $actual | Should -BeOfType [bool]
                    $actual | Should -Be $expected -Because "$name of record $i"
                }
                elseif ($expected -is [long]) {
                    $actual | Should -BeOfType [long]
                    $actual | Should -Be $expected -Because "$name of record $i"
                }
                else {
                    $actual | Should -BeOfType [string]
                    $actual | Should -BeExactly $expected -Because "$name of record $i"
                }
            }
        }
    }

    It 'keeps a text that a format could change: <Name>' -ForEach @(
        @{ Name = 'a comma and a quote'; Title = 'Sales, "EMEA"' }
        @{ Name = 'a semicolon and a tab'; Title = "a;b`tc" }
        @{ Name = 'a line break'; Title = "line 1`r`nline 2`nline 3" }
        @{ Name = 'spaces around it'; Title = '  padded  ' }
        @{ Name = 'accents'; Title = "L'équipe Éléphant" }
        @{ Name = 'a character outside the basic plane'; Title = "Team $([char]::ConvertFromUtf32(0x1F680))" }
        @{ Name = 'a text that looks like a date'; Title = '2026-10-14' }
        @{ Name = 'a text that looks like a date and a time'; Title = '2026-10-14T10:05:58Z' }
        @{ Name = 'a text that looks like a number'; Title = '0012' }
        @{ Name = 'a text that looks like a boolean'; Title = 'True' }
        @{ Name = 'a formula'; Title = '=SUM(A1:A2)' }
        @{ Name = 'an empty title'; Title = '' }
        @{ Name = 'two double quotes'; Title = '""' }
    ) {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @((New-TestRecord -Index 1 -Override @{ Title = $Title }), (New-TestRecord -Index 2))

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $back | Should -HaveCount 2
        $back[0].Title | Should -BeOfType [string]
        $back[0].Title | Should -BeExactly $Title
        $back[1].Title | Should -BeExactly 'Site 2'
    }

    It 'keeps an unknown size and an unknown date unknown, and a size of zero a size of zero' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @(
            (New-TestRecord -Index 1 -Override @{ StorageUsedMB = $null; LastContentModified = $null })
            (New-TestRecord -Index 2 -Override @{ StorageUsedMB = [long]0 })
        )

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $null -eq $back[0].StorageUsedMB | Should -BeTrue
        $null -eq $back[0].LastContentModified | Should -BeTrue
        $null -eq $back[1].StorageUsedMB | Should -BeFalse
        $back[1].StorageUsedMB | Should -Be 0
    }

    It 'reads a size that is larger than an integer of 32 bits' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @((New-TestRecord -Index 1 -Override @{ StorageUsedMB = [long]5000000000 }))

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $back[0].StorageUsedMB | Should -Be 5000000000
    }

    It 'saves a page that holds no site, which a filter makes common' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @() -NextToken 'next-1'

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $back | Should -HaveCount 0
        $entry.Sites | Should -Be 0
        $manifest.Pages | Should -HaveCount 1
    }

    It 'does not depend on the culture of the machine: <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
        @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $record = New-TestRecord -Index 1 -Override @{ StorageUsedMB = [long]1234567; Title = 'Ilık İşler 1.5' }
            $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @($record)

            $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

            $back[0].StorageUsedMB | Should -Be 1234567
            $back[0].Title | Should -BeExactly 'Ilık İşler 1.5'
            $back[0].LastContentModified.Ticks | Should -Be $record.LastContentModified.Ticks
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }

    It 'numbers the pages from 1 and writes each one with a six-digit name, next to the manifest' {
        $folder = New-TestFolder
        $manifest = New-TestManifest

        $first = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -Token '' -NextToken 'next-1'
        $second = Save-TestPage -Folder $folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken 'next-2'

        $first.Number | Should -Be 1
        $first.File | Should -BeExactly 'page-000001.csv'
        $second.Number | Should -Be 2
        $second.File | Should -BeExactly 'page-000002.csv'
        (Get-ChildItem -LiteralPath $folder -Name | Sort-Object) | Should -Be @('manifest.json', 'page-000001.csv', 'page-000002.csv')
        $manifest.NextToken | Should -BeExactly 'next-2'
        $manifest.ListingComplete | Should -BeFalse
    }

    It 'says that the listing is complete when the last page has no next token' {
        $folder = New-TestFolder
        $manifest = New-TestManifest

        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken ''

        $manifest.ListingComplete | Should -BeTrue
        $manifest.NextToken | Should -BeExactly ''
    }

    It 'records what the page cost: the sites that were read, kept, the time and a hash of the file' {
        $folder = New-TestFolder
        $manifest = New-TestManifest

        $entry = & $script:Module {
            param($f, $m, $r, $n)
            Save-SPSLifecycleListingPage -Folder $f -Manifest $m -Record $r -Token '' -NextToken 'next-1' -Read 1500 -Seconds 2.35 -Now $n
        } $folder $manifest @((New-TestRecord -Index 1)) $script:Now

        $entry.Read | Should -Be 1500
        $entry.Sites | Should -Be 1
        $entry.Seconds | Should -Be 2.35
        $entry.Sha256 | Should -Match '^[0-9a-f]{64}$'
        $entry.Sha256 | Should -BeExactly ((Get-FileHash -LiteralPath (Join-Path $folder 'page-000001.csv') -Algorithm SHA256).Hash.ToLowerInvariant())
    }

    It 'leaves no partial file behind' {
        $folder = New-TestFolder
        $manifest = New-TestManifest

        $null = Save-TestPage -Folder $folder -Manifest $manifest

        @(Get-ChildItem -LiteralPath $folder -Filter '*.partial') | Should -HaveCount 0
    }
}

Describe 'Read-SPSLifecycleListingCheckpoint' {
    Context 'A checkpoint that can be taken up' {
        It 'is one that a run left after its pages, for the same tenant and filter, with intact pages' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
            $null = Save-TestPage -Folder $folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken 'next-2'

            $state = Read-TestCheckpoint -Folder $folder

            $state.Exists | Should -BeTrue
            $state.Usable | Should -BeTrue
            $state.Reason | Should -BeExactly ''
            $state.Manifest.Pages | Should -HaveCount 2
            $state.Manifest.NextToken | Should -BeExactly 'next-2'
            $state.Manifest.ListingComplete | Should -BeFalse
            $state.Manifest.State | Should -BeExactly 'Running'
        }

        It 'is not changed by the case of the tenant name' {
            $folder = New-TestFolder
            $manifest = New-TestManifest -Tenant 'Contoso'
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder -Tenant 'contoso').Usable | Should -BeTrue
        }

        It 'can be taken up and added to: the manifest that it gives takes more pages' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
            $resumed = (Read-TestCheckpoint -Folder $folder).Manifest

            $null = Save-TestPage -Folder $folder -Manifest $resumed -From 4 -Token 'next-1' -NextToken ''

            $again = Read-TestCheckpoint -Folder $folder
            $again.Usable | Should -BeTrue
            $again.Manifest.Pages | Should -HaveCount 2
            $again.Manifest.ListingComplete | Should -BeTrue
        }

        It 'is still good at exactly 24 hours, and not a second later' {
            $folder = New-TestFolder
            $manifest = New-TestManifest -Now $script:Now.AddHours(-24)
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder).Usable | Should -BeTrue

            $late = Read-TestCheckpoint -Folder $folder -Now $script:Now.AddSeconds(1)
            $late.Usable | Should -BeFalse
            $late.Exists | Should -BeTrue
            $late.Reason | Should -BeLike '*24 hours*'
        }

        It 'counts the age from the start of the listing, not from the last page, because the first pages are the oldest' {
            $folder = New-TestFolder
            $manifest = New-TestManifest -Now $script:Now.AddHours(-30)
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder).Usable | Should -BeFalse
        }
    }

    Context 'A checkpoint that is not taken up' {
        It 'is nothing when there is none: <Name>' -ForEach @(
            @{ Name = 'the folder does not exist'; Make = { Join-Path -Path (New-TestFolder) -ChildPath 'missing' } }
            @{ Name = 'the folder is empty'; Make = { New-TestFolder } }
        ) {
            $folder = & $Make

            $state = Read-TestCheckpoint -Folder $folder

            $state.Exists | Should -BeFalse
            $state.Usable | Should -BeFalse
            $state.Finished | Should -BeFalse
            $state.Reason | Should -BeExactly ''
        }

        It 'is refused, with its reason, when <Name>' -ForEach @(
            @{ Name = 'it is for another tenant'; Tenant = 'fabrikam'; Filter = "LockState -eq 'ReadOnly'"; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*tenant*' }
            @{ Name = 'the filter changed'; Tenant = 'contoso'; Filter = "LockState -eq 'Unlock'"; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*filter*' }
            @{ Name = 'the filter was removed'; Tenant = 'contoso'; Filter = ''; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*filter*' }
            @{ Name = 'the way the sites are asked changed'; Tenant = 'contoso'; Filter = "LockState -eq 'ReadOnly'"; Options = 'Source=Cmdlet'; Expected = '*asked*' }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            $state = Read-TestCheckpoint -Folder $folder -Tenant $Tenant -Filter $Filter -Options $Options

            $state.Exists | Should -BeTrue
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike $Expected
            $null -eq $state.Manifest | Should -BeTrue
        }

        It 'is refused when the filter differs only by the case: the server reads it as written' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder -Filter "lockstate -eq 'readonly'").Usable | Should -BeFalse
        }

        It 'is refused when the run that wrote it finished: a listing is not reused to answer a new Scan' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest -NextToken ''
            & $script:Module { param($f, $m, $n) Complete-SPSLifecycleListingCheckpoint -Folder $f -Manifest $m -Now $n } $folder $manifest $script:Now

            $state = Read-TestCheckpoint -Folder $folder

            $state.Exists | Should -BeTrue
            $state.Usable | Should -BeFalse
            $state.Finished | Should -BeTrue
            $state.Reason | Should -BeLike '*finished*'
        }

        It 'is refused when it is dated in the future, which a clock that was set back can do' {
            $folder = New-TestFolder
            $manifest = New-TestManifest -Now $script:Now.AddHours(2)
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            $state = Read-TestCheckpoint -Folder $folder

            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*future*'
        }
    }

    Context 'A checkpoint that is damaged' {
        BeforeEach {
            $script:Folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $script:Folder -Manifest $manifest -From 1 -NextToken 'next-1'
            $null = Save-TestPage -Folder $script:Folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken 'next-2'
            $script:ManifestPath = Join-Path -Path $script:Folder -ChildPath 'manifest.json'
        }

        It 'is read as it was written, before the damage (control)' {
            (Read-TestCheckpoint -Folder $script:Folder).Usable | Should -BeTrue
        }

        It 'is refused when the manifest is not JSON' {
            Set-Content -LiteralPath $script:ManifestPath -Value '{ not json' -Encoding utf8NoBOM

            $state = Read-TestCheckpoint -Folder $script:Folder

            $state.Exists | Should -BeTrue
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the manifest is empty' {
            Set-Content -LiteralPath $script:ManifestPath -Value '' -Encoding utf8NoBOM

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the manifest is a JSON value that is not an object: <Name>' -ForEach @(
            @{ Name = 'an array'; Text = '[1, 2]' }
            @{ Name = 'a number'; Text = '42' }
            @{ Name = 'null'; Text = 'null' }
        ) {
            Set-Content -LiteralPath $script:ManifestPath -Value $Text -Encoding utf8NoBOM

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when it was written by another version of the tool' {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"Version":\s*1' -Replacement '"Version": 2'

            $state = Read-TestCheckpoint -Folder $script:Folder

            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*version*'
        }

        It 'is refused when the manifest has a property that it should not have' {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"Version":\s*1,' -Replacement '"Version": 1, "Extra": "x",'

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the manifest lacks the property <Name>' -ForEach @(
            @{ Name = 'Tenant' }
            @{ Name = 'Filter' }
            @{ Name = 'Options' }
            @{ Name = 'StartedOn' }
            @{ Name = 'NextToken' }
            @{ Name = 'Pages' }
        ) {
            $json = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
            $json.PSObject.Properties.Remove($Name)
            Set-Content -LiteralPath $script:ManifestPath -Value (ConvertTo-Json -InputObject $json -Depth 5) -Encoding utf8NoBOM

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when a value has the wrong type: <Name>' -ForEach @(
            @{ Name = 'a tenant that is a number'; Pattern = '"Tenant":\s*"contoso"'; Replacement = '"Tenant": 5' }
            @{ Name = 'a state that is not known'; Pattern = '"State":\s*"Running"'; Replacement = '"State": "Paused"' }
            @{ Name = 'a start that is not a date'; Pattern = '"StartedOn":\s*"[^"]*"'; Replacement = '"StartedOn": "yesterday"' }
            @{ Name = 'a start that is a date that JSON readers convert'; Pattern = '"StartedOn":\s*"[^"]*"'; Replacement = '"StartedOn": "2026-10-30T09:00:00Z"' }
            @{ Name = 'a flag that is a text'; Pattern = '"ListingComplete":\s*false'; Replacement = '"ListingComplete": "no"' }
            @{ Name = 'a page count that is negative'; Pattern = '"Sites":\s*3,'; Replacement = '"Sites": -3,' }
            @{ Name = 'a page that read fewer sites than it kept'; Pattern = '"Read":\s*3,'; Replacement = '"Read": 1,' }
        ) {
            Edit-TestFile -Path $script:ManifestPath -Pattern $Pattern -Replacement $Replacement

            $state = Read-TestCheckpoint -Folder $script:Folder
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the manifest says that the listing is complete and still gives a token' {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"ListingComplete":\s*false' -Replacement '"ListingComplete": true'

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the manifest has pages and no token to go on with, and the listing is not complete' {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"NextToken":\s*"next-2"' -Replacement '"NextToken": ""'

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when the pages are not numbered 1, 2, 3 without a gap' {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"Number":\s*2' -Replacement '"Number": 3'

            (Read-TestCheckpoint -Folder $script:Folder).Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when a page file is named so that it leaves the folder: <Name>' -ForEach @(
            @{ Name = 'a parent folder'; File = '../page-000001.csv' }
            @{ Name = 'a backslash'; File = '..\\page-000001.csv' }
            @{ Name = 'an absolute path'; File = '/etc/passwd' }
            @{ Name = 'another name'; File = 'manifest.json' }
        ) {
            Edit-TestFile -Path $script:ManifestPath -Pattern '"File":\s*"page-000001.csv"' -Replacement ('"File": "{0}"' -f $File)

            $state = Read-TestCheckpoint -Folder $script:Folder
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*damaged*'
        }

        It 'is refused when a page file is missing, and names the page' {
            Remove-Item -LiteralPath (Join-Path $script:Folder 'page-000002.csv')

            $state = Read-TestCheckpoint -Folder $script:Folder

            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*page 2*'
        }

        It 'is refused when a page file was changed, even by one character, and names the page' {
            Add-Content -LiteralPath (Join-Path $script:Folder 'page-000001.csv') -Value ' ' -NoNewline

            $state = Read-TestCheckpoint -Folder $script:Folder

            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*page 1*'
        }

        It 'is refused when a page file was replaced by another of the same length' {
            $path = Join-Path $script:Folder 'page-000001.csv'
            $text = [System.IO.File]::ReadAllText($path)
            $other = $text.Replace('site1', 'siteX')
            $other.Length | Should -Be $text.Length
            [System.IO.File]::WriteAllText($path, $other, [System.Text.UTF8Encoding]::new($false))

            (Read-TestCheckpoint -Folder $script:Folder).Usable | Should -BeFalse
        }

        It 'ignores a partial file that a run that was killed left behind' {
            Set-Content -LiteralPath (Join-Path $script:Folder 'page-000003.csv.1a2b3c4d.partial') -Value 'half a page' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $script:Folder 'manifest.json.1a2b3c4d.partial') -Value '{ half' -Encoding utf8NoBOM

            (Read-TestCheckpoint -Folder $script:Folder).Usable | Should -BeTrue
        }
    }
}

Describe 'Complete-SPSLifecycleListingCheckpoint and Clear-SPSLifecycleListingCheckpoint' {
    It 'completes a checkpoint: the pages go, the manifest stays and says when it finished' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken ''

        & $script:Module { param($f, $m, $n) Complete-SPSLifecycleListingCheckpoint -Folder $f -Manifest $m -Now $n } $folder $manifest $script:Now.AddMinutes(7)

        (Get-ChildItem -LiteralPath $folder -Name) | Should -Be @('manifest.json')
        $manifest.State | Should -BeExactly 'Completed'
        $json = Get-Content -LiteralPath (Join-Path $folder 'manifest.json') -Raw | ConvertFrom-Json
        $json.State | Should -BeExactly 'Completed'
        $json.FinishedOn | Should -BeExactly '20261030T090700.0000000Z'
        @($json.Pages) | Should -HaveCount 0
    }

    It 'refuses to complete a listing that is not complete' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $null = Save-TestPage -Folder $folder -Manifest $manifest -NextToken 'next-1'

        { & $script:Module { param($f, $m, $n) Complete-SPSLifecycleListingCheckpoint -Folder $f -Manifest $m -Now $n } $folder $manifest $script:Now } | Should -Throw -ExpectedMessage '*not complete*'
    }

    It 'removes the manifest, the pages and the partial files, and leaves the lock and anything else alone' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
        Set-Content -LiteralPath (Join-Path $folder 'page-000002.csv.1a2b3c4d.partial') -Value 'half' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $folder 'listing.lock') -Value '' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $folder 'notes.txt') -Value 'mine' -Encoding utf8NoBOM

        & $script:Module { param($f) Clear-SPSLifecycleListingCheckpoint -Folder $f } $folder

        (Get-ChildItem -LiteralPath $folder -Name | Sort-Object) | Should -Be @('listing.lock', 'notes.txt')
    }

    It 'removes nothing, and does not fail, when there is no checkpoint' {
        $folder = Join-Path -Path (New-TestFolder) -ChildPath 'missing'

        { & $script:Module { param($f) Clear-SPSLifecycleListingCheckpoint -Folder $f } $folder } | Should -Not -Throw
    }
}
