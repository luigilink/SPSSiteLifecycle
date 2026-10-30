BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Manifest = $manifest
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc)
    $script:SiteA = 'a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64'
    $script:GroupA = '11111111-1111-1111-1111-111111111111'

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

    # Types that have the shape of the ones of the admin API (and some that lack one thing), to test the check that is made on them.
    if (-not ('SPSLifecycleTest.Api.SiteFilter' -as [type])) {
        Add-Type -TypeDefinition @'
namespace SPSLifecycleTest.Api
{
    public enum PersonalSiteFilter { UseServerDefault, Include, Exclude }
    public enum PersonalSiteFilterNoExclude { UseServerDefault, Include }
    public class SiteCollection { public string NextStartIndexFromSharePoint { get; set; } }
    public class SiteCollectionNoToken { public int Count { get; set; } }
    public class SiteCollectionNumberToken { public int NextStartIndexFromSharePoint { get; set; } }
    public class SiteFilter
    {
        public string Filter { get; set; }
        public bool IncludeDetail { get; set; }
        public PersonalSiteFilter IncludePersonalSite { get; set; }
        public string StartIndex { get; set; }
    }
    public class SiteFilterNoStartIndex
    {
        public string Filter { get; set; }
        public bool IncludeDetail { get; set; }
        public PersonalSiteFilter IncludePersonalSite { get; set; }
    }
    public class SiteFilterNumberStartIndex
    {
        public string Filter { get; set; }
        public bool IncludeDetail { get; set; }
        public PersonalSiteFilter IncludePersonalSite { get; set; }
        public int StartIndex { get; set; }
    }
    public class SiteFilterReadOnlyDetail
    {
        public string Filter { get; set; }
        public bool IncludeDetail { get { return true; } }
        public PersonalSiteFilter IncludePersonalSite { get; set; }
        public string StartIndex { get; set; }
    }
    public class SiteFilterOtherEnum
    {
        public string Filter { get; set; }
        public bool IncludeDetail { get; set; }
        public PersonalSiteFilterNoExclude IncludePersonalSite { get; set; }
        public string StartIndex { get; set; }
    }
    public class Tenant { public SiteCollection GetSitePropertiesFromSharePointByFilters(SiteFilter filter) { return null; } }
    public class TenantNoMethod { public SiteCollection Other(SiteFilter filter) { return null; } }
    public class TenantOtherArgument { public SiteCollection GetSitePropertiesFromSharePointByFilters(string filter) { return null; } }
    public class TenantNoTokenResult { public SiteCollectionNoToken GetSitePropertiesFromSharePointByFilters(SiteFilter filter) { return null; } }
    public class TenantNumberTokenResult { public SiteCollectionNumberToken GetSitePropertiesFromSharePointByFilters(SiteFilter filter) { return null; } }
    public class DisposableContext : System.IDisposable
    {
        public bool Disposed;
        public bool Throws;
        public void Dispose() { if (Throws) { throw new System.InvalidOperationException("cannot dispose"); } Disposed = true; }
    }
}
'@
    }

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
            Owner                   = 'someone@contoso.com'
        }
        $values[$(if ($Source -eq 'Csom') { 'StorageUsage' } else { 'StorageUsageCurrent' })] = 12L
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    function script:New-TestSetting {
        param([hashtable]$Override = @{})

        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $values = [ordered]@{
            TenantName     = 'contoso'
            AdminUrl       = 'https://contoso-admin.sharepoint.com'
            ClientId       = '11111111-2222-3333-4444-555555555555'
            RefusedTenants = @('microsoft', 'microsoftonline')
            OutputFolder   = $folder
            Scan           = [PSCustomObject]@{ LockStates = @('ReadOnly') }
        }
        foreach ($key in $Override.Keys) {
            $values[$key] = $Override[$key]
        }

        [PSCustomObject]$values
    }

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'The tests of the adapters cannot reach a tenant' {
    It 'has replaced every command that reaches a tenant, inside the module, before any test runs: <Name>' -ForEach @(
        @{ Name = 'Connect-PnPOnline' }
        @{ Name = 'Get-PnPContext' }
        @{ Name = 'Invoke-PnPQuery' }
        @{ Name = 'Get-PnPTenantSite' }
        @{ Name = 'Disconnect-PnPOnline' }
    ) {
        Assert-ModuleStub -Name $Name

        { & $script:Module { param($n) & $n -Url 'https://contoso-admin.sharepoint.com' } $Name } | Should -Throw -ExpectedMessage "*called $Name for real*"
    }

    It 'stops a test whose stub is not in place, instead of running the real command' {
        { Assert-ModuleStub -Name 'Get-Date' } | Should -Throw -ExpectedMessage '*not in place*Get-Date*not a stub*'
        { Assert-ModuleStub -Name 'Invoke-SPSLifecycleTestCommandThatDoesNotExist' } | Should -Throw -ExpectedMessage '*nothing*'
    }

    It 'puts a stub where the code of the module finds it, and takes it away afterwards' {
        Set-ModuleStub -Stub @{ 'Invoke-SPSLifecycleTestOnlyCommand' = "'stubbed'" }
        try {
            & $script:Module { Invoke-SPSLifecycleTestOnlyCommand } | Should -BeExactly 'stubbed'
        }
        finally {
            Clear-ModuleStub
        }

        { & $script:Module { Invoke-SPSLifecycleTestOnlyCommand } } | Should -Throw -ExpectedMessage '*not recognized*'
    }

    It 'gives a function of the module back as it was, and working, after a test replaced it' {
        $before = & $script:Module { (Get-Command Get-SPSLifecycleListingColumn).Definition }
        Set-ModuleStub -Stub @{ 'Get-SPSLifecycleListingColumn' = "'stubbed'" }
        try {
            & $script:Module { Get-SPSLifecycleListingColumn } | Should -BeExactly 'stubbed'
        }
        finally {
            Clear-ModuleStub
        }

        & $script:Module { (Get-Command Get-SPSLifecycleListingColumn).Definition } | Should -BeExactly $before
        @(& $script:Module { Get-SPSLifecycleListingColumn }) | Should -HaveCount 12
    }

    It 'keeps the traps in place after a test replaced one of them and cleared its stubs' {
        Set-ModuleStub -Stub @{ 'Connect-PnPOnline' = "'recorded'" }
        try {
            & $script:Module { Connect-PnPOnline } | Should -BeExactly 'recorded'
        }
        finally {
            Clear-ModuleStub
        }

        Assert-ModuleStub -Name $script:TenantCommand
        { & $script:Module { Connect-PnPOnline -Url 'https://contoso-admin.sharepoint.com' -Interactive } } | Should -Throw -ExpectedMessage '*for real*'
    }
}

