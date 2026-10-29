BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:SiteB = '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    $script:SiteC = '3c9f7a52-8b1e-4d6a-9f0e-21c4d5e6f708'

    function script:New-TestFolder {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $folder
    }

    function script:Write-TestFile {
        param([string]$Folder, [string]$Name, [string]$Text, [string]$Encoding = 'utf8bom')
        $path = Join-Path -Path $Folder -ChildPath $Name
        switch ($Encoding) {
            'utf8bom' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($true)) }
            'utf8' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UTF8Encoding]::new($false)) }
            'cp1252' { [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)) }
            'utf16' { [System.IO.File]::WriteAllText($path, $Text, [System.Text.UnicodeEncoding]::new($false, $true)) }
        }

        $path
    }

    function script:Import-TestList {
        param([string]$Path, [string[]]$DateFormat = @())
        & $script:Module { param($p, $f) Import-SPSLifecycleLockDateList -Path $p -DateFormat $f } $Path $DateFormat
    }

    function script:Import-TestJournal {
        param([string]$Path, [string[]]$DateFormat = @())
        & $script:Module { param($p, $f) Import-SPSLifecycleLockJournal -Path $p -DateFormat $f } $Path $DateFormat
    }

    function script:Merge-TestLockDate {
        param($Import)
        & $script:Module { param($i) Merge-SPSLifecycleLockDate -Import $i } $Import
    }

    function script:Get-TestIndex {
        param([string[]]$LockDateFile = @(), [string]$LockJournal = '', [string[]]$DateFormat = @())
        & $script:Module { param($p) Get-SPSLifecycleLockDateIndex @p } @{ LockDateFile = $LockDateFile; LockJournal = $LockJournal; DateFormat = $DateFormat }
    }

    function script:Find-TestLockDate {
        param($Index, [string]$SiteId = '', [string]$Url = '')
        & $script:Module { param($x, $s, $u) Find-SPSLifecycleLockDate -Index $x -SiteId $s -Url $u } $Index $SiteId $Url
    }

    function script:New-TestEntry {
        param([string]$Url = '', [string]$SiteId = '', [string]$Date = '2025-09-18', [string]$Source = 'list.csv')
        $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $Url
        [PSCustomObject]@{
            Url      = $Url
            UrlKey   = $key
            SiteId   = $SiteId
            LockedOn = [System.DateTime]::SpecifyKind([System.DateTime]::ParseExact($Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture), [System.DateTimeKind]::Utc)
            Source   = $Source
        }
    }

    function script:New-TestImport {
        param([string]$Name, [object[]]$Entry)
        [PSCustomObject]@{ Name = $Name; RowCount = @($Entry).Count; Entries = @($Entry) }
    }

    # What a user gets after Set-Location: the location of the PowerShell session moves, the working directory of
    # the process does not. Both are put back afterwards.
    function script:Invoke-InDivergedLocation {
        param([string]$Location, [string]$ProcessDirectory, [scriptblock]$Script)
        $previousLocation = (Get-Location).Path
        $previousDirectory = [System.IO.Directory]::GetCurrentDirectory()
        try {
            [System.IO.Directory]::SetCurrentDirectory($ProcessDirectory)
            Set-Location -LiteralPath $Location
            & $Script
        }
        finally {
            Set-Location -LiteralPath $previousLocation
            [System.IO.Directory]::SetCurrentDirectory($previousDirectory)
        }
    }
}

