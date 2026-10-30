# The fixture of the tests of the Act phase: a tenant of sites that the adapters give and that the writing adapters change, the
# reviewed report and the other files that an Act run reads, and the stubs of the adapters. A test file dot-sources this file,
# after Helpers/ModuleStub.ps1, in its BeforeAll.

# One site of the tenant, as its live state: the record that the read adapter gives, and what the stubs need to follow the changes.
function script:New-ActSiteState {
    param([int]$Index, [hashtable]$Override = @{})

    $values = [ordered]@{
        Url                     = "https://contoso.sharepoint.com/sites/site$Index"
        SiteId                  = ('{0:x8}-0000-4000-8000-{1:x12}' -f $Index, $Index)
        Title                   = "Title $Index"
        Template                = 'GROUP#0'
        LockState               = 'ReadOnly'
        GroupId                 = ('{0:x8}-1111-4111-8111-{1:x12}' -f $Index, $Index)
        IsHubSite               = $false
        IsTeamsConnected        = $true
        IsTeamsChannelConnected = $false
        ArchiveStatus           = 'NotArchived'
        StorageUsedMB           = [System.Int64]12
        LastContentModified     = [System.DateTime]::new(2025, 1, 5, 10, 0, 0, [System.DateTimeKind]::Utc)
        HasHolds                = $false
        Exists                  = $true
        GroupState              = 'Active'
    }
    foreach ($key in $Override.Keys) {
        $values[$key] = $Override[$key]
    }

    [PSCustomObject]$values
}