Describe 'Test-SPSLifecycleListingApiType' {
    BeforeAll {
        function script:Test-TestApi {
            param($Tenant = 'Tenant', $Filter = 'SiteFilter', $Personal = 'PersonalSiteFilter')
            $resolve = { param($name) if ($name) { "SPSLifecycleTest.Api.$name" -as [System.Type] } else { $null } }
            $t = & $resolve $Tenant
            $f = & $resolve $Filter
            $p = & $resolve $Personal
            & $script:Module { param($t, $f, $p) Test-SPSLifecycleListingApiType -TenantType $t -FilterType $f -PersonalSiteFilterType $p } $t $f $p
        }
    }

    It 'accepts types that have what the paged listing uses' {
        $result = Test-TestApi

        $result.Available | Should -BeTrue
        $result.Reason | Should -BeExactly ''
    }

    It 'refuses types that are not there: <Name>' -ForEach @(
        @{ Name = 'no tenant type'; Tenant = ''; Filter = 'SiteFilter'; Personal = 'PersonalSiteFilter' }
        @{ Name = 'no filter type'; Tenant = 'Tenant'; Filter = ''; Personal = 'PersonalSiteFilter' }
        @{ Name = 'no enumeration'; Tenant = 'Tenant'; Filter = 'SiteFilter'; Personal = '' }
    ) {
        $result = Test-TestApi -Tenant $Tenant -Filter $Filter -Personal $Personal

        $result.Available | Should -BeFalse
        $result.Reason | Should -BeLike '*are not in this PnP.PowerShell*'
    }

    It 'refuses a filter that is not what the call is given: <Name>' -ForEach @(
        @{ Name = 'a property that is missing'; Filter = 'SiteFilterNoStartIndex'; Expected = "*'StartIndex'*" }
        @{ Name = 'a property of another type'; Filter = 'SiteFilterNumberStartIndex'; Expected = "*'StartIndex'*String*" }
        @{ Name = 'a property that cannot be written'; Filter = 'SiteFilterReadOnlyDetail'; Expected = "*'IncludeDetail'*writable*" }
        @{ Name = 'a property of the wrong enumeration'; Filter = 'SiteFilterOtherEnum'; Expected = "*'IncludePersonalSite'*" }
    ) {
        $result = Test-TestApi -Filter $Filter

        $result.Available | Should -BeFalse
        $result.Reason | Should -BeLike $Expected
    }

    It 'refuses an enumeration that has no value to leave the OneDrive sites out' {
        $result = Test-TestApi -Filter 'SiteFilterOtherEnum' -Personal 'PersonalSiteFilterNoExclude'

        $result.Available | Should -BeFalse
        $result.Reason | Should -BeLike "*'Exclude'*"
    }

    It 'refuses a tenant whose call is not the one that the listing makes: <Name>' -ForEach @(
        @{ Name = 'no method'; Tenant = 'TenantNoMethod'; Expected = '*GetSitePropertiesFromSharePointByFilters*' }
        @{ Name = 'a method that takes another argument'; Tenant = 'TenantOtherArgument'; Expected = '*GetSitePropertiesFromSharePointByFilters*' }
        @{ Name = 'a page without a token'; Tenant = 'TenantNoTokenResult'; Expected = "*'NextStartIndexFromSharePoint'*" }
        @{ Name = 'a page whose token is a number'; Tenant = 'TenantNumberTokenResult'; Expected = "*'NextStartIndexFromSharePoint'*" }
    ) {
        $result = Test-TestApi -Tenant $Tenant

        $result.Available | Should -BeFalse
        $result.Reason | Should -BeLike $Expected
    }

    It 'finds the real types of the installed PnP.PowerShell with the members that the listing uses, without loading the module' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        # Only the libraries of types are loaded, in a process of their own, and that process keeps only the modules of PowerShell
        # itself on its module path: a command that is not defined would otherwise load PnP.PowerShell by itself, with its sign-in
        # commands. The test checks that neither the module nor a sign-in command is there.
        $base = (Get-Module -ListAvailable -Name 'PnP.PowerShell' | Sort-Object -Property Version -Descending | Select-Object -First 1).ModuleBase
        $script = @'
$env:PSModulePath = [System.IO.Path]::Combine($PSHOME, 'Modules')
$ErrorActionPreference = 'Stop'
foreach ($name in 'Microsoft.SharePoint.Client.dll', 'Microsoft.SharePoint.Client.Runtime.dll', 'Microsoft.Online.SharePoint.Client.Tenant.dll') {
    $null = [System.Reflection.Assembly]::LoadFrom((Join-Path -Path '@BASE@' -ChildPath "Core/$name"))
}

Import-Module -Name '@MANIFEST@' -Force
$module = Get-Module -Name SPSSiteLifecycle.Common
& $module {
    $api = Test-SPSLifecycleListingApi
    $request = Get-SPSLifecycleListingRequest -Filter "LockState -eq 'ReadOnly'" -StartIndex 'token-1'
    $first = Get-SPSLifecycleListingRequest -Filter '' -StartIndex ''
    [PSCustomObject]@{
        Available     = $api.Available
        Reason        = $api.Reason
        IncludeDetail = $request.IncludeDetail
        Personal      = "$($request.IncludePersonalSite)"
        Filter        = $request.Filter
        StartIndex    = $request.StartIndex
        FirstFilter   = "$($first.Filter)"
        FirstStart    = "$($first.StartIndex)"
        ModuleLoaded  = [bool](Get-Module -Name 'PnP.PowerShell')
        SignInKnown   = [bool](Get-Command -Name 'Connect-PnPOnline' -ErrorAction SilentlyContinue)
    } | ConvertTo-Json -Compress
}
'@
        $path = Join-Path -Path $TestDrive -ChildPath 'real-types.ps1'
        [System.IO.File]::WriteAllText($path, $script.Replace('@BASE@', $base.Replace("'", "''")).Replace('@MANIFEST@', $script:Manifest.Replace("'", "''")))

        $output = & (Join-Path -Path $PSHOME -ChildPath 'pwsh') -NoProfile -NonInteractive -File $path

        $LASTEXITCODE | Should -Be 0
        $result = ($output | Select-Object -Last 1) | ConvertFrom-Json
        $result.Reason | Should -BeExactly ''
        $result.Available | Should -BeTrue
        $result.IncludeDetail | Should -BeTrue
        $result.Personal | Should -BeExactly 'Exclude'
        $result.Filter | Should -BeExactly "LockState -eq 'ReadOnly'"
        $result.StartIndex | Should -BeExactly 'token-1'
        $result.FirstFilter | Should -BeExactly ''
        $result.FirstStart | Should -BeExactly ''
        $result.ModuleLoaded | Should -BeFalse -Because 'the module is never imported by a test'
        $result.SignInKnown | Should -BeFalse -Because 'no sign-in command may exist in that process'
    }

    It 'says that the types are not there when PnP.PowerShell is not loaded' -Skip:([bool]('Microsoft.Online.SharePoint.TenantAdministration.Tenant' -as [System.Type])) {
        $result = & $script:Module { Test-SPSLifecycleListingApi }

        $result.Available | Should -BeFalse
        $result.Reason | Should -BeLike '*are not in this PnP.PowerShell*'
    }
}

