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

    # Rewrites one cell of a page file that Save-SPSLifecycleListingPage wrote (every cell is quoted, and the test records hold
    # no quote and no comma). Row 1 is the first site, as the header is row 0.
    function script:Edit-TestPageCell {
        param([string]$Path, [int]$Row, [string]$Column, [string]$Value)

        $columns = @(& $script:Module { Get-SPSLifecycleListingColumn })
        $lines = [System.IO.File]::ReadAllText($Path).TrimEnd("`r", "`n") -split "`r`n"
        $cells = $lines[$Row].Substring(1, $lines[$Row].Length - 2) -split '","'
        $cells[[System.Array]::IndexOf($columns, $Column)] = $Value
        $lines[$Row] = '"' + ($cells -join '","') + '"'
        [System.IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
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

    # Makes Move-Item fail inside the module for the length of the action, as a full disk would, and puts the cmdlet back.
    function script:Invoke-WithFailingMove {
        param([scriptblock]$Action)

        & $script:Module { Invoke-Expression 'function script:Move-Item { throw ''The disk is full.'' }' }
        try {
            & $Action
        }
        finally {
            & $script:Module { Remove-Item -Path 'Function:\Move-Item' -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Initialize-SPSLifecycleListingManifest' {
    It 'starts as a listing that has not begun: running, with no page, no token, and not complete' {
        $manifest = New-TestManifest

        $manifest.Version | Should -Be 1
        $manifest.State | Should -BeExactly 'Running'
        $manifest.Tenant | Should -BeExactly 'contoso'
        $manifest.Filter | Should -BeExactly $script:Filter
        $manifest.Options | Should -BeExactly $script:Options
        $manifest.ListingComplete | Should -BeFalse
        $manifest.NextToken | Should -BeExactly ''
        $manifest.FinishedOn | Should -BeExactly ''
        @($manifest.Pages) | Should -HaveCount 0
        $manifest.StartedOn | Should -BeExactly '20261030T090000.0000000Z'
        $manifest.UpdatedOn | Should -BeExactly $manifest.StartedOn
    }
}

Describe 'The dates of a checkpoint' {
    It 'is checked that the cultures below really write another year than the Gregorian one, so that the next test can fail' {
        $date = [System.DateTime]::new(2026, 10, 30, 9, 7, 0, [System.DateTimeKind]::Utc)

        $date.ToString('yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('th-TH')) | Should -BeExactly '2569'
        $date.ToString('yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('ar-SA')) | Should -Not -BeExactly '2026'
    }

    It 'writes and reads the same text whatever the culture and the calendar of the machine: <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
        @{ Culture = 'tr-TR' }
        @{ Culture = 'th-TH' }
        @{ Culture = 'ar-SA' }
        @{ Culture = 'fa-IR' }
    ) {
        $date = [System.DateTime]::new(2026, 10, 30, 9, 7, 0, [System.DateTimeKind]::Utc).AddTicks(1234567)

        Invoke-UnderCulture -Culture $Culture -Action {
            $text = & $script:Module { param($d) ConvertTo-SPSLifecycleCheckpointDate -Value $d } $date
            $back = & $script:Module { param($t) ConvertFrom-SPSLifecycleCheckpointDate -Text $t } '20261030T090700.1234567Z'

            $text | Should -BeExactly '20261030T090700.1234567Z'
            $back.Ticks | Should -Be $date.Ticks
            $back.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }
    }

    It 'writes the UTC time of a local date' {
        $local = [System.DateTime]::new(2026, 10, 30, 9, 7, 0, [System.DateTimeKind]::Utc).ToLocalTime()

        (& $script:Module { param($d) ConvertTo-SPSLifecycleCheckpointDate -Value $d } $local) | Should -BeExactly '20261030T090700.0000000Z'
    }

    It 'reads no date from a text that is not the one that the checkpoint writes: <Name>' -ForEach @(
        @{ Name = 'an empty text'; Text = '' }
        @{ Name = 'null'; Text = $null }
        @{ Name = 'ISO 8601 with separators'; Text = '2026-10-30T09:07:00.0000000Z' }
        @{ Name = 'no fraction'; Text = '20261030T090700Z' }
        @{ Name = 'no Z'; Text = '20261030T090700.0000000' }
        @{ Name = 'a month that does not exist'; Text = '20261330T090700.0000000Z' }
    ) {
        $null -eq (& $script:Module { param($t) ConvertFrom-SPSLifecycleCheckpointDate -Text $t } $Text) | Should -BeTrue
    }
}

Describe 'Get-SPSLifecycleListingManifestProblem' {
    BeforeAll {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 1 -NextToken 'next-1'
        $null = Save-TestPage -Folder $folder -Manifest $manifest -From 4 -Token 'next-1' -NextToken 'next-2'
        $script:BaseJson = Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'manifest.json') -Raw

        function script:Get-TestProblem {
            param([scriptblock]$Edit = $null)

            $json = $script:BaseJson | ConvertFrom-Json
            if ($null -ne $Edit) {
                & $Edit $json
            }

            & $script:Module { param($m) Get-SPSLifecycleListingManifestProblem -Manifest $m } $json
        }
    }

    It 'finds nothing to say about a manifest that the tool wrote' {
        Get-TestProblem | Should -BeExactly ''
    }

    It 'refuses what is not a JSON object: <Name>' -ForEach @(
        @{ Name = 'a text'; Value = 'text' }
        @{ Name = 'a number'; Value = 42 }
        @{ Name = 'an array'; Value = @(1, 2) }
    ) {
        (& $script:Module { param($m) Get-SPSLifecycleListingManifestProblem -Manifest $m } $Value) | Should -BeExactly 'the manifest is not a JSON object.'
    }

    It 'says which check refused the manifest: <Name>' -ForEach @(
        @{ Name = 'a property is missing'; Edit = { param($m) $m.PSObject.Properties.Remove('Tenant') }; Reason = "the property 'Tenant' is missing." }
        @{ Name = 'a property that the tool does not write'; Edit = { param($m) $m | Add-Member -NotePropertyName 'Extra' -NotePropertyValue 'x' }; Reason = "the property 'Extra' is not one that the tool writes." }
        @{ Name = 'a tenant that is a number'; Edit = { param($m) $m.Tenant = 5 }; Reason = "the value of 'Tenant' is not a text." }
        @{ Name = 'a next token that is a number'; Edit = { param($m) $m.NextToken = 5 }; Reason = "the value of 'NextToken' is not a text." }
        @{ Name = 'a state that is not known'; Edit = { param($m) $m.State = 'Paused' }; Reason = "the state 'Paused' is not one that the tool writes (Running or Completed)." }
        @{ Name = 'a state in lowercase'; Edit = { param($m) $m.State = 'running' }; Reason = "the state 'running' is not one that the tool writes*" }
        @{ Name = 'a state in capitals'; Edit = { param($m) $m.State = 'COMPLETED' }; Reason = "the state 'COMPLETED' is not one that the tool writes*" }
        @{ Name = 'a start that is not a date'; Edit = { param($m) $m.StartedOn = 'yesterday' }; Reason = "the value of 'StartedOn' is not a date that the tool writes." }
        @{ Name = 'an update that is not a date'; Edit = { param($m) $m.UpdatedOn = '2026-10-30T09:00:00Z' }; Reason = "the value of 'UpdatedOn' is not a date that the tool writes." }
        @{ Name = 'an end that is not a date'; Edit = { param($m) $m.FinishedOn = 'tomorrow' }; Reason = "the value of 'FinishedOn' is not a date that the tool writes." }
        @{ Name = 'a flag that is a text'; Edit = { param($m) $m.ListingComplete = 'no' }; Reason = "the value of 'ListingComplete' is not true or false." }
        @{ Name = 'pages that are not a list'; Edit = { param($m) $m.Pages = $m.Pages[0] }; Reason = "the value of 'Pages' is not a list." }
        @{ Name = 'a page that is not an object'; Edit = { param($m) $m.Pages[0] = 'page' }; Reason = 'the entry of page 1 is not an object.' }
        @{ Name = 'a page that lacks a property'; Edit = { param($m) $m.Pages[0].PSObject.Properties.Remove('Token') }; Reason = "the entry of page 1 lacks 'Token'." }
        @{ Name = 'a page with a property that the tool does not write'; Edit = { param($m) $m.Pages[1] | Add-Member -NotePropertyName 'Extra' -NotePropertyValue 1 }; Reason = "the entry of page 2 has a property that the tool does not write ('Extra')." }
        @{ Name = 'a page that read fewer sites than it kept'; Edit = { param($m) $m.Pages[0].Read = 1 }; Reason = 'page 1 kept more sites than it read.' }
        @{ Name = 'a number of sites below zero'; Edit = { param($m) $m.Pages[0].Sites = -1 }; Reason = "the value of 'Sites' in page 1 is not a whole number that is zero or more." }
        @{ Name = 'a number of sites read below zero'; Edit = { param($m) $m.Pages[0].Read = -1 }; Reason = "the value of 'Read' in page 1 is not a whole number that is zero or more." }
        @{ Name = 'a number of sites that is a text'; Edit = { param($m) $m.Pages[0].Sites = 'three' }; Reason = "the value of 'Sites' in page 1 is not a whole number that is zero or more." }
        @{ Name = 'a number of sites that has a fraction'; Edit = { param($m) $m.Pages[0].Sites = 1.5 }; Reason = "the value of 'Sites' in page 1 is not a whole number that is zero or more." }
        @{ Name = 'a page number that is a fraction'; Edit = { param($m) $m.Pages[0].Number = 1.5 }; Reason = "the value of 'Number' in page 1 is not a whole number that is zero or more." }
        @{ Name = 'pages that are not numbered without a gap'; Edit = { param($m) $m.Pages[1].Number = 3 }; Reason = 'the pages are not numbered from 1 without a gap (page 2 is numbered 3).' }
        @{ Name = 'a file named after another number'; Edit = { param($m) $m.Pages[0].File = 'page-000002.csv' }; Reason = 'the file of page 1 is not the one that the tool names after its number.' }
        @{ Name = 'a file name in another case'; Edit = { param($m) $m.Pages[0].File = 'Page-000001.csv' }; Reason = 'the file of page 1 is not the one that the tool names after its number.' }
        @{ Name = 'a file that is a number'; Edit = { param($m) $m.Pages[0].File = 1 }; Reason = 'the file of page 1 is not the one that the tool names after its number.' }
        @{ Name = 'a token that is a number'; Edit = { param($m) $m.Pages[1].Token = 5 }; Reason = 'the token of page 2 is not a text.' }
        @{ Name = 'a hash that is too short'; Edit = { param($m) $m.Pages[0].Sha256 = 'abc' }; Reason = 'the hash of page 1 is not a SHA-256 in lowercase hexadecimal.' }
        @{ Name = 'a hash in capitals'; Edit = { param($m) $m.Pages[0].Sha256 = $m.Pages[0].Sha256.ToUpperInvariant() }; Reason = 'the hash of page 1 is not a SHA-256 in lowercase hexadecimal.' }
        @{ Name = 'a hash that is a number'; Edit = { param($m) $m.Pages[0].Sha256 = 5 }; Reason = 'the hash of page 1 is not a SHA-256 in lowercase hexadecimal.' }
        @{ Name = 'a time below zero'; Edit = { param($m) $m.Pages[0].Seconds = -1 }; Reason = 'the time of page 1 is not a number of seconds.' }
        @{ Name = 'a time that is a text'; Edit = { param($m) $m.Pages[0].Seconds = 'fast' }; Reason = 'the time of page 1 is not a number of seconds.' }
        @{ Name = 'a page that lacks the token that it gave'; Edit = { param($m) $m.Pages[0].PSObject.Properties.Remove('NextToken') }; Reason = "the entry of page 1 lacks 'NextToken'." }
        @{ Name = 'a token given that is a number'; Edit = { param($m) $m.Pages[0].NextToken = 5 }; Reason = 'the next token of page 1 is not a text.' }
        @{ Name = 'a first page that was not asked with the first token'; Edit = { param($m) $m.Pages[0].Token = 'x' }; Reason = 'the first page was not asked with the first token (an empty one), but with ''x''.' }
        @{ Name = 'a page that was not asked with the token that the page before gave'; Edit = { param($m) $m.Pages[1].Token = 'other' }; Reason = "the token of page 2 is not the one that page 1 gave." }
        @{ Name = 'a last page that gave another token than the one to go on with'; Edit = { param($m) $m.Pages[1].NextToken = 'other' }; Reason = 'the token to go on with is not the one that the last page gave.' }
        @{ Name = 'a manifest from which the last page was removed'; Edit = { param($m) $m.Pages = @($m.Pages[0]) }; Reason = 'the token to go on with is not the one that the last page gave.' }
        @{ Name = 'a manifest from which the first page was removed'; Edit = { param($m) $m.Pages = @($m.Pages[1]); $m.Pages[0].Number = 1; $m.Pages[0].File = 'page-000001.csv' }; Reason = 'the first page was not asked with the first token (an empty one), but with ''next-1''.' }
        @{ Name = 'a listing that is complete and has a token'; Edit = { param($m) $m.ListingComplete = $true }; Reason = 'the listing is complete and still has a token to go on with.' }
        @{ Name = 'a listing that has pages, is not complete and has no token'; Edit = { param($m) $m.NextToken = '' }; Reason = 'the listing is not complete and has no token to go on with.' }
        @{ Name = 'a listing that is marked finished and is not complete'; Edit = { param($m) $m.State = 'Completed' }; Reason = 'the listing is marked finished and is not complete.' }
        @{ Name = 'a token that differs from the one that the page before gave by a character that is not shown'; Edit = { param($m) $m.Pages[1].Token = "next-1$([char]0x00AD)" }; Reason = 'the token of page 2 is not the one that page 1 gave.' }
        @{ Name = 'a token given by a page that differs by a character that is not shown from the one that the next page was asked with'; Edit = { param($m) $m.Pages[0].NextToken = "next-1$([char]0x00AD)" }; Reason = 'the token of page 2 is not the one that page 1 gave.' }
        @{ Name = 'a token to go on with that differs from the one that the last page gave by a character that is not shown'; Edit = { param($m) $m.NextToken = "next-2$([char]0x00AD)" }; Reason = 'the token to go on with is not the one that the last page gave.' }
        @{ Name = 'a first page that was asked with a token that is only a character that is not shown'; Edit = { param($m) $m.Pages[0].Token = [string][char]0x00AD }; Reason = 'the first page was not asked with the first token*' }
        @{ Name = 'a complete listing whose token to go on with is only a character that is not shown'; Edit = { param($m) $m.ListingComplete = $true; $m.NextToken = [string][char]0x00AD }; Reason = 'the listing is complete and still has a token to go on with.' }
        @{ Name = 'a listing that has pages whose token to go on with is only a character that is not shown'; Edit = { param($m) $m.NextToken = [string][char]0x00AD }; Reason = 'the token to go on with is not the one that the last page gave.' }
        @{ Name = 'a state that differs by a character that is not shown'; Edit = { param($m) $m.State = "Running$([char]0x00AD)" }; Reason = "the state 'Running*' is not one that the tool writes*" }
        @{ Name = 'a finished state that differs by a character that is not shown'; Edit = { param($m) $m.State = "Completed$([char]0x00AD)" }; Reason = "the state 'Completed*' is not one that the tool writes*" }
        @{ Name = 'a file name that differs by a character that is not shown'; Edit = { param($m) $m.Pages[0].File = "page-000001.csv$([char]0x00AD)" }; Reason = 'the file of page 1 is not the one that the tool names after its number.' }
    ) {
        Get-TestProblem -Edit $Edit | Should -BeLike $Reason
    }

    It 'accepts what a run can write, at the edges of the checks: <Name>' -ForEach @(
        @{ Name = 'a page of no site, that read none'; Edit = { param($m) $m.Pages[0].Sites = 0; $m.Pages[0].Read = 0 } }
        @{ Name = 'a page that kept as many sites as it read'; Edit = { param($m) $m.Pages[0].Read = 3 } }
        @{ Name = 'a page that read more sites than it kept'; Edit = { param($m) $m.Pages[0].Read = 1500 } }
        @{ Name = 'counts that JSON gives as long integers'; Edit = { param($m) $m.Pages[0].Read = [long]3; $m.Pages[0].Sites = [long]3 } }
        @{ Name = 'a time of zero'; Edit = { param($m) $m.Pages[0].Seconds = 0 } }
        @{ Name = 'a time that is a whole number'; Edit = { param($m) $m.Pages[0].Seconds = 2 } }
        @{ Name = 'a time that is a long integer'; Edit = { param($m) $m.Pages[0].Seconds = [long]2 } }
        @{ Name = 'a time with a fraction'; Edit = { param($m) $m.Pages[0].Seconds = 2.35 } }
        @{ Name = 'an end that is a date'; Edit = { param($m) $m.FinishedOn = '20261030T091500.0000000Z' } }
        @{ Name = 'a listing that has not saved a page yet: running, not complete, no page and no token'; Edit = { param($m) $m.Pages = @(); $m.NextToken = '' } }
        @{ Name = 'a finished listing: complete, with no page and no token'; Edit = { param($m) $m.State = 'Completed'; $m.ListingComplete = $true; $m.NextToken = ''; $m.Pages = @() } }
    ) {
        Get-TestProblem -Edit $Edit | Should -BeExactly ''
    }
}

Describe 'Write-SPSLifecycleListingManifest' {
    It 'writes manifest.json in the folder, and nothing else, also when the folder is relative to the location of the session' {
        $root = New-TestFolder
        $null = New-Item -Path (Join-Path -Path $root -ChildPath 'checkpoint') -ItemType Directory
        $manifest = New-TestManifest
        Push-Location -LiteralPath $root
        try {
            & $script:Module { param($m) Write-SPSLifecycleListingManifest -Folder 'checkpoint' -Manifest $m } $manifest
        }
        finally {
            Pop-Location
        }

        $folder = Join-Path -Path $root -ChildPath 'checkpoint'
        @(Get-ChildItem -LiteralPath $folder -Name) | Should -Be @('manifest.json')
        (Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'manifest.json') -Raw | ConvertFrom-Json).Tenant | Should -BeExactly 'contoso'
    }

    It 'leaves the manifest as it was, and no partial file, when the disk refuses the new one' {
        $folder = New-TestFolder
        $first = New-TestManifest -Tenant 'first'
        & $script:Module { param($f, $m) Write-SPSLifecycleListingManifest -Folder $f -Manifest $m } $folder $first
        $second = New-TestManifest -Tenant 'second'

        { Invoke-WithFailingMove -Action { & $script:Module { param($f, $m) Write-SPSLifecycleListingManifest -Folder $f -Manifest $m } $folder $second } } | Should -Throw -ExpectedMessage '*disk is full*'

        (Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'manifest.json') -Raw | ConvertFrom-Json).Tenant | Should -BeExactly 'first'
        @(Get-ChildItem -LiteralPath $folder -Filter '*.partial') | Should -HaveCount 0
        (& $script:Module { (Get-Command -Name Move-Item).CommandType }) | Should -Be 'Cmdlet'
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
        @{ Culture = 'th-TH' }
        @{ Culture = 'ar-SA' }
        @{ Culture = 'sv-SE' }
    ) {
        Invoke-UnderCulture -Culture $Culture -Action {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $record = New-TestRecord -Index 1 -Override @{ StorageUsedMB = [long]1234567; Title = 'Ilık İşler 1.5' }
            $negative = New-TestRecord -Index 2 -Override @{ StorageUsedMB = [long]-5 }
            $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records @($record, $negative)

            $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

            $back | Should -HaveCount 2
            $back[0].StorageUsedMB | Should -Be 1234567
            $back[0].Title | Should -BeExactly 'Ilık İşler 1.5'
            $back[0].LastContentModified.Ticks | Should -Be $record.LastContentModified.Ticks
            $back[1].StorageUsedMB | Should -Be ([long]-5)
            $back[1].LastContentModified.Ticks | Should -Be $negative.LastContentModified.Ticks
            $entry.File | Should -BeExactly 'page-000001.csv'
        }
    }

    It 'gives each site its own size and date: a site that has none does not take the one of the site before' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $records = @(
            New-TestRecord -Index 1
            New-TestRecord -Index 2 -Override @{ StorageUsedMB = $null; LastContentModified = $null }
            New-TestRecord -Index 3
        )
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Records $records

        $back = @(& $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry)

        $back | Should -HaveCount 3
        $null -eq $back[1].StorageUsedMB | Should -BeTrue
        $null -eq $back[1].LastContentModified | Should -BeTrue
        $back[2].StorageUsedMB | Should -Be 13
        $back[2].LastContentModified.Ticks | Should -Be $records[2].LastContentModified.Ticks
    }

    It 'refuses a flag that is not True or False, and names the page, the line and the column: <Name>' -ForEach @(
        @{ Name = 'a word'; Column = 'IsHubSite'; Value = 'Yes' }
        @{ Name = 'lowercase'; Column = 'IsTeamsConnected'; Value = 'true' }
        @{ Name = 'a number'; Column = 'IsTeamsChannelConnected'; Value = '1' }
        @{ Name = 'an empty cell'; Column = 'IsHubSite'; Value = '' }
    ) {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Count 3
        Edit-TestPageCell -Path (Join-Path -Path $folder -ChildPath $entry.File) -Row 2 -Column $Column -Value $Value

        { & $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry } | Should -Throw -ExpectedMessage "*page 1 of the checkpoint, line 3: '$Column' is neither True nor False.*"
    }

    It 'refuses a size that is not a whole number, and names the page, the line and the column: <Name>' -ForEach @(
        @{ Name = 'a word'; Value = 'many' }
        @{ Name = 'a fraction'; Value = '1.5' }
        @{ Name = 'an exponent'; Value = '1e3' }
        @{ Name = 'a thousands separator'; Value = '1,000' }
    ) {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Count 3
        Edit-TestPageCell -Path (Join-Path -Path $folder -ChildPath $entry.File) -Row 3 -Column 'StorageUsedMB' -Value $Value

        { & $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry } | Should -Throw -ExpectedMessage "*page 1 of the checkpoint, line 4: 'StorageUsedMB' is not a whole number.*"
    }

    It 'refuses a date that is not the one that the checkpoint writes, and names the page, the line and the column: <Name>' -ForEach @(
        @{ Name = 'a word'; Value = 'yesterday' }
        @{ Name = 'ISO 8601 with separators'; Value = '2026-10-14T10:05:58.0000001Z' }
        @{ Name = 'no fraction'; Value = '20261014T100558Z' }
        @{ Name = 'a month that does not exist'; Value = '20261414T100558.0000001Z' }
    ) {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Count 3
        Edit-TestPageCell -Path (Join-Path -Path $folder -ChildPath $entry.File) -Row 1 -Column 'LastContentModified' -Value $Value

        { & $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry } | Should -Throw -ExpectedMessage "*page 1 of the checkpoint, line 2: 'LastContentModified' is not a date that the checkpoint writes.*"
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

    It 'creates the folder of the checkpoint when it is not there' {
        $folder = Join-Path -Path (New-TestFolder) -ChildPath 'listing-checkpoint'
        $manifest = New-TestManifest

        $null = Save-TestPage -Folder $folder -Manifest $manifest

        @(Get-ChildItem -LiteralPath $folder -Name | Sort-Object) | Should -Be @('manifest.json', 'page-000001.csv')
    }

    It 'records in the manifest when the last page was saved' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $later = $script:Now.AddMinutes(7)

        $null = & $script:Module {
            param($f, $m, $r, $n)
            Save-SPSLifecycleListingPage -Folder $f -Manifest $m -Record $r -Token '' -NextToken 'next-1' -Read 1 -Seconds 1 -Now $n
        } $folder $manifest @((New-TestRecord -Index 1)) $later

        $manifest.StartedOn | Should -BeExactly '20261030T090000.0000000Z'
        $manifest.UpdatedOn | Should -BeExactly '20261030T090700.0000000Z'
        (Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'manifest.json') -Raw | ConvertFrom-Json).UpdatedOn | Should -BeExactly '20261030T090700.0000000Z'
    }

    It 'lists no page, leaves no partial file and gives the error, when the disk refuses the page' {
        $folder = New-TestFolder
        $manifest = New-TestManifest

        { Invoke-WithFailingMove -Action { Save-TestPage -Folder $folder -Manifest $manifest } } | Should -Throw -ExpectedMessage '*disk is full*'

        @($manifest.Pages) | Should -HaveCount 0
        @(Get-ChildItem -LiteralPath $folder -Name) | Should -HaveCount 0
        (& $script:Module { (Get-Command -Name Move-Item).CommandType }) | Should -Be 'Cmdlet'
    }

    It 'refuses a page that holds another number of sites than the manifest says, although the file is the one that was saved' {
        $folder = New-TestFolder
        $manifest = New-TestManifest
        $entry = Save-TestPage -Folder $folder -Manifest $manifest -Count 3
        $entry.Sites = 4

        { & $script:Module { param($f, $e) Read-SPSLifecycleListingPage -Folder $f -Entry $e } $folder $entry } | Should -Throw -ExpectedMessage '*page 1*holds 3 sites*manifest says 4*'
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

        It 'is refused, with its reason and the code of its reason, when <Name>' -ForEach @(
            @{ Name = 'it is for another tenant'; Tenant = 'fabrikam'; Filter = "LockState -eq 'ReadOnly'"; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*tenant*'; Code = 'other-tenant' }
            @{ Name = 'the filter changed'; Tenant = 'contoso'; Filter = "LockState -eq 'Unlock'"; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*filter*'; Code = 'other-filter' }
            @{ Name = 'the filter was removed'; Tenant = 'contoso'; Filter = ''; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*filter*'; Code = 'other-filter' }
            @{ Name = 'the way the sites are asked changed'; Tenant = 'contoso'; Filter = "LockState -eq 'ReadOnly'"; Options = 'Source=Cmdlet'; Expected = '*asked*'; Code = 'other-options' }
            @{ Name = 'the filter differs only by a character that is not shown'; Tenant = 'contoso'; Filter = "LockState -eq 'ReadOnly'$([char]0x00AD)"; Options = 'Source=Csom;PersonalSites=Excluded'; Expected = '*filter*'; Code = 'other-filter' }
            @{ Name = 'the way the sites are asked differs only by a character that is not shown'; Tenant = 'contoso'; Filter = "LockState -eq 'ReadOnly'"; Options = "Source=Csom;PersonalSites=Excluded$([char]0x00AD)"; Expected = '*asked*'; Code = 'other-options' }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            $state = Read-TestCheckpoint -Folder $folder -Tenant $Tenant -Filter $Filter -Options $Options

            $state.Exists | Should -BeTrue
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike $Expected
            $state.Code | Should -BeExactly $Code
            $null -eq $state.Manifest | Should -BeTrue
        }

        It 'gives a code for each way of not being taken up, that names nothing of the tenant: <Name>' -ForEach @(
            @{ Name = 'a manifest that is not JSON'; Code = 'damaged'; Make = { param($f) Set-Content -LiteralPath (Join-Path $f 'manifest.json') -Value '{ no' -Encoding utf8NoBOM } }
            @{ Name = 'a manifest of another version'; Code = 'other-version'; Make = { param($f) Edit-TestFile -Path (Join-Path $f 'manifest.json') -Pattern '"Version":\s*1' -Replacement '"Version": 2' } }
            @{ Name = 'a page that is missing'; Code = 'damaged'; Make = { param($f) Remove-Item -LiteralPath (Join-Path $f 'page-000001.csv') } }
            @{ Name = 'a listing that finished'; Code = 'finished'; Make = { param($f) Get-ChildItem -LiteralPath $f | Remove-Item -Force; $m = New-TestManifest; $null = Save-TestPage -Folder $f -Manifest $m -NextToken ''; & $script:Module { param($f2, $m2, $n) Complete-SPSLifecycleListingCheckpoint -Folder $f2 -Manifest $m2 -Now $n } $f $m $script:Now } }
            @{ Name = 'a clock that was set back'; Code = 'clock'; Make = { param($f) Edit-TestFile -Path (Join-Path $f 'manifest.json') -Pattern '"UpdatedOn":\s*"[^"]*"' -Replacement '"UpdatedOn": "20261030T110000.0000000Z"' } }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest
            & $Make $folder

            $state = Read-TestCheckpoint -Folder $folder

            $state.Usable | Should -BeFalse
            $state.Code | Should -BeExactly $Code
        }

        It 'gives the code too-old for a checkpoint that is too old, and no code for one that can be taken up or that does not exist' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder -Now $script:Now.AddHours(25)).Code | Should -BeExactly 'too-old'
            $usable = Read-TestCheckpoint -Folder $folder
            $usable.Usable | Should -BeTrue
            $usable.Code | Should -BeExactly ''
            (Read-TestCheckpoint -Folder (Join-Path -Path (New-TestFolder) -ChildPath 'missing')).Code | Should -BeExactly ''
        }

        It 'is not trusted when the dates are not in order, as the clock of the machine was set back while the listing ran: <Name>' -ForEach @(
            @{ Name = 'an update a second before the start'; UpdatedOn = '20261030T085959.0000000Z'; Usable = $false }
            @{ Name = 'an update an hour before the start'; UpdatedOn = '20261030T080000.0000000Z'; Usable = $false }
            @{ Name = 'an update at the very moment of the start'; UpdatedOn = '20261030T090000.0000000Z'; Usable = $true }
            @{ Name = 'an update after the start'; UpdatedOn = '20261030T090100.0000000Z'; Usable = $true }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest
            $manifest.UpdatedOn = $UpdatedOn
            & $script:Module { param($f, $m) Write-SPSLifecycleListingManifest -Folder $f -Manifest $m } $folder $manifest

            $state = Read-TestCheckpoint -Folder $folder -Now $script:Now.AddMinutes(10)

            $state.Usable | Should -Be $Usable
            if (-not $Usable) {
                $state.Reason | Should -BeLike '*not in order*clock*'
            }
        }

        It 'says what the filter was and what it is, with none written as (none): <Name>' -ForEach @(
            @{ Name = 'changed'; Filter = "LockState -eq 'Unlock'"; Expected = "The filter changed (it was LockState -eq 'ReadOnly', it is LockState -eq 'Unlock')." }
            @{ Name = 'removed'; Filter = ''; Expected = "The filter changed (it was LockState -eq 'ReadOnly', it is (none))." }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder -Filter $Filter).Reason | Should -BeExactly $Expected
        }

        It 'says that a filter was added when there was none' {
            $folder = New-TestFolder
            $manifest = & $script:Module { param($t, $o, $n) Initialize-SPSLifecycleListingManifest -Tenant $t -Filter '' -Options $o -Now $n } 'contoso' $script:Options $script:Now
            $null = Save-TestPage -Folder $folder -Manifest $manifest

            (Read-TestCheckpoint -Folder $folder -Filter "LockState -eq 'ReadOnly'").Reason | Should -BeExactly "The filter changed (it was (none), it is LockState -eq 'ReadOnly')."
        }

        It 'is not trusted when the last update is dated in the future, as the clock of the machine may have been set back: <Name>' -ForEach @(
            @{ Name = 'two hours ahead'; UpdatedOn = '20261030T110000.0000000Z'; Usable = $false }
            @{ Name = 'a second more than the five minutes of tolerance'; UpdatedOn = '20261030T090501.0000000Z'; Usable = $false }
            @{ Name = 'exactly the five minutes of tolerance'; UpdatedOn = '20261030T090500.0000000Z'; Usable = $true }
            @{ Name = 'now'; UpdatedOn = '20261030T090000.0000000Z'; Usable = $true }
        ) {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest
            $manifest.UpdatedOn = $UpdatedOn
            & $script:Module { param($f, $m) Write-SPSLifecycleListingManifest -Folder $f -Manifest $m } $folder $manifest

            $state = Read-TestCheckpoint -Folder $folder

            $state.Usable | Should -Be $Usable
            if (-not $Usable) {
                $state.Reason | Should -BeLike '*future*'
            }
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

        It 'is refused when the manifest of a listing that is running says that it is complete and lists no page: nothing was listed, and nothing would be read' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $manifest.ListingComplete = $true
            & $script:Module { param($f, $m) Write-SPSLifecycleListingManifest -Folder $f -Manifest $m } $folder $manifest

            $state = Read-TestCheckpoint -Folder $folder

            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*damaged*running, complete, and lists no page*'
        }

        It 'does not take a finished listing for a damaged one, although it is complete and lists no page' {
            $folder = New-TestFolder
            $manifest = New-TestManifest
            $null = Save-TestPage -Folder $folder -Manifest $manifest -NextToken ''
            & $script:Module { param($f, $m, $n) Complete-SPSLifecycleListingCheckpoint -Folder $f -Manifest $m -Now $n } $folder $manifest $script:Now

            $state = Read-TestCheckpoint -Folder $folder

            $state.Finished | Should -BeTrue
            $state.Usable | Should -BeFalse
            $state.Reason | Should -BeLike '*finished*'
            $state.Reason | Should -Not -BeLike '*damaged*'
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
        $json.UpdatedOn | Should -BeExactly '20261030T090700.0000000Z'
        $manifest.UpdatedOn | Should -BeExactly '20261030T090700.0000000Z'
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
        Set-Content -LiteralPath (Join-Path $folder 'manifest.json.5e6f7a8b.partial') -Value '{ half' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $folder 'listing.lock') -Value '' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $folder 'notes.txt') -Value 'mine' -Encoding utf8NoBOM

        & $script:Module { param($f) Clear-SPSLifecycleListingCheckpoint -Folder $f } $folder

        (Get-ChildItem -LiteralPath $folder -Name | Sort-Object) | Should -Be @('listing.lock', 'notes.txt')
    }

    It 'removes nothing, and does not fail, when there is no checkpoint, even when every error is made to stop the caller' {
        $folder = Join-Path -Path (New-TestFolder) -ChildPath 'missing'

        { & $script:Module { param($f) Clear-SPSLifecycleListingCheckpoint -Folder $f -ErrorAction Stop } $folder } | Should -Not -Throw
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'removes only the files that the tool wrote, named as it names them: <Name>' -ForEach @(
        @{ Name = 'a manifest in capitals'; Leave = 'MANIFEST.JSON' }
        @{ Name = 'a manifest with another extension'; Leave = 'manifest.json.bak' }
        @{ Name = 'a page in capitals'; Leave = 'PAGE-000001.CSV' }
        @{ Name = 'a page file in capitals only in its extension'; Leave = 'page-000001.CSV' }
        @{ Name = 'a page numbered with fewer digits'; Leave = 'page-1.csv' }
        @{ Name = 'a page numbered with more digits'; Leave = 'page-0000001.csv' }
        @{ Name = 'a page that something else wrote after'; Leave = 'page-000001.csv.bak' }
        @{ Name = 'a page with a prefix'; Leave = 'old-page-000001.csv' }
        @{ Name = 'a partial file in capitals'; Leave = 'page-000003.csv.1a2b3c4d.PARTIAL' }
        @{ Name = 'a file that only mentions partial'; Leave = 'partial.txt' }
        @{ Name = 'a file of the user that ends with .partial'; Leave = 'customer-notes.partial' }
        @{ Name = 'a partial file of another name'; Leave = 'notes.csv.1a2b3c4d.partial' }
        @{ Name = 'a partial file with no suffix'; Leave = 'page-000003.csv.partial' }
        @{ Name = 'a partial file whose suffix is too short'; Leave = 'page-000003.csv.1a2b3c.partial' }
        @{ Name = 'a partial file whose suffix is too long'; Leave = 'manifest.json.1a2b3c4d5.partial' }
        @{ Name = 'a partial file whose suffix is not hexadecimal'; Leave = 'manifest.json.1a2b3c4z.partial' }
        @{ Name = 'a partial file whose suffix is in capitals'; Leave = 'manifest.json.1A2B3C4D.partial' }
    ) {
        # No real manifest or page of the same number is written here: on a file system that ignores the case (Windows, macOS), a
        # file that only differs by the case from the one of the tool would be that very file.
        $folder = New-TestFolder
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'page-000009.csv') -Value 'written by the tool' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath $Leave) -Value 'not written by the tool' -Encoding utf8NoBOM

        & $script:Module { param($f) Clear-SPSLifecycleListingCheckpoint -Folder $f } $folder

        @(Get-ChildItem -LiteralPath $folder -Name) | Should -Be @($Leave)
    }
}
