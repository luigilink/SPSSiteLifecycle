BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'
    $script:Columns = @('Url', 'SiteId', 'Title', 'Template', 'LockState', 'GroupId', 'IsHubSite', 'IsTeamsConnected', 'IsTeamsChannelConnected', 'ArchiveStatus', 'StorageUsedMB', 'LastContentModified')

    # A .NET object like the ones of the SharePoint admin API: reading a property that was not loaded throws, and PowerShell
    # shows that as $null.
    if (-not ('SPSLifecycleTest.Listing.FakeSiteProperties' -as [type])) {
        Add-Type -TypeDefinition @'
namespace SPSLifecycleTest.Listing
{
    public class FakeSiteProperties
    {
        public System.Collections.Generic.HashSet<string> Unloaded = new System.Collections.Generic.HashSet<string>();

        private T Read<T>(string name, T value)
        {
            if (Unloaded.Contains(name))
            {
                throw new System.InvalidOperationException("The property or field has not been initialized. It has not been requested or the request has not been executed.");
            }

            return value;
        }

        public string Url { get { return Read("Url", "https://contoso.sharepoint.com/sites/a"); } }
        public System.Guid SiteId { get { return Read("SiteId", new System.Guid("a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64")); } }
        public string Title { get { return Read("Title", "Sales"); } }
        public string Template { get { return Read("Template", "GROUP#0"); } }
        public string LockState { get { return Read("LockState", "ReadOnly"); } }
        public System.Guid GroupId { get { return Read("GroupId", new System.Guid("11111111-1111-1111-1111-111111111111")); } }
        public bool IsHubSite { get { return Read("IsHubSite", false); } }
        public bool IsTeamsConnected { get { return Read("IsTeamsConnected", true); } }
        public bool IsTeamsChannelConnected { get { return Read("IsTeamsChannelConnected", false); } }
        public string ArchiveStatus { get { return Read("ArchiveStatus", "NotArchived"); } }
        public long StorageUsage { get { return Read("StorageUsage", 12L); } }
        public System.DateTime LastContentModifiedDate { get { return Read("LastContentModifiedDate", new System.DateTime(2026, 10, 14, 10, 5, 58, System.DateTimeKind.Utc)); } }
    }
}
'@
    }

    # An item as a call gives it, with more properties than the Scan uses (the owner is personal data and never leaves).
    function script:New-TestItem {
        param([hashtable]$Override = @{}, [ValidateSet('Csom', 'Cmdlet')][string]$Source = 'Csom')

        $values = [ordered]@{
            Url                     = 'https://contoso.sharepoint.com/sites/a'
            SiteId                  = [guid]$script:SiteA
            Title                   = 'Sales'
            Template                = 'GROUP#0'
            LockState               = 'ReadOnly'
            GroupId                 = [guid]$script:GroupA
            IsHubSite               = $false
            IsTeamsConnected        = $true
            IsTeamsChannelConnected = $false
            ArchiveStatus           = 'NotArchived'
            LastContentModifiedDate = [System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc)
            Owner                   = 'i:0#.f|membership|someone@contoso.com'
            OwnerEmail              = 'someone@contoso.com'
            SensitivityLabel        = [guid]'33333333-3333-3333-3333-333333333333'
            HasHolds                = $false
        }
        $storage = if ($Source -eq 'Csom') { 'StorageUsage' } else { 'StorageUsageCurrent' }
        $values[$storage] = 12L
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    function script:ConvertTo-TestRecord {
        param($Item, [string]$Source = 'Csom')
        & $script:Module { param($i, $s) ConvertTo-SPSLifecycleSiteRecord -Item $i -Source $s } $Item $Source
    }
}