Describe 'ConvertTo-SPSLifecycleSitePage' {
    BeforeAll {
        function script:ConvertTo-TestPage {
            param($Item, [string]$Source = 'Csom', $NextStartIndex = 'next-1')
            & $script:Module { param($i, $s, $n) ConvertTo-SPSLifecycleSitePage -Item $i -Source $s -NextStartIndex $n } $Item $Source $NextStartIndex
        }
    }

    It 'gives the sites of the call as records, and the token of the next page' {
        $page = ConvertTo-TestPage -Item @((New-TestItem), (New-TestItem -Override @{ Url = 'https://contoso.sharepoint.com/sites/b'; SiteId = [guid]'0d7b4ebb-f68c-4f29-8529-5b46655d0c3c' }))

        $page.NextStartIndex | Should -BeExactly 'next-1'
        $page.Items | Should -HaveCount 2
        $page.Items[0].PSObject.Properties.Name | Should -Contain 'StorageUsedMB'
        $page.Items[0].PSObject.Properties.Name | Should -Not -Contain 'Owner'
        $page.Items[1].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/b'
        $page.Items[1].SiteId | Should -BeExactly '0d7b4ebb-f68c-4f29-8529-5b46655d0c3c'
    }

    It 'gives a page that holds no site, with its token: a server filter makes them common' {
        $page = ConvertTo-TestPage -Item @()

        @($page.Items) | Should -HaveCount 0
        $page.NextStartIndex | Should -BeExactly 'next-1'
    }

    It 'gives a page for a call that gave nothing at all' {
        $page = ConvertTo-TestPage -Item $null

        @($page.Items) | Should -HaveCount 0
    }

    It 'gives no token after the last page: <Name>' -ForEach @(
        @{ Name = 'an empty text'; Token = '' }
        @{ Name = 'null'; Token = $null }
    ) {
        (ConvertTo-TestPage -Item @((New-TestItem)) -NextStartIndex $Token).NextStartIndex | Should -BeExactly ''
    }

    It 'reads the storage under the name of the call: <Source>' -ForEach @(
        @{ Source = 'Csom' }
        @{ Source = 'Cmdlet' }
    ) {
        (ConvertTo-TestPage -Item @((New-TestItem -Source $Source)) -Source $Source).Items[0].StorageUsedMB | Should -Be 12
    }

    It 'stops on a page whose first site has a property that was not loaded, and names it: a group ID that reads as null would read as no group for every site' {
        $item = [SPSLifecycleTest.Listing.FakeSiteProperties]::new()
        $null = $item.Unloaded.Add('GroupId')

        { ConvertTo-TestPage -Item @($item, (New-TestItem)) } | Should -Throw -ExpectedMessage "*'GroupId'*not been loaded*"
    }

    It 'stops on a site that is not the first of the page, and names its property: <Position>' -ForEach @(
        @{ Position = 'the second'; Index = 1 }
        @{ Position = 'the last of three'; Index = 2 }
    ) {
        $sites = @(1..3 | ForEach-Object { [SPSLifecycleTest.Listing.FakeSiteProperties]::new() })
        $null = $sites[$Index].Unloaded.Add('LastContentModifiedDate')

        { ConvertTo-TestPage -Item $sites } | Should -Throw -ExpectedMessage "*'LastContentModifiedDate'*not been loaded*"
    }

    It 'gives the sites of a .NET object of the admin API' {
        $page = ConvertTo-TestPage -Item @([SPSLifecycleTest.Listing.FakeSiteProperties]::new())

        $page.Items | Should -HaveCount 1
        $page.Items[0].GroupId | Should -BeExactly $script:GroupA
        $page.Items[0].StorageUsedMB | Should -Be 12
    }

    It 'stops on a site that has a null flag, with its address' {
        { ConvertTo-TestPage -Item @((New-TestItem), (New-TestItem -Override @{ Url = 'https://contoso.sharepoint.com/sites/bad'; IsHubSite = $null })) } | Should -Throw -ExpectedMessage "*sites/bad*'IsHubSite'*"
    }
}

Describe 'Assert-SPSLifecyclePnPModule' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-Module'    = @'
[CmdletBinding()]
param([string]$Name, [switch]$ListAvailable)
$script:StubLog.Add("Get-Module ListAvailable=$($ListAvailable.IsPresent)")
if ($ListAvailable) { $script:StubData.Available } else { $script:StubData.Loaded }
'@
            'Import-Module' = @'