# Replaces the adapters for the length of a test. The writing adapters change the sites of the world, so that a wait for a lock state
# sees it, and every call is written in the log. $script:StubData.Fail maps a step ('delete site', 'delete group', 'archive',
# 'lock ReadOnly', 'lock Unlock', 'admin', 'read') to a message that makes it fail, or to a hashtable of address -> message.
function script:Set-ActStub {
    param([object[]]$Site = @(), [hashtable]$Data = @{})

    $world = @{}
    foreach ($state in $Site) {
        $world[$state.Url.ToLowerInvariant()] = $state
    }

    $values = @{
        World = $world; Fail = @{}; HomeSite = ''; HomeSiteQueue = $null; HomeSiteReads = 0; ArchiveEnabled = $true; Account = 'admin@contoso.example'
        Redirected = $false; Answers = @('contoso', 'APPLY 1'); AnswerIndex = 0; Reads = 0
    }
    foreach ($key in $Data.Keys) {
        $values[$key] = $Data[$key]
    }

    Set-ModuleStub -Stub @{
        'Open-SPSLifecycleTenantSession'   = @'
param($Setting)
$script:StubLog.Add('open')
if ($script:StubData.Fail.ContainsKey('open')) { throw $script:StubData.Fail['open'] }
[PSCustomObject]@{ Connection = 'a connection'; TenantName = 'contoso'; AdminUrl = 'https://contoso-admin.sharepoint.com'; RefusedTenants = @() }
'@
        'Close-SPSLifecycleTenantSession'  = @'
param($Session)
$script:StubLog.Add('close')
'@
        'Get-SPSLifecycleHomeSiteUrl'      = @'
param($Session)
$script:StubLog.Add('home site')
$script:StubData.HomeSiteReads++
if ($script:StubData.Fail.ContainsKey('home site')) { throw $script:StubData.Fail['home site'] }
if ($script:StubData.Fail.ContainsKey('home site from')) { if ($script:StubData.HomeSiteReads -ge $script:StubData.Fail['home site from']) { throw 'The home site of the tenant could not be read: Throttled.' } }
$queue = $script:StubData.HomeSiteQueue
if ($null -ne $queue) { $queue[[System.Math]::Min($script:StubData.HomeSiteReads - 1, $queue.Count - 1)] } else { $script:StubData.HomeSite }
'@
        'Get-SPSLifecycleArchiveEnabled'   = @'
param($Session)
$script:StubLog.Add('archive enabled?')
if ($script:StubData.Fail.ContainsKey('archive enabled')) { throw $script:StubData.Fail['archive enabled'] }
$script:StubData.ArchiveEnabled
'@
        'Get-SPSLifecycleSignedInAccount'  = @'
param($Session)
$script:StubLog.Add('account')
if ($script:StubData.Fail.ContainsKey('account')) { throw $script:StubData.Fail['account'] }
$script:StubData.Account
'@
        'Get-SPSLifecycleLiveSite'         = @'
param($Session, $Url)
$script:StubLog.Add("read $Url")
$script:StubData.Reads++
$fail = $script:StubData.Fail['read']
if ($fail -is [string]) { throw $fail }
if ($fail -is [hashtable] -and $fail.ContainsKey($Url)) { throw $fail[$Url] }
$state = $script:StubData.World[$Url.ToLowerInvariant().TrimEnd('/')]
if ($null -eq $state -or -not $state.Exists) { return }
[PSCustomObject][ordered]@{
    Url = $state.Url; SiteId = $state.SiteId; Title = $state.Title; Template = $state.Template; LockState = $state.LockState; GroupId = $state.GroupId
    IsHubSite = $state.IsHubSite; IsTeamsConnected = $state.IsTeamsConnected; IsTeamsChannelConnected = $state.IsTeamsChannelConnected
    ArchiveStatus = $state.ArchiveStatus; StorageUsedMB = $state.StorageUsedMB; LastContentModified = $state.LastContentModified; HasHolds = $state.HasHolds
}
'@
        'Get-SPSLifecycleGroupState'       = @'
param($Session, $GroupId)
$script:StubLog.Add("group $GroupId")
if ($script:StubData.Fail.ContainsKey('group')) { throw $script:StubData.Fail['group'] }
$state = @($script:StubData.World.Values | Where-Object { $_.GroupId -eq $GroupId }) | Select-Object -First 1
if ($null -eq $state) { return 'NotFound' }
$state.GroupState
'@
        'Set-SPSLifecycleSiteLockState'    = @'
param($Session, $Url, $State)
$script:StubLog.Add("lock $State $Url")
$fail = $script:StubData.Fail["lock $State"]
if ($fail -is [string]) { throw $fail }
if ($fail -is [hashtable] -and $fail.ContainsKey($Url)) { throw $fail[$Url] }
$script:StubData.World[$Url.ToLowerInvariant()].LockState = $State
'@
        'Remove-SPSLifecycleSite'          = @'
param($Session, $Url)
$script:StubLog.Add("delete site $Url")
$fail = $script:StubData.Fail['delete site']
if ($fail -is [string]) { throw $fail }
if ($fail -is [hashtable] -and $fail.ContainsKey($Url)) { throw $fail[$Url] }
$script:StubData.World[$Url.ToLowerInvariant()].Exists = $false
'@
        'Remove-SPSLifecycleGroup'         = @'
param($Session, $GroupId)
$script:StubLog.Add("delete group $GroupId")
$fail = $script:StubData.Fail['delete group']
if ($fail -is [string]) { throw $fail }
if ($fail -is [hashtable] -and $fail.ContainsKey($GroupId)) { throw $fail[$GroupId] }
foreach ($state in @($script:StubData.World.Values | Where-Object { $_.GroupId -eq $GroupId })) { $state.GroupState = 'SoftDeleted' }
'@
        'Request-SPSLifecycleSiteArchive'  = @'
param($Session, $Url)
$script:StubLog.Add("archive $Url")
$fail = $script:StubData.Fail['archive']
if ($fail -is [string]) { throw $fail }
if ($fail -is [hashtable] -and $fail.ContainsKey($Url)) { throw $fail[$Url] }
$script:StubData.World[$Url.ToLowerInvariant()].ArchiveStatus = 'RecentlyArchived'
'@
        'Add-SPSLifecycleSiteAdmin'        = @'
param($Session, $Url, $Account)
$script:StubLog.Add("admin $Account $Url")
if ($script:StubData.Fail.ContainsKey('admin')) { throw $script:StubData.Fail['admin'] }
'@
        'Test-SPSLifecycleInputRedirected' = @'
$script:StubLog.Add('redirected?')
$script:StubData.Redirected
'@
        'Read-Host'                        = @'
[CmdletBinding()]
param($Prompt)
$script:StubLog.Add("ask: $Prompt")
$answer = $script:StubData.Answers[$script:StubData.AnswerIndex]
$script:StubData.AnswerIndex++
$answer
'@
        'Start-Sleep'                      = @'
param([double]$Seconds)
$script:StubLog.Add("sleep $Seconds")
'@
    } -Data $values
}