Describe 'ConvertTo-SPSLifecycleSiteRecord' {
    Context 'The record' {
        It 'has the twelve names of the Scan, in that order, and nothing else (no owner, no label)' {
            $record = ConvertTo-TestRecord -Item (New-TestItem)

            $record.PSObject.Properties.Name | Should -Be $script:Columns
        }

        It 'gives the values of the site, with the types that the Scan core asks for' {
            $record = ConvertTo-TestRecord -Item (New-TestItem)

            $record.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $record.SiteId | Should -BeExactly $script:SiteA
            $record.SiteId | Should -BeOfType [string]
            $record.Title | Should -BeExactly 'Sales'
            $record.Template | Should -BeExactly 'GROUP#0'
            $record.LockState | Should -BeExactly 'ReadOnly'
            $record.GroupId | Should -BeExactly $script:GroupA
            $record.GroupId | Should -BeOfType [string]
            $record.IsHubSite | Should -BeFalse
            $record.IsHubSite | Should -BeOfType [bool]
            $record.IsTeamsConnected | Should -BeTrue
            $record.IsTeamsConnected | Should -BeOfType [bool]
            $record.IsTeamsChannelConnected | Should -BeFalse
            $record.IsTeamsChannelConnected | Should -BeOfType [bool]
            $record.ArchiveStatus | Should -BeExactly 'NotArchived'
            $record.StorageUsedMB | Should -Be 12
            $record.LastContentModified | Should -BeOfType [System.DateTime]
            $record.LastContentModified.Kind | Should -Be ([System.DateTimeKind]::Utc)
            $record.LastContentModified.Ticks | Should -Be ([System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc).Ticks)
        }

        It 'reads a site from the pipeline' {
            $records = @(& $script:Module { param($a, $b) @($a, $b) | ConvertTo-SPSLifecycleSiteRecord -Source Csom } (New-TestItem) (New-TestItem -Override @{ Url = 'https://contoso.sharepoint.com/sites/b' }))

            $records | Should -HaveCount 2
            $records[1].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/b'
        }
    }

    Context 'The storage in use' {
        It 'is StorageUsage for the admin API and StorageUsageCurrent for the cmdlet' {
            (ConvertTo-TestRecord -Item (New-TestItem -Source Csom) -Source Csom).StorageUsedMB | Should -Be 12
            (ConvertTo-TestRecord -Item (New-TestItem -Source Cmdlet) -Source Cmdlet).StorageUsedMB | Should -Be 12
        }

        It 'is not read from the other name: a site that has its size under the other name is refused, as the call is wrong, and its size is not read as zero' {
            { ConvertTo-TestRecord -Item (New-TestItem -Source Cmdlet) -Source Csom } | Should -Throw -ExpectedMessage "*no property 'StorageUsage'*"
            { ConvertTo-TestRecord -Item (New-TestItem -Source Csom) -Source Cmdlet } | Should -Throw -ExpectedMessage "*no property 'StorageUsageCurrent'*"
        }

        It 'refuses a size that is not a number, and names the property and the site' {
            $item = New-TestItem -Override @{ StorageUsage = 'a lot' }

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*'StorageUsage' is not a number of megabytes ('a lot')*"
            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage '*contoso.sharepoint.com/sites/a*'
        }

        It 'is no size, and not the one of a variable that the caller happens to have, when the call gives none' {
            $item = New-TestItem -Override @{ StorageUsage = $null }

            $record = & $script:Module {
                param($i)
                $storageMB = 999
                ConvertTo-SPSLifecycleSiteRecord -Item $i -Source Csom
            } $item

            $null -eq $record.StorageUsedMB | Should -BeTrue
        }

        It 'reads a size that is a whole number, whatever the type that carries it: <Name>' -ForEach @(
            @{ Name = 'a long'; Value = [long]12; Expected = 12 }
            @{ Name = 'an int'; Value = 12; Expected = 12 }
            @{ Name = 'a byte'; Value = [byte]12; Expected = 12 }
            @{ Name = 'an unsigned int'; Value = [uint32]12; Expected = 12 }
            @{ Name = 'a double that is whole'; Value = 12.0; Expected = 12 }
            @{ Name = 'a decimal that is whole'; Value = [decimal]12; Expected = 12 }
            @{ Name = 'a text of digits'; Value = '12'; Expected = 12 }
            @{ Name = 'a text of digits with spaces around'; Value = '  12 '; Expected = 12 }
            @{ Name = 'a text with a plus sign'; Value = '+12'; Expected = 12 }
            @{ Name = 'zero'; Value = [long]0; Expected = 0 }
            @{ Name = 'the largest size'; Value = [long]::MaxValue; Expected = [long]::MaxValue }
        ) {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = $Value })

            $record.StorageUsedMB | Should -BeOfType [long]
            $record.StorageUsedMB | Should -Be $Expected
        }

        It 'reads no size, and not a size of zero, from a blank text: <Name>' -ForEach @(
            @{ Name = 'an empty text'; Value = '' }
            @{ Name = 'spaces'; Value = '   ' }
            @{ Name = 'a tab and a line break'; Value = "`t`r`n" }
        ) {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = $Value })

            $null -eq $record.StorageUsedMB | Should -BeTrue
        }

        It 'refuses what is not a size, and does not turn it into a number: <Name>' -ForEach @(
            @{ Name = 'false'; Value = $false }
            @{ Name = 'true'; Value = $true }
            @{ Name = 'a word'; Value = 'many' }
            @{ Name = 'a fraction as a text'; Value = '1.5' }
            @{ Name = 'a fraction'; Value = 1.5 }
            @{ Name = 'an exponent'; Value = '1e3' }
            @{ Name = 'a thousands separator'; Value = '1,000' }
            @{ Name = 'a number with a space inside'; Value = '1 000' }
            @{ Name = 'a hexadecimal text'; Value = '0x10' }
            @{ Name = 'not a number'; Value = [double]::NaN }
            @{ Name = 'infinity'; Value = [double]::PositiveInfinity }
            @{ Name = 'a number that does not fit'; Value = 1e30 }
            @{ Name = 'an unsigned number that does not fit'; Value = [uint64]::MaxValue }
            @{ Name = 'an object'; Value = (Get-Date) }
            @{ Name = 'a list'; Value = @(1, 2) }
        ) {
            { ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = $Value }) } | Should -Throw -ExpectedMessage "*'StorageUsage' is not a number of megabytes*"
        }

        It 'refuses a size below zero, which no site has, and says so: <Name>' -ForEach @(
            @{ Name = 'a number'; Value = [long]-1 }
            @{ Name = 'a text'; Value = '-5' }
        ) {
            { ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = $Value }) } | Should -Throw -ExpectedMessage "*'StorageUsage' is below zero*"
        }

        It 'stays a size of zero when the site holds nothing' {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = 0L })

            $record.StorageUsedMB | Should -Be 0
            $null -eq $record.StorageUsedMB | Should -BeFalse
        }
    }

    Context 'The identifiers' {
        It 'gives a site ID and a group ID in lowercase, whatever the way they come: <Name>' -ForEach @(
            @{ Name = 'a GUID'; Value = [guid]'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64'; Expected = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64' }
            @{ Name = 'a text in capitals'; Value = 'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64'; Expected = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64' }
            @{ Name = 'a text with braces'; Value = '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}'; Expected = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64' }
            @{ Name = 'a text with spaces around it'; Value = '  a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64 '; Expected = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64' }
        ) {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ SiteId = $Value; GroupId = $Value })

            $record.SiteId | Should -BeExactly $Expected
            $record.GroupId | Should -BeExactly $Expected
        }

        It 'keeps the all-zero group ID that the tenant gives to a site without a group' {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ GroupId = [guid]::Empty })

            $record.GroupId | Should -BeExactly '00000000-0000-0000-0000-000000000000'
        }

        It 'refuses a site ID that is all zeros: it is no identity, and the pager would take every such site for one' {
            { ConvertTo-TestRecord -Item (New-TestItem -Override @{ SiteId = [guid]::Empty }) } | Should -Throw -ExpectedMessage "*'SiteId' is empty*"
            { ConvertTo-TestRecord -Item (New-TestItem -Override @{ SiteId = '00000000-0000-0000-0000-000000000000' }) } | Should -Throw -ExpectedMessage "*'SiteId' is empty*"
        }

        It 'keeps a value that is not a GUID as it is, so that the Scan core stops on it instead of reading no group' {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ SiteId = 'not-a-guid'; GroupId = 'also not a guid' })

            $record.SiteId | Should -BeExactly 'not-a-guid'
            $record.GroupId | Should -BeExactly 'also not a guid'
        }
    }

    Context 'The date of the last change of the content' {
        It 'is a UTC date whatever the kind of the date that the call gives: <Name>' -ForEach @(
            @{ Name = 'UTC'; Value = [System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc); Expected = [System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc) }
            @{ Name = 'no kind, which SharePoint writes in UTC'; Value = [System.DateTime]::new(2026, 10, 14, 10, 5, 58); Expected = [System.DateTime]::new(2026, 10, 14, 10, 5, 58, [System.DateTimeKind]::Utc) }
            @{ Name = 'local'; Value = [System.DateTime]::new(2026, 10, 14, 12, 5, 58, [System.DateTimeKind]::Local); Expected = [System.DateTime]::new(2026, 10, 14, 12, 5, 58, [System.DateTimeKind]::Local).ToUniversalTime() }
        ) {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ LastContentModifiedDate = $Value })

            $record.LastContentModified.Kind | Should -Be ([System.DateTimeKind]::Utc)
            $record.LastContentModified.Ticks | Should -Be $Expected.Ticks
        }

        It 'refuses a value that is not a date, and names the property and the site: <Name>' -ForEach @(
            @{ Name = 'a number'; Value = 42 }
            @{ Name = 'a text'; Value = 'last Tuesday' }
        ) {
            $item = New-TestItem -Override @{ LastContentModifiedDate = $Value }

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*the property 'LastContentModifiedDate'*"
            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage '*contoso.sharepoint.com/sites/a*'
        }

        It 'is no date when the call gives the empty date of .NET, which is not a date of the site' {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ LastContentModifiedDate = [System.DateTime]::MinValue })

            $null -eq $record.LastContentModified | Should -BeTrue
        }
    }

    Context 'A property that cannot be read' {
        It 'stops on a null <Name>: a value that is never null was not loaded, and reading it as "no group" or "not a hub site" would hide a safeguard' -ForEach @(
            @{ Name = 'SiteId' }
            @{ Name = 'GroupId' }
            @{ Name = 'IsHubSite' }
            @{ Name = 'IsTeamsConnected' }
            @{ Name = 'IsTeamsChannelConnected' }
        ) {
            $item = New-TestItem -Override @{ $Name = $null }

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*'https://contoso.sharepoint.com/sites/a'*'$Name'*"
        }

        It 'stops on a flag that is not a boolean: <Name>' -ForEach @(
            @{ Name = 'a text'; Value = 'True' }
            @{ Name = 'a number'; Value = 1 }
        ) {
            $item = New-TestItem -Override @{ IsHubSite = $Value }

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*'IsHubSite'*boolean*"
        }

        It 'stops on a property that a .NET object could not read (PowerShell gives null for it)' {
            $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
            $null = $item.Unloaded.Add('GroupId')

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*'GroupId'*"
        }

        It 'reads a .NET object of the admin API' {
            $record = ConvertTo-TestRecord -Item ([SPSLifecycleTest.Listing.FakeSiteProperties]::new())

            $record.Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/a'
            $record.StorageUsedMB | Should -Be 12
            $record.GroupId | Should -BeExactly $script:GroupA
        }

        It 'stops on an item that is null' {
            { ConvertTo-TestRecord -Item $null } | Should -Throw -ExpectedMessage '*empty*'
        }

        It 'leaves a missing text empty and a missing size or date unknown, and the Scan core says what it cannot use' {
            $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ Title = $null; Url = $null; Template = $null; LockState = $null; ArchiveStatus = $null; StorageUsage = $null; LastContentModifiedDate = $null })

            $record.Title | Should -BeExactly ''
            $record.Url | Should -BeExactly ''
            $record.Template | Should -BeExactly ''
            $record.LockState | Should -BeExactly ''
            $record.ArchiveStatus | Should -BeExactly ''
            $null -eq $record.StorageUsedMB | Should -BeTrue
            $null -eq $record.LastContentModified | Should -BeTrue
        }
    }

    Context 'A property that was not loaded' {
        It 'is found on a site, whichever the property: <Name>' -ForEach @(
            @{ Name = 'Url' }
            @{ Name = 'SiteId' }
            @{ Name = 'Title' }
            @{ Name = 'Template' }
            @{ Name = 'LockState' }
            @{ Name = 'GroupId' }
            @{ Name = 'IsHubSite' }
            @{ Name = 'IsTeamsConnected' }
            @{ Name = 'IsTeamsChannelConnected' }
            @{ Name = 'ArchiveStatus' }
            @{ Name = 'StorageUsage' }
            @{ Name = 'LastContentModifiedDate' }
        ) {
            $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
            $null = $item.Unloaded.Add($Name)

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage "*'$Name'*not been loaded*"
        }

        It 'is not mistaken for a date that the site does not have, which would take a protection away from it' {
            $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
            $null = $item.Unloaded.Add('LastContentModifiedDate')

            { ConvertTo-TestRecord -Item $item } | Should -Throw -ExpectedMessage '*reading it fails: The property or field has not been initialized*'
        }

        It 'is not found on a site that has everything, including the empty date of .NET, which is a date that the site does not have' {
            $item = New-TestItem -Override @{ LastContentModifiedDate = [System.DateTime]::MinValue }

            $null -eq (ConvertTo-TestRecord -Item $item).LastContentModified | Should -BeTrue
        }
    }

    Context 'The text of the tenant' {
        It 'is given as it is: <Name>' -ForEach @(
            @{ Name = 'a title with accents and quotes'; Title = "L'équipe ""Ventes"" 2026" }
            @{ Name = 'a title with a line break and a tab'; Title = "line 1`r`nline 2`tend" }
            @{ Name = 'a title with a character outside the basic plane'; Title = "Team $([char]::ConvertFromUtf32(0x1F680))" }
            @{ Name = 'a title with spaces around it'; Title = '  padded  ' }
        ) {
            (ConvertTo-TestRecord -Item (New-TestItem -Override @{ Title = $Title })).Title | Should -BeExactly $Title
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
                $record = ConvertTo-TestRecord -Item (New-TestItem -Override @{ StorageUsage = 1234567L; SiteId = 'A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64' })

                $record.StorageUsedMB | Should -Be 1234567
                $record.SiteId | Should -BeExactly $script:SiteA
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }
        }
    }
}