[CmdletBinding()]
param([string]$Name, [version]$MinimumVersion, [switch]$PassThru)
$script:StubLog.Add("Import-Module $Name $MinimumVersion")
$script:StubData.Imported
'@
        } -Data @{ Loaded = $null; Available = @(); Imported = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Set-TestModules {
            param($Loaded = $null, $Available = @(), $Imported = $null)
            & $script:Module { param($l, $a, $i) $script:StubData.Loaded = $l; $script:StubData.Available = $a; $script:StubData.Imported = $i } $Loaded $Available $Imported
        }

        function script:New-TestModuleInfo {
            param([string]$Version)
            [PSCustomObject]@{ Name = 'PnP.PowerShell'; Version = [System.Version]$Version }
        }
    }

    It 'uses a version 3 that is already loaded, and loads nothing' {
        Set-TestModules -Loaded (New-TestModuleInfo -Version '3.4.1')

        { & $script:Module { Assert-SPSLifecyclePnPModule } } | Should -Not -Throw

        Get-StubLog | Should -Be @('Get-Module ListAvailable=False')
    }

    It 'loads the newest version that is installed, with a minimum of 3.0' {
        Set-TestModules -Available @((New-TestModuleInfo -Version '2.12.0'), (New-TestModuleInfo -Version '3.4.1')) -Imported (New-TestModuleInfo -Version '3.4.1')

        { & $script:Module { Assert-SPSLifecyclePnPModule } } | Should -Not -Throw

        Get-StubLog | Should -Be @('Get-Module ListAvailable=False', 'Get-Module ListAvailable=True', 'Import-Module PnP.PowerShell 3.0.0')
    }

    It 'says how to install it when it is not installed' {
        { & $script:Module { Assert-SPSLifecyclePnPModule } } | Should -Throw -ExpectedMessage '*not installed*Install-Module*'

        Get-StubLog | Should -Not -Contain 'Import-Module PnP.PowerShell 3.0.0'
    }

    It 'refuses a version 2 that is installed, and does not load it' {
        Set-TestModules -Available @((New-TestModuleInfo -Version '2.12.0'))

        { & $script:Module { Assert-SPSLifecyclePnPModule } } | Should -Throw -ExpectedMessage '*2.12.0*too old*'

        Get-StubLog | Should -Not -Contain 'Import-Module PnP.PowerShell 3.0.0'
    }

    It 'refuses a version 2 that is already loaded, which a new session replaces' {
        Set-TestModules -Loaded (New-TestModuleInfo -Version '2.12.0')

        { & $script:Module { Assert-SPSLifecyclePnPModule } } | Should -Throw -ExpectedMessage '*2.12.0*new PowerShell session*'
    }
}

Describe 'Open-SPSLifecycleTenantSession' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Assert-SPSLifecyclePnPModule' = @'
$script:StubLog.Add('module checked')
'@
            'Connect-PnPOnline'            = @'
[CmdletBinding()]
param([string]$Url, [switch]$Interactive, [string]$ClientId, [string]$Tenant, [switch]$ReturnConnection)
$script:StubLog.Add("Connect-PnPOnline Url=$Url Interactive=$($Interactive.IsPresent) ClientId=$ClientId Tenant=$Tenant ReturnConnection=$($ReturnConnection.IsPresent)")
if ($script:StubData.ConnectFails) { throw 'AADSTS50020: the account does not exist in the tenant.' }
if ($script:StubData.ConnectWritesError) { Write-Error 'The sign-in window was closed.'; return }
if ($script:StubData.ConnectGivesNothing) { return }
'a connection'
'@
        } -Data @{ ConnectFails = $false; ConnectWritesError = $false; ConnectGivesNothing = $false }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Open-TestSession {
            param($Setting)
            & $script:Module { param($s) Open-SPSLifecycleTenantSession -Setting $s } $Setting
        }
    }

    It 'signs in to the admin site with the client ID of the settings, interactively, and keeps the connection to itself' {
        $session = Open-TestSession -Setting (New-TestSetting)

        Get-StubLog | Should -Be @(
            'module checked'
            'Connect-PnPOnline Url=https://contoso-admin.sharepoint.com Interactive=True ClientId=11111111-2222-3333-4444-555555555555 Tenant=contoso.onmicrosoft.com ReturnConnection=True'
        )
        $session.Connection | Should -BeExactly 'a connection'
        $session.TenantName | Should -BeExactly 'contoso'
        $session.AdminUrl | Should -BeExactly 'https://contoso-admin.sharepoint.com'
    }

    It 'writes the tenant of the sign-in in lowercase, as the initial domain of a tenant is' {
        $null = Open-TestSession -Setting (New-TestSetting -Override @{ TenantName = 'Contoso' })

        @(Get-StubLog)[1] | Should -BeLike '*Tenant=contoso.onmicrosoft.com*'
    }

    It 'does not sign in, and does not even load PnP.PowerShell, to a tenant that is refused: <Name>' -ForEach @(
        @{ Name = 'a Microsoft tenant'; Override = @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' } }
        @{ Name = 'a tenant of the settings'; Override = @{ TenantName = 'fabrikam'; AdminUrl = 'https://fabrikam-admin.sharepoint.com'; RefusedTenants = @('fabrikam') } }
        @{ Name = 'an admin address that is for a refused tenant'; Override = @{ AdminUrl = 'https://microsoft-admin.sharepoint.com' } }
        @{ Name = 'an admin address that is for another tenant'; Override = @{ AdminUrl = 'https://fabrikam-admin.sharepoint.com' } }
    ) {
        { Open-TestSession -Setting (New-TestSetting -Override $Override) } | Should -Throw

        Get-StubLog | Should -HaveCount 0
    }

    It 'stops when there is no client ID, before it signs in' {
        { Open-TestSession -Setting (New-TestSetting -Override @{ ClientId = '' }) } | Should -Throw -ExpectedMessage '*ClientId*'

        Get-StubLog | Should -HaveCount 0
    }

    It 'stops when the sign-in reports an error without throwing and gives nothing: a session with no connection would use the one that the user already has, maybe of another tenant' {
        & $script:Module { $script:StubData.ConnectWritesError = $true }

        { Open-TestSession -Setting (New-TestSetting) } | Should -Throw -ExpectedMessage '*sign-in*failed*window was closed*'
    }

    It 'stops when the sign-in gives no connection and no error' {
        & $script:Module { $script:StubData.ConnectGivesNothing = $true }

        { Open-TestSession -Setting (New-TestSetting) } | Should -Throw -ExpectedMessage '*sign-in*no connection*'
    }

    It 'says that the sign-in failed, and why' {
        & $script:Module { $script:StubData.ConnectFails = $true }

        { Open-TestSession -Setting (New-TestSetting) } | Should -Throw -ExpectedMessage '*sign-in*failed*AADSTS50020*'
    }
}