Describe 'Import-SPSLifecycleLockJournal' {
    BeforeEach {
        $script:Folder = New-TestFolder
    }

    It 'is an empty journal when the file does not exist yet' {
        $journal = Import-TestJournal -Path (Join-Path -Path $script:Folder -ChildPath 'lock-journal.csv')

        $journal.Found | Should -BeFalse
        $journal.RowCount | Should -Be 0
        @($journal.Entries) | Should -HaveCount 0
        $journal.Name | Should -BeExactly 'lock-journal.csv'
    }

    It 'is an empty journal when the folder does not exist either' {
        $journal = Import-TestJournal -Path (Join-Path -Path $script:Folder -ChildPath 'never/created/lock-journal.csv')

        $journal.Found | Should -BeFalse
        @($journal.Entries) | Should -HaveCount 0
    }

    It 'is an empty journal when the file has no byte at all' {
        $path = Join-Path -Path $script:Folder -ChildPath 'lock-journal.csv'
        [System.IO.File]::WriteAllBytes($path, [byte[]]@())

        $journal = Import-TestJournal -Path $path

        $journal.Found | Should -BeTrue
        $journal.RowCount | Should -Be 0
        @($journal.Entries) | Should -HaveCount 0
    }

    It 'is an empty journal when the file has a header and no row' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`n"

        $journal = Import-TestJournal -Path $path

        $journal.Found | Should -BeTrue
        $journal.RowCount | Should -Be 0
    }

    It 'reads the rows that the tool writes, and names the journal as their source' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29T14:37:39Z`r`nhttps://contoso.sharepoint.com/sites/b,$($script:SiteB),2026-10-30`r`n"

        $journal = Import-TestJournal -Path $path
        $entry = $journal.Entries | Where-Object { $_.SiteId -eq $script:SiteA }

        $journal.Found | Should -BeTrue
        $journal.RowCount | Should -Be 2
        $journal.Entries | Should -HaveCount 2
        $entry.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
        $entry.LockedOn.ToString('o') | Should -Be '2026-10-29T14:37:39.0000000Z'
        $entry.Source | Should -BeExactly 'lock-journal.csv'
    }

    It 'reads a journal that French Excel saved: semicolons, Windows-1252, dd/MM/yyyy' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Encoding cp1252 -Text "Url;SiteId;LockedOn`r`nhttps://contoso.sharepoint.com/sites/équipe;$($script:SiteA);29/10/2026`r`n"

        $journal = Import-TestJournal -Path $path -DateFormat 'dd/MM/yyyy'

        $journal.Entries[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/équipe'
        $journal.Entries[0].LockedOn.ToString('yyyy-MM-dd') | Should -Be '2026-10-29'
    }

    It 'stops on a date that it cannot read, and names the journal and the column' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),29/10/2026`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage "*lock-journal.csv*LockedOn*"
    }

    It 'stops on a row that has no date, because it could hide a lock that is more recent than the other rows of the site' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-01-01`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 3*no lock date*'
    }

    It 'stops on a row whose site ID is not a GUID, because the row would lose its identity: <Name>' -ForEach @(
        @{ Name = 'a cut ID'; Id = 'a6e20079-2d1a-4e9d' }
        @{ Name = 'zeros'; Id = '00000000-0000-0000-0000-000000000000' }
        @{ Name = 'text'; Id = 'unknown' }
    ) {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$Id,2026-10-29`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 2*site ID*'
    }

    It 'stops on a row that has neither an address nor a site ID, because the date belongs to no site' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-28`r`n,,2026-10-29`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 3*neither*'
    }

    It 'stops on a row that has a value too many, even when the first values are empty (an overflow must not look like an empty row)' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`n,,,https://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29T14:37:39Z`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 2*6 value(s)*'
    }

    It 'stops on a row that is cut short' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA)`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 2*2 value(s)*'
    }

    It 'stops on an address that cannot be used, because the row would be indexed under a key that no site has: <Name>' -ForEach @(
        @{ Name = 'a path'; Url = 'sites/a' }
        @{ Name = 'a zero-width space'; Url = [string][char]0x200B }
        @{ Name = 'an address with a space'; Url = 'https://contoso.sharepoint.com/sites/a b' }
        @{ Name = 'another scheme'; Url = 'ftp://contoso.sharepoint.com/sites/a' }
    ) {
        $good = (1..9 | ForEach-Object { "https://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-01-01" }) -join "`r`n"
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`n$good`r`n$Url,,2026-10-29T14:37:39Z`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 11*web address*'
    }

    It 'stops on a journal in which a stray quote hides an unclosed one (an even number of quotes)' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-01-01,stray`"quote`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-02-01,`"unfinished"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 2*CSV rules*'
    }

    It 'accepts a row that has an address and no site ID, as a person may write it' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,,2026-10-29`r`n"

        $journal = Import-TestJournal -Path $path

        $journal.Entries | Should -HaveCount 1
        $journal.Entries[0].SiteId | Should -BeExactly ''
    }

    It 'still ignores a row without a date in a list that a person provides: it says nothing about the site' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lot.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,`r`nhttps://contoso.sharepoint.com/sites/b,2025-09-18`r`n"

        $list = Import-TestList -Path $path

        $list.Entries | Should -HaveCount 1
    }

    It 'stops on a journal that ends inside a quoted field, because the rows after the quote are read as part of it' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn,Note`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-02-01,`"unfinished"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*lock-journal.csv*line 2*CSV rules*'
    }

    It 'stops on a journal that has no SiteId column, because its dates would be attributed to addresses' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,2026-10-29`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*not found*SiteId*'
    }

    It 'stops on a list whose SiteId column only looks like it: the identity of every row would be lost' -ForEach @(
        @{ Name = 'a soft hyphen'; Header = "Site$([char]0xAD)Id" }
        @{ Name = 'a zero-width space'; Header = "Site$([char]0x200B)Id" }
        @{ Name = 'a space'; Header = 'Site ID' }
    ) {
        $path = Write-TestFile -Folder $script:Folder -Name 'lot1.csv' -Text "Url,$Header,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2024-01-01`r`n"

        { Import-TestList -Path $path } | Should -Throw -ExpectedMessage "*lot1.csv*looks like 'SiteId'*"
    }

    It 'does not take a column that only looks like SiteId for it: the identity is not silently lost' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,Site$([char]0xAD)Id,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage "*Site\u00ADId*looks like 'SiteId'*"
    }

    It 'stops when the path is a folder' {
        { Import-TestJournal -Path $script:Folder } | Should -Throw -ExpectedMessage '*is a folder*'
    }

    It 'stops when the file is not a lock journal, which is not the same as a journal that is missing' {
        $path = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Name,Size`r`nSales,12`r`n"

        { Import-TestJournal -Path $path } | Should -Throw -ExpectedMessage '*not found*'
    }

    It 'finds the journal of the session location, not a missing one of the working directory of the process' {
        $location = New-TestFolder
        $processDirectory = New-TestFolder
        $null = Write-TestFile -Folder $location -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29`r`n"

        $journal = Invoke-InDivergedLocation -Location $location -ProcessDirectory $processDirectory -Script {
            Import-TestJournal -Path 'lock-journal.csv'
        }

        $journal.Found | Should -BeTrue
        $journal.Entries | Should -HaveCount 1
    }
}

Describe 'Merge-SPSLifecycleLockDate' {
    It 'keeps the latest date of a site across the lists and the journal, and the name of the file that gave it' {
        $lot1 = New-TestImport -Name 'lot1.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA -Date '2025-03-01' -Source 'lot1.csv')
        $journal = New-TestImport -Name 'lock-journal.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA -Date '2025-09-18' -Source 'lock-journal.csv')

        foreach ($order in @($lot1, $journal), @($journal, $lot1)) {
            $index = Merge-TestLockDate -Import $order
            $found = Find-TestLockDate -Index $index -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/sales'

            $found.LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-09-18'
            $found.Source | Should -BeExactly 'lock-journal.csv'
        }
    }

    It 'keeps the first source when two sources give the same date, for an entry with a site ID and for an entry with a URL only' {
        $url = 'https://contoso.sharepoint.com/sites/sales'
        $one = New-TestImport -Name 'one.csv' -Entry @((New-TestEntry -SiteId $script:SiteA -Date '2025-09-18' -Source 'one.csv'), (New-TestEntry -Url $url -Date '2025-09-18' -Source 'one.csv'))
        $two = New-TestImport -Name 'two.csv' -Entry @((New-TestEntry -SiteId $script:SiteA -Date '2025-09-18' -Source 'two.csv'), (New-TestEntry -Url $url -Date '2025-09-18' -Source 'two.csv'))

        foreach ($case in @{ First = $one; Second = $two; Named = 'one.csv' }, @{ First = $two; Second = $one; Named = 'two.csv' }) {
            $index = Merge-TestLockDate -Import @($case.First, $case.Second)

            (Find-TestLockDate -Index $index -SiteId $script:SiteA).Source | Should -BeExactly $case.Named
            (Find-TestLockDate -Index $index -SiteId $script:SiteB -Url $url).Source | Should -BeExactly $case.Named
        }
    }

    It 'finds an entry that has no site ID by its URL, whatever the spelling of the address' {
        $list = New-TestImport -Name 'lot2.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/hr' -Date '2025-01-10' -Source 'lot2.csv')
        $index = Merge-TestLockDate -Import @($list)

        foreach ($spelling in 'https://contoso.sharepoint.com/sites/hr', 'HTTPS://CONTOSO.sharepoint.com:443/Sites/HR/', 'https://contoso.sharepoint.com/sites/hr?x=1') {
            $found = Find-TestLockDate -Index $index -SiteId $script:SiteB -Url $spelling

            $found.LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-01-10'
            $found.Source | Should -BeExactly 'lot2.csv'
        }
    }

    It 'finds an entry that has a site ID by that ID, even when the site has a new address' {
        $list = New-TestImport -Name 'lot1.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/old' -SiteId $script:SiteA -Date '2025-03-01')
        $index = Merge-TestLockDate -Import @($list)

        $found = Find-TestLockDate -Index $index -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/new'

        $found.LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-03-01'
    }

    It 'ignores an entry whose site ID is another one, because that site reused the address' {
        $list = New-TestImport -Name 'lot1.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA -Date '2025-03-01')
        $index = Merge-TestLockDate -Import @($list)

        Find-TestLockDate -Index $index -SiteId $script:SiteB -Url 'https://contoso.sharepoint.com/sites/sales' | Should -BeNullOrEmpty
        (Find-TestLockDate -Index $index -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/sales').LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-03-01'
    }

    It 'keeps the dates of two sites that used the same address, one for each site ID' {
        $list = New-TestImport -Name 'lot1.csv' -Entry @(
            (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA -Date '2025-03-01'),
            (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteB -Date '2025-09-18'))
        $index = Merge-TestLockDate -Import @($list)

        (Find-TestLockDate -Index $index -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/sales').LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-03-01'
        (Find-TestLockDate -Index $index -SiteId $script:SiteB -Url 'https://contoso.sharepoint.com/sites/sales').LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-09-18'
    }

    It 'takes the later of the entry of the site ID and the entry of the URL: <Name>' -ForEach @(
        @{ Name = 'the ID entry is later'; IdDate = '2025-09-18'; UrlDate = '2025-03-01'; Expected = '2025-09-18'; ExpectedSource = 'id.csv' }
        @{ Name = 'the URL entry is later'; IdDate = '2025-03-01'; UrlDate = '2025-09-18'; Expected = '2025-09-18'; ExpectedSource = 'url.csv' }
        @{ Name = 'the dates are equal, so the site ID wins'; IdDate = '2025-03-01'; UrlDate = '2025-03-01'; Expected = '2025-03-01'; ExpectedSource = 'id.csv' }
    ) {
        $byId = New-TestImport -Name 'id.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA -Date $IdDate -Source 'id.csv')
        $byUrl = New-TestImport -Name 'url.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -Date $UrlDate -Source 'url.csv')

        foreach ($order in @($byId, $byUrl), @($byUrl, $byId)) {
            $found = Find-TestLockDate -Index (Merge-TestLockDate -Import $order) -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/sales'

            $found.LockedOn.ToString('yyyy-MM-dd') | Should -Be $Expected
            $found.Source | Should -BeExactly $ExpectedSource
        }
    }

    It 'finds nothing when the site ID of the site is unknown, whatever the entries: it is not known whose date it would be' {
        $url = 'https://contoso.sharepoint.com/sites/sales'
        $index = Merge-TestLockDate -Import @(
            (New-TestImport -Name 'lot1.csv' -Entry @(
                (New-TestEntry -Url $url -SiteId $script:SiteA -Date '2024-01-01'),
                (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/hr' -Date '2024-01-01'))))

        foreach ($unknown in '', '00000000-0000-0000-0000-000000000000', 'not a guid') {
            Find-TestLockDate -Index $index -SiteId $unknown -Url $url | Should -BeNullOrEmpty -Because "a replacement site at the address of site A must not inherit its date ([$unknown])"
            Find-TestLockDate -Index $index -SiteId $unknown -Url 'https://contoso.sharepoint.com/sites/hr' | Should -BeNullOrEmpty
        }

        Find-TestLockDate -Index $index -SiteId $script:SiteB -Url $url | Should -BeNullOrEmpty
        (Find-TestLockDate -Index $index -SiteId $script:SiteB -Url 'https://contoso.sharepoint.com/sites/hr').LockedOn.ToString('yyyy-MM-dd') | Should -Be '2024-01-01'
    }

    It 'finds nothing for a site that no source knows, and for no address and no ID' {
        $list = New-TestImport -Name 'lot1.csv' -Entry (New-TestEntry -Url 'https://contoso.sharepoint.com/sites/sales' -SiteId $script:SiteA)
        $index = Merge-TestLockDate -Import @($list)

        Find-TestLockDate -Index $index -SiteId $script:SiteC -Url 'https://contoso.sharepoint.com/sites/other' | Should -BeNullOrEmpty
        Find-TestLockDate -Index $index | Should -BeNullOrEmpty
    }

    It 'gives an index with nothing in it when there is no source, and when every source is empty' {
        $none = Merge-TestLockDate -Import @()
        $empty = Merge-TestLockDate -Import @((New-TestImport -Name 'empty.csv' -Entry @()))

        $none.EntryCount | Should -Be 0
        $empty.EntryCount | Should -Be 0
        Find-TestLockDate -Index $none -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/sales' | Should -BeNullOrEmpty
    }

    It 'says how many rows and entries each source gave' {
        $one = New-TestImport -Name 'one.csv' -Entry @((New-TestEntry -SiteId $script:SiteA), (New-TestEntry -SiteId $script:SiteB))
        $two = New-TestImport -Name 'two.csv' -Entry @((New-TestEntry -SiteId $script:SiteA -Date '2026-01-01'))

        $index = Merge-TestLockDate -Import @($one, $two)

        $index.EntryCount | Should -Be 2
        @($index.Sources | ForEach-Object { "$($_.Name):$($_.RowCount)" }) | Should -Be @('one.csv:2', 'two.csv:1')
    }

    It 'refuses something that is not the import of a list' {
        { Merge-TestLockDate -Import @([PSCustomObject]@{ Name = 'x' }) } | Should -Throw -ExpectedMessage '*Entries*'
    }

    It 'merges 100,000 entries and finds each of them in a reasonable time' -Tag 'Slow' {
        $entries = foreach ($i in 1..100000) {
            [PSCustomObject]@{
                Url      = "https://contoso.sharepoint.com/sites/site$i"
                UrlKey   = "https://contoso.sharepoint.com/sites/site$i"
                SiteId   = [guid]::NewGuid().ToString()
                LockedOn = [System.DateTime]::new(2025, 9, 18, 0, 0, 0, [System.DateTimeKind]::Utc)
                Source   = 'big.csv'
            }
        }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $index = Merge-TestLockDate -Import @((New-TestImport -Name 'big.csv' -Entry $entries))
        $watch.Stop()
        $mergeSeconds = $watch.Elapsed.TotalSeconds

        $watch.Restart()
        $found = 0
        foreach ($entry in $entries) {
            if (Find-TestLockDate -Index $index -SiteId $entry.SiteId -Url $entry.Url) {
                $found++
            }
        }

        $watch.Stop()

        $index.EntryCount | Should -Be 100000
        $found | Should -Be 100000
        $mergeSeconds | Should -BeLessThan 60
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 120
    }
}

Describe 'Get-SPSLifecycleLockDateIndex' {
    BeforeEach {
        $script:Folder = New-TestFolder
    }

    It 'merges the lists and the journal, and the latest date wins' {
        $lot = Write-TestFile -Folder $script:Folder -Name 'lot1.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2025-03-01`r`nhttps://contoso.sharepoint.com/sites/b,,2025-04-01`r`n"
        $journal = Write-TestFile -Folder $script:Folder -Name 'lock-journal.csv' -Text "Url,SiteId,LockedOn`r`nhttps://contoso.sharepoint.com/sites/a,$($script:SiteA),2026-10-29T14:37:39Z`r`n"

        $index = Get-TestIndex -LockDateFile $lot -LockJournal $journal

        $a = Find-TestLockDate -Index $index -SiteId $script:SiteA -Url 'https://contoso.sharepoint.com/sites/a'
        $b = Find-TestLockDate -Index $index -SiteId $script:SiteB -Url 'https://contoso.sharepoint.com/sites/b'
        $a.LockedOn.ToString('yyyy-MM-dd') | Should -Be '2026-10-29'
        $a.Source | Should -BeExactly 'lock-journal.csv'
        $b.Source | Should -BeExactly 'lot1.csv'
        @($index.Sources.Name) | Should -Be @('lot1.csv', 'lock-journal.csv')
    }

    It 'works with no list, and with a journal that does not exist yet' {
        $index = Get-TestIndex -LockJournal (Join-Path -Path $script:Folder -ChildPath 'lock-journal.csv')

        $index.EntryCount | Should -Be 0
        @($index.Sources.Name) | Should -Be @('lock-journal.csv')
    }

    It 'applies the extra date formats to the lists and to the journal' {
        $lot = Write-TestFile -Folder $script:Folder -Name 'lot1.csv' -Text "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/b;01/04/2025`r`n"

        $index = Get-TestIndex -LockDateFile $lot -DateFormat 'dd/MM/yyyy'

        (Find-TestLockDate -Index $index -SiteId $script:SiteB -Url 'https://contoso.sharepoint.com/sites/b').LockedOn.ToString('yyyy-MM-dd') | Should -Be '2025-04-01'
    }

    It 'stops on a list that cannot be read, because a lock date that is lost would hide a recent lock' {
        $lot = Write-TestFile -Folder $script:Folder -Name 'lot1.csv' -Text "Url,LockedOn`r`nhttps://contoso.sharepoint.com/sites/b,not a date`r`n"

        { Get-TestIndex -LockDateFile $lot } | Should -Throw -ExpectedMessage '*lot1.csv*'
    }
}