# The files of an Act run, in a folder of its own: the settings file, the reviewed report, and the lock dates of the sites.
# -Row is a list of @{ Index = 1; Decision = 'Delete' } (a Url or a SiteId can be given to replace the ones of the site).
function script:New-ActRunFolder {
    param(
        [object[]]$Row = @(),
        [string]$Settings = '',
        [string]$ActSettings = '',
        [int]$LockedSites = 50,
        [string]$Generated = '20261029T080000Z',
        [string]$Delimiter = ',',
        $Locks = $null
    )

    $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $folder -ItemType Directory

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add('Url,SiteId,GeneratedOn,Decision')
    foreach ($entry in $Row) {
        $index = [int]$entry.Index
        $url = if ($entry.ContainsKey('Url')) { $entry.Url } else { "https://contoso.sharepoint.com/sites/site$index" }
        $siteId = if ($entry.ContainsKey('SiteId')) { $entry.SiteId } else { '{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index }
        $generated = if ($entry.ContainsKey('GeneratedOn')) { $entry.GeneratedOn } else { $Generated }
        $decision = if ($entry.ContainsKey('Decision')) { $entry.Decision } else { '' }
        $lines.Add("$url,$siteId,$generated,$decision")
    }
    [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'sites.csv'), (($lines -join "`r`n") + "`r`n"))

    if ($null -eq $Locks) {
        $lockLines = [System.Collections.Generic.List[System.String]]::new()
        $lockLines.Add('Url,LockedOn,SiteId')
        foreach ($index in 1..$LockedSites) {
            $lockLines.Add("https://contoso.sharepoint.com/sites/site$index,2025-09-18,$('{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index)")
        }
        $Locks = ($lockLines -join "`r`n") + "`r`n"
    }
    [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'lot1.csv'), $Locks)

    $body = @"
@{
TenantName    = 'contoso'
ClientId      = '11111111-2222-3333-4444-555555555555'
OutputFolder  = 'Reports'
CsvDelimiter  = '$Delimiter'
LockDateFiles = @('lot1.csv')
$Settings
Act = @{ InputFile = 'sites.csv'; $ActSettings }
}
"@
    $config = Join-Path -Path $folder -ChildPath 'settings.psd1'
    [System.IO.File]::WriteAllText($config, $body)

    [PSCustomObject]@{
        Folder  = $folder
        Config  = $config
        Reports = Join-Path -Path $folder -ChildPath 'Reports'
        Journal = Join-Path -Path (Join-Path -Path $folder -ChildPath 'Reports') -ChildPath 'lock-journal.csv'
    }
}

# Runs the Act phase, and gives its summary, the lines that it wrote, and the rows of its report.
function script:Invoke-TestAct {
    param($Run, [datetime]$Now = [System.DateTime]::new(2026, 10, 30, 9, 0, 0, [System.DateTimeKind]::Utc))

    $summary = Invoke-SPSLifecycleAct -ConfigFile $Run.Config -Now $Now -InformationAction SilentlyContinue -InformationVariable info
    $rows = @()
    if ($null -ne $summary -and $summary.ReportPath -and (Test-Path -LiteralPath $summary.ReportPath)) {
        $rows = @(Import-Csv -LiteralPath $summary.ReportPath)
    }

    [PSCustomObject]@{ Summary = $summary; Text = @($info | ForEach-Object { "$($_.MessageData)" }); Rows = $rows }
}