Describe 'Close-SPSLifecycleTenantSession' {
    It 'disposes the context of the connection, which is what releases it' {
        $context = [SPSLifecycleTest.Api.DisposableContext]::new()
        $session = [PSCustomObject]@{ Connection = [PSCustomObject]@{ Context = $context } }

        & $script:Module { param($s) Close-SPSLifecycleTenantSession -Session $s } $session

        $context.Disposed | Should -BeTrue
    }

    It 'does nothing for a session that was never opened: <Name>' -ForEach @(
        @{ Name = 'null'; Session = $null }
        @{ Name = 'a session without a connection'; Session = [PSCustomObject]@{ Connection = $null } }
    ) {
        { & $script:Module { param($s) Close-SPSLifecycleTenantSession -Session $s } $Session } | Should -Not -Throw
    }

    It 'does not let a failure to close hide why the run ended' {
        $context = [SPSLifecycleTest.Api.DisposableContext]::new()
        $context.Throws = $true
        $session = [PSCustomObject]@{ Connection = [PSCustomObject]@{ Context = $context } }

        { & $script:Module { param($s) Close-SPSLifecycleTenantSession -Session $s } $session } | Should -Not -Throw
    }
}

Describe 'Get-SPSLifecycleTenantSitePage with Get-PnPTenantSite' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Get-PnPTenantSite' = @'
[CmdletBinding()]
param([switch]$Detailed, [string]$Filter, $Connection, [switch]$IncludeOneDriveSites)
$script:StubLog.Add("Get-PnPTenantSite Detailed=$($Detailed.IsPresent) Filter=[$Filter] Connection=$Connection IncludeOneDriveSites=$($IncludeOneDriveSites.IsPresent)")
$script:StubData.Items
if ($script:StubData.WritesError) { Write-Error 'Access denied for a part of the tenant.' }
'@
        } -Data @{ Items = @(); WritesError = $false }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:Get-TestCmdletPage {
            param([string]$Filter = '', $Items = @())
            & $script:Module { param($items) $script:StubData.Items = $items } $Items
            $session = [PSCustomObject]@{ Connection = 'a connection' }
            & $script:Module { param($s, $f) Get-SPSLifecycleTenantSitePage -Session $s -Source Cmdlet -StartIndex '' -Filter $f } $session $Filter
        }
    }

    It 'asks for the details, with the connection of the session, the filter that it was given, and not for the OneDrive sites' {
        $page = Get-TestCmdletPage -Filter "LockState -eq 'ReadOnly'" -Items @((New-TestItem -Source Cmdlet))

        Get-StubLog | Should -Be @("Get-PnPTenantSite Detailed=True Filter=[LockState -eq 'ReadOnly'] Connection=a connection IncludeOneDriveSites=False")
        $page.Items | Should -HaveCount 1
        $page.Items[0].StorageUsedMB | Should -Be 12
    }

    It 'gives the whole listing as one page, with no token, so that it is never resumed' {
        $page = Get-TestCmdletPage -Items @((New-TestItem -Source Cmdlet), (New-TestItem -Source Cmdlet -Override @{ Url = 'https://contoso.sharepoint.com/sites/b' }))

        $page.Items | Should -HaveCount 2
        $page.NextStartIndex | Should -BeExactly ''
    }

    It 'asks for no filter when it has none' {
        $null = Get-TestCmdletPage -Items @((New-TestItem -Source Cmdlet))

        @(Get-StubLog)[0] | Should -BeLike '*Filter=[[]]*'
    }

    It 'stops when the cmdlet gives some sites and reports an error without throwing: a part of the tenant that was not read must not look like a complete listing' {
        & $script:Module { $script:StubData.WritesError = $true }

        { Get-TestCmdletPage -Items @((New-TestItem -Source Cmdlet)) } | Should -Throw -ExpectedMessage '*Access denied for a part of the tenant*'
    }

    It 'gives an empty page for a tenant of no site' {
        $page = Get-TestCmdletPage -Items @()

        @($page.Items) | Should -HaveCount 0
    }
}