Describe 'Assert-SPSLifecycleSiteLoaded' {
    BeforeAll {
        function script:Assert-TestLoaded {
            param($Item, [string]$Source = 'Csom')
            & $script:Module { param($i, $s) Assert-SPSLifecycleSiteLoaded -Item $i -Source $s } $Item $Source
        }
    }

    It 'accepts a .NET object of the admin API that has everything loaded' {
        { Assert-TestLoaded -Item ([SPSLifecycleTest.Listing.FakeSiteProperties]::new()) } | Should -Not -Throw
    }

    It 'names the property that a .NET object cannot read: <Name>' -ForEach @(
        @{ Name = 'GroupId' }
        @{ Name = 'IsHubSite' }
        @{ Name = 'ArchiveStatus' }
        @{ Name = 'StorageUsage' }
        @{ Name = 'LastContentModifiedDate' }
    ) {
        $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
        $null = $item.Unloaded.Add($Name)

        { Assert-TestLoaded -Item $item } | Should -Throw -ExpectedMessage "*'$Name'*not been loaded*"
    }

    It 'says that the site is empty, and does not go on to read its type' {
        { Assert-TestLoaded -Item $null } | Should -Throw -ExpectedMessage '*empty (null)*'
    }

    It 'gives the reason of the server, not the one of the reflection that read the property' {
        $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
        $null = $item.Unloaded.Add('GroupId')

        $message = try { Assert-TestLoaded -Item $item } catch { $_.Exception.Message }

        $message | Should -BeLike '*reading it fails: The property or field has not been initialized*'
        $message | Should -Not -BeLike '*target of an invocation*'
    }

    It 'accepts an object that has all the properties, whatever their values' {
        { Assert-TestLoaded -Item (New-TestItem -Override @{ GroupId = $null }) } | Should -Not -Throw
    }

    It 'names a property that an object does not have: <Source>' -ForEach @(
        @{ Source = 'Csom'; Missing = 'StorageUsage'; ItemSource = 'Cmdlet' }
        @{ Source = 'Cmdlet'; Missing = 'StorageUsageCurrent'; ItemSource = 'Csom' }
    ) {
        $item = New-TestItem -Source $ItemSource

        { Assert-TestLoaded -Item $item -Source $Source } | Should -Throw -ExpectedMessage "*'$Missing'*"
    }
}