Describe 'Get-SPSLifecycleTenantSitePage with the paged call, on the real types of the admin API' {
    # The real client library (the type libraries of the installed PnP.PowerShell, never the module) builds the request that the
    # adapter queues, in a process of its own. Invoke-PnPQuery is replaced by a function that reads that request, as the client
    # library would send it, and sends nothing: no connection exists, and no sign-in command is known in that process.
    BeforeAll {
        $script:RealCall = {
            param([string]$Filter, [string]$StartIndex, [bool]$QueryError = $false)

            $base = (Get-Module -ListAvailable -Name 'PnP.PowerShell' | Sort-Object -Property Version -Descending | Select-Object -First 1).ModuleBase
            $script = @'
$env:PSModulePath = [System.IO.Path]::Combine($PSHOME, 'Modules')
$ErrorActionPreference = 'Stop'
foreach ($name in 'Microsoft.SharePoint.Client.dll', 'Microsoft.SharePoint.Client.Runtime.dll', 'Microsoft.Online.SharePoint.Client.Tenant.dll') {
    $null = [System.Reflection.Assembly]::LoadFrom((Join-Path -Path '@BASE@' -ChildPath "Core/$name"))
}

Import-Module -Name '@MANIFEST@' -Force
$module = Get-Module -Name SPSSiteLifecycle.Common
& $module {
    param($filter, $startIndex, $queryError)

    $script:Sent = [System.Collections.Generic.List[System.String]]::new()
    # Not named like a variable of the adapter (context): the names do not depend on the case, and the adapter would find this one
    # by the scope above its own when it did not read the context itself.
    $script:SyntheticClientContext = [Microsoft.SharePoint.Client.ClientContext]::new('https://contoso-admin.sharepoint.com')

    function script:Get-PnPContext { [CmdletBinding()] param($Connection) $script:SyntheticClientContext }
    function script:Invoke-PnPQuery {
        [CmdletBinding()]
        param($RetryCount, $Connection)
        if ($queryError) { Write-Error 'The query failed for a part of the tenant.'; return }
        $request = $script:SyntheticClientContext.PendingRequest
        $build = $request.GetType().GetMethod('BuildQuery', [System.Reflection.BindingFlags]'Instance,Public,NonPublic')
        $script:Sent.Add($build.Invoke($request, @()).CreateTextReader().ReadToEnd())
        $script:Retry = $RetryCount
    }

    $session = [PSCustomObject]@{ Connection = 'a connection'; TenantName = 'contoso'; AdminUrl = 'https://contoso-admin.sharepoint.com' }
    # The adapter is run under the preference of a normal session: an error that a command writes does not stop the code unless the
    # adapter asks for it. (The global preference is the one that the functions of a module read.)
    $global:ErrorActionPreference = 'Continue'
    $outcome = try {
        $null = Get-SPSLifecycleTenantSitePage -Session $session -Source Csom -StartIndex $startIndex -Filter $filter
        'no error'
    }
    catch {
        $_.Exception.Message
    }

    [PSCustomObject]@{
        Requests     = $script:Sent.Count
        Request      = if ($script:Sent.Count -gt 0) { $script:Sent[0] } else { '' }
        RetryCount   = $script:Retry
        Outcome      = $outcome
        SignInKnown  = [bool](Get-Command -Name 'Connect-PnPOnline' -ErrorAction SilentlyContinue)
        ModuleLoaded = [bool](Get-Module -Name 'PnP.PowerShell')
    } | ConvertTo-Json -Compress
} '@FILTER@' '@START@' @QUERYERROR@
'@
            $script = $script.Replace('@BASE@', $base.Replace("'", "''")).Replace('@MANIFEST@', $script:Manifest.Replace("'", "''"))
            $script = $script.Replace('@FILTER@', $Filter.Replace("'", "''")).Replace('@START@', $StartIndex.Replace("'", "''")).Replace('@QUERYERROR@', $(if ($QueryError) { '$true' } else { '$false' }))
            $path = Join-Path -Path $TestDrive -ChildPath ('real-call-{0}.ps1' -f [System.Guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText($path, $script)

            $output = & (Join-Path -Path $PSHOME -ChildPath 'pwsh') -NoProfile -NonInteractive -File $path
            $LASTEXITCODE | Should -Be 0
            ($output | Select-Object -Last 1) | ConvertFrom-Json
        }
    }

    It 'queues one request that holds the filter, the token, the details, and no OneDrive site, and asks again when the tenant throttles' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        $call = & $script:RealCall "LockState -eq 'ReadOnly'" 'token-1'

        $call.Requests | Should -Be 1
        $call.RetryCount | Should -Be 5
        $call.Request | Should -BeLike '*Name="GetSitePropertiesFromSharePointByFilters"*'
        $call.Request | Should -BeLike "*<Property Name=`"Filter`" Type=`"String`">LockState -eq 'ReadOnly'</Property>*"
        $call.Request | Should -BeLike '*<Property Name="StartIndex" Type="String">token-1</Property>*'
        $call.Request | Should -BeLike '*<Property Name="IncludeDetail" Type="Boolean">true</Property>*'
        $call.Request | Should -BeLike '*<Property Name="IncludePersonalSite" Type="Enum">2</Property>*'
    }

    It 'asks for every property of the sites that come back, so that none is left unloaded' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        $call = & $script:RealCall '' ''

        $call.Request | Should -BeLike '*<ChildItemQuery SelectAllProperties="true">*'
    }

    It 'sends no filter and no token for the first page of a whole listing' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        $call = & $script:RealCall '' ''

        $call.Request | Should -BeLike '*<Property Name="Filter" Type="Null" />*'
        $call.Request | Should -BeLike '*<Property Name="StartIndex" Type="Null" />*'
    }

    It 'stops on an error that the query reports without throwing, and does not go on to read a collection that was not loaded' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        $call = & $script:RealCall '' '' $true

        $call.Requests | Should -Be 0
        $call.Outcome | Should -BeLike '*The query failed for a part of the tenant*'
        $call.Outcome | Should -Not -BeLike '*not been initialized*'
    }

    It 'stops, after having queued the request, when the call gives back no page that can be read, and never signs in' -Skip:(-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        $call = & $script:RealCall '' ''

        $call.Requests | Should -Be 1
        $call.Outcome | Should -BeLike '*not been initialized*'
        $call.SignInKnown | Should -BeFalse -Because 'no sign-in command may exist in that process'
        $call.ModuleLoaded | Should -BeFalse -Because 'the module is never imported by a test'
    }
}

Describe 'Get-SPSLifecycleTenantSite' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Open-SPSLifecycleTenantSession'  = @'
param($Setting)
$script:StubLog.Add('open')
if ($script:StubData.OpenFails) { throw $script:StubData.OpenFails }
[PSCustomObject]@{ Connection = 'a connection'; TenantName = 'contoso' }
'@
            'Close-SPSLifecycleTenantSession' = @'
param($Session)
$script:StubLog.Add("close session=$($null -ne $Session)")
'@
            'Test-SPSLifecycleListingApi'     = @'
$script:StubLog.Add('api checked')
[PSCustomObject]@{ Available = $script:StubData.ApiAvailable; Reason = $script:StubData.ApiReason }
'@
            'Start-Sleep'                     = @'
param([double]$Seconds)
$script:StubLog.Add("sleep $Seconds")
'@
            'Get-SPSLifecycleTenantSitePage'  = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add("page source=$Source start=[$StartIndex] filter=[$Filter]")
$pages = $script:StubData.Pages
$index = if ($StartIndex -eq '') { 0 } else { [int]$StartIndex.Substring(1) }
if ($script:StubData.FailAt -eq $StartIndex) { throw 'The server did not answer.' }
$next = if ($index + 1 -lt $pages.Count) { 't' + ($index + 1) } else { '' }
[PSCustomObject]@{ Items = @($pages[$index]); NextStartIndex = $next }
'@
        } -Data @{ OpenFails = ''; ApiAvailable = $true; ApiReason = ''; Pages = @(); FailAt = $null }
    }

    AfterEach {
        Clear-ModuleStub
    }

    BeforeAll {
        function script:New-TestRecord {
            param([int]$Index)
            [PSCustomObject][ordered]@{
                Url = "https://contoso.sharepoint.com/sites/site$Index"; SiteId = ('{0:x8}-0000-4000-8000-{1:x12}' -f $Index, $Index); Title = "Site $Index"
                Template = 'GROUP#0'; LockState = 'ReadOnly'; GroupId = ('{0:x8}-1111-4111-8111-{1:x12}' -f $Index, $Index)
                IsHubSite = $false; IsTeamsConnected = $true; IsTeamsChannelConnected = $false; ArchiveStatus = 'NotArchived'
                StorageUsedMB = [long]12; LastContentModified = $script:Now
            }
        }

        function script:Set-TestPages {
            param([int[]]$Sizes)
            $number = 0
            $pages = foreach ($size in $Sizes) { , @(for ($i = 0; $i -lt $size; $i++) { $number++; New-TestRecord -Index $number }) }
            & $script:Module { param($p) $script:StubData.Pages = @($p) } @($pages)
        }

        function script:Invoke-TestTenantSite {
            param($Setting = (New-TestSetting), [string]$Source = 'Auto', [switch]$Restart, [scriptblock]$OnProgress = $null)
            $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
            $parameters = @{ Setting = $Setting; Summary = $summary; Source = $Source; Now = $script:Now }
            if ($Restart) { $parameters.Restart = $true }
            if ($null -ne $OnProgress) { $parameters.OnProgress = $OnProgress }
            $records = @(& $script:Module { param($p) Get-SPSLifecycleTenantSite @p } $parameters)
            [PSCustomObject]@{ Records = $records; Summary = $summary; Setting = $Setting }
        }
    }

    It 'lists the sites of the pages, signs in once, and ends the session' {
        Set-TestPages -Sizes 3, 2

        $result = Invoke-TestTenantSite

        $result.Records | Should -HaveCount 5
        $result.Summary.PagesRead | Should -Be 2
        $result.Summary.SitesReturned | Should -Be 5
        Get-StubLog | Should -Be @(
            'open'
            'api checked'
            "page source=Csom start=[] filter=[LockState -eq 'ReadOnly']"
            "page source=Csom start=[t1] filter=[LockState -eq 'ReadOnly']"
            'close session=True'
        )
    }

    It 'says in the summary how the sites were listed, with the OneDrive sites left out and the filter of the server' {
        Set-TestPages -Sizes 1

        $summary = (Invoke-TestTenantSite).Summary

        $summary.Source | Should -BeExactly 'Csom'
        $summary.FallbackReason | Should -BeExactly ''
        $summary.PersonalSites | Should -BeExactly 'Excluded'
        $summary.Filter | Should -BeExactly "LockState -eq 'ReadOnly'"
        $summary.StartedOn | Should -Be $script:Now
    }

    It 'asks for no filter when the Scan lists several lock states, and leaves the choice to the Scan core' {
        Set-TestPages -Sizes 1
        $setting = New-TestSetting -Override @{ Scan = [PSCustomObject]@{ LockStates = @('ReadOnly', 'Unlock') } }

        $result = Invoke-TestTenantSite -Setting $setting

        $result.Summary.Filter | Should -BeExactly ''
        (Get-StubLog) | Should -Contain 'page source=Csom start=[] filter=[]'
    }

    It 'writes the checkpoint in the output folder, in a folder of its own' {
        Set-TestPages -Sizes 1
        $setting = New-TestSetting

        $null = Invoke-TestTenantSite -Setting $setting

        Test-Path -LiteralPath (Join-Path -Path $setting.OutputFolder -ChildPath 'listing-checkpoint/manifest.json') | Should -BeTrue
    }

    It 'falls back on Get-PnPTenantSite when the paged call is not there, and says why' {
        Set-TestPages -Sizes 2
        & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'The types of the SharePoint admin API are not in this PnP.PowerShell.' }

        $result = Invoke-TestTenantSite

        $result.Records | Should -HaveCount 2
        $result.Summary.Source | Should -BeExactly 'Cmdlet'
        $result.Summary.FallbackReason | Should -BeLike '*not in this PnP.PowerShell*'
        (Get-StubLog) | Should -Contain "page source=Cmdlet start=[] filter=[LockState -eq 'ReadOnly']"
    }

    It 'uses the cmdlet when it is asked to, and says so' {
        Set-TestPages -Sizes 1

        $result = Invoke-TestTenantSite -Source Cmdlet

        $result.Summary.Source | Should -BeExactly 'Cmdlet'
        $result.Summary.FallbackReason | Should -BeLike '*asked*'
        (Get-StubLog) | Should -Not -Contain 'api checked'
    }

    It 'stops, and ends the session, when the paged call is asked for and is not there' {
        Set-TestPages -Sizes 1
        & $script:Module { $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'The filter of the admin API has no property StartIndex.' }

        { Invoke-TestTenantSite -Source Csom } | Should -Throw -ExpectedMessage '*StartIndex*'

        (Get-StubLog) | Should -Contain 'close session=True'
        (Get-StubLog | Where-Object { $_ -like 'page source*' }) | Should -HaveCount 0
    }

    It 'does not read the pages of a checkpoint that was made the other way: starts again and says that the way changed' {
        Set-TestPages -Sizes 3, 2, 4
        $setting = New-TestSetting
        & $script:Module { $script:StubData.FailAt = 't2' }
        { Invoke-TestTenantSite -Setting $setting } | Should -Throw
        & $script:Module { $script:StubData.FailAt = $null; $script:StubData.ApiAvailable = $false; $script:StubData.ApiReason = 'no API' }

        $result = Invoke-TestTenantSite -Setting $setting

        $result.Summary.Resumed | Should -BeFalse
        $result.Summary.StartReason | Should -BeLike '*asked*'
        $result.Records | Should -HaveCount 9
    }

    It 'takes up an interrupted listing: the second run asks only for the pages that are missing' {
        Set-TestPages -Sizes 3, 2, 4
        $setting = New-TestSetting
        & $script:Module { $script:StubData.FailAt = 't2' }
        { Invoke-TestTenantSite -Setting $setting } | Should -Throw -ExpectedMessage '*page 3*'
        & $script:Module { $script:StubData.FailAt = $null; $script:StubLog.Clear() }

        $result = Invoke-TestTenantSite -Setting $setting

        $result.Summary.Resumed | Should -BeTrue
        $result.Summary.PagesFromCheckpoint | Should -Be 2
        $result.Records | Should -HaveCount 9
        (Get-StubLog | Where-Object { $_ -like 'page source*' }) | Should -Be @("page source=Csom start=[t2] filter=[LockState -eq 'ReadOnly']")
    }

    It 'starts again when it is asked to' {
        Set-TestPages -Sizes 3, 2, 4
        $setting = New-TestSetting
        & $script:Module { $script:StubData.FailAt = 't2' }
        { Invoke-TestTenantSite -Setting $setting } | Should -Throw
        & $script:Module { $script:StubData.FailAt = $null }

        $result = Invoke-TestTenantSite -Setting $setting -Restart

        $result.Summary.Resumed | Should -BeFalse
        $result.Summary.StartReason | Should -BeLike '*Restart*'
    }

    It 'ends the session when the listing fails' {
        Set-TestPages -Sizes 3, 2
        & $script:Module { $script:StubData.FailAt = 't1' }

        { Invoke-TestTenantSite } | Should -Throw -ExpectedMessage '*page 2*'

        @(Get-StubLog)[-1] | Should -BeExactly 'close session=True'
    }

    It 'asks a page that failed again after 5 s and then 10 s, without waiting for real in the test' {
        Set-TestPages -Sizes 3, 2
        & $script:Module { $script:StubData.FailAt = 't1' }

        { Invoke-TestTenantSite } | Should -Throw

        (Get-StubLog | Where-Object { $_ -like 'sleep*' }) | Should -Be @('sleep 5', 'sleep 10')
        (Get-StubLog | Where-Object { $_ -like 'page source=Csom start=[[]t1[]]*' }) | Should -HaveCount 3
    }

    It 'does not list anything when the sign-in fails, and has no session to end' {
        & $script:Module { $script:StubData.OpenFails = 'The sign-in failed.' }

        { Invoke-TestTenantSite } | Should -Throw -ExpectedMessage '*sign-in failed*'

        (Get-StubLog | Where-Object { $_ -like 'page source*' }) | Should -HaveCount 0
        (Get-StubLog | Where-Object { $_ -like 'close*' }) | Should -HaveCount 0
    }

    It 'does not end a session that its caller happens to hold in a variable of the same name, when the sign-in fails' {
        & $script:Module { $script:StubData.OpenFails = 'The sign-in failed.' }
        $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

        {
            & $script:Module {
                param($setting, $sum, $now)
                $session = 'a session of the caller'
                $null = Get-SPSLifecycleTenantSite -Setting $setting -Summary $sum -Source Auto -Now $now
            } (New-TestSetting) $summary $script:Now
        } | Should -Throw -ExpectedMessage '*sign-in failed*'

        (Get-StubLog | Where-Object { $_ -like 'close*' }) | Should -HaveCount 0
    }

    It 'gives no reason for the cmdlet when the paged call is used, also in a summary that held one' {
        Set-TestPages -Sizes 2
        $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }
        $summary.FallbackReason = 'a reason of an earlier listing'

        $null = @(& $script:Module { param($sum, $now, $setting) Get-SPSLifecycleTenantSite -Setting $setting -Summary $sum -Source Auto -Now $now } $summary $script:Now (New-TestSetting))

        $summary.Source | Should -BeExactly 'Csom'
        $summary.FallbackReason | Should -BeExactly ''
    }

    It 'ends the progress that it showed, under the same activity, also when the caller gives none' {
        Set-TestPages -Sizes 3, 2
        & $script:Module {
            $script:Progress = [System.Collections.Generic.List[System.Object]]::new()
            Invoke-Expression 'function script:Write-Progress { param($Activity, $Status, $PercentComplete, [switch]$Completed) $script:Progress.Add([PSCustomObject]@{ Activity = $Activity; Completed = [bool]$Completed }) }'
        }

        try {
            $null = Invoke-TestTenantSite
            $progress = @(& $script:Module { $script:Progress.ToArray() })
        }
        finally {
            & $script:Module { Remove-Item -Path 'Function:\Write-Progress' -ErrorAction SilentlyContinue }
        }

        @($progress | Where-Object { -not $_.Completed }) | Should -HaveCount 2
        @($progress | Where-Object { $_.Completed }) | Should -HaveCount 1
        foreach ($record in $progress) {
            $record.Activity | Should -BeExactly 'Listing the sites of the tenant'
        }
    }

    It 'tells its progress to the caller after each page' {
        Set-TestPages -Sizes 3, 2
        $log = [System.Collections.Generic.List[object]]::new()
        $onProgress = { param($progress) $log.Add($progress) }.GetNewClosure()

        $null = Invoke-TestTenantSite -OnProgress $onProgress

        ($log | ForEach-Object { $_.Pages }) | Should -Be @(1, 2)
        ($log | ForEach-Object { $_.SitesReturned }) | Should -Be @(3, 5)
    }

    It 'shows its progress when the caller gives none, and does not stop for it' {
        Set-TestPages -Sizes 3, 2

        $result = Invoke-TestTenantSite

        $result.Records | Should -HaveCount 5
    }

    It 'refuses a lock state that the server does not know, before it signs in' {
        $setting = New-TestSetting -Override @{ Scan = [PSCustomObject]@{ LockStates = @('Locked') } }

        { Invoke-TestTenantSite -Setting $setting } | Should -Throw -ExpectedMessage '*lock state*'

        Get-StubLog | Should -HaveCount 0
    }
}

Describe 'A refused tenant never reaches the sign-in, through the whole chain' {
    BeforeEach {
        Set-ModuleStub -Stub @{
            'Assert-SPSLifecyclePnPModule' = @'
$script:StubLog.Add('module checked')
'@
            'Connect-PnPOnline'            = @'
[CmdletBinding()]
param([string]$Url, [switch]$Interactive, [string]$ClientId, [string]$Tenant, [switch]$ReturnConnection)
$script:StubLog.Add("Connect-PnPOnline Url=$Url")
'a connection'
'@
            'Get-SPSLifecycleTenantSitePage' = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add('page')
[PSCustomObject]@{ Items = @(); NextStartIndex = '' }
'@
        }
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'stops before anything is called: <Name>' -ForEach @(
        @{ Name = 'the Microsoft tenant'; Override = @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' } }
        @{ Name = 'the Microsoft tenant in capitals'; Override = @{ TenantName = 'MICROSOFT'; AdminUrl = 'https://MICROSOFT-admin.sharepoint.com' } }
        @{ Name = 'a tenant of the settings'; Override = @{ TenantName = 'fabrikam'; AdminUrl = 'https://fabrikam-admin.sharepoint.com'; RefusedTenants = @('fabrikam') } }
    ) {
        $setting = New-TestSetting -Override $Override
        $summary = & $script:Module { Initialize-SPSLifecycleListingSummary }

        { @(& $script:Module { param($s, $sum) Get-SPSLifecycleTenantSite -Setting $s -Summary $sum -Source Cmdlet } $setting $summary) } | Should -Throw -ExpectedMessage '*refused*'

        Get-StubLog | Should -HaveCount 0
        Test-Path -LiteralPath (Join-Path -Path $setting.OutputFolder -ChildPath 'listing-checkpoint') | Should -BeFalse
    }
}
