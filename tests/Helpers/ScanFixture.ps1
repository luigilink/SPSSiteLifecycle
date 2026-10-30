# The fixture of the tests of the Scan: a tenant of five sites that the listing gives, the files that a Scan reads, and the
# stubs of the adapters. A test file dot-sources this file, after Helpers/ModuleStub.ps1, in its BeforeAll.

# A record as the listing gives it: five sites that a Scan reads, and a OneDrive site that the listing drops.
function script:New-RunRecord {
    param([int]$Index, [hashtable]$Override = @{})

    $values = [ordered]@{
        Url                     = "https://contoso.sharepoint.com/sites/site$Index"
        SiteId                  = ('{0:x8}-0000-4000-8000-{1:x12}' -f $Index, $Index)
        Title                   = "Title $Index"
        Template                = 'GROUP#0'
        LockState               = 'ReadOnly'
        GroupId                 = ('{0:x8}-1111-4111-8111-{1:x12}' -f $Index, $Index)
        IsHubSite               = $false
        IsTeamsConnected        = $false
        IsTeamsChannelConnected = $false
        ArchiveStatus           = 'NotArchived'
        StorageUsedMB           = [long]10
        LastContentModified     = [System.DateTime]::new(2025, 1, 5, 0, 0, 0, [System.DateTimeKind]::Utc)
    }
    foreach ($key in $Override.Keys) {
        $values[$key] = $Override[$key]
    }

    [PSCustomObject]$values
}

# Site 1: a quiet site with a group. 2: a quiet site without a group. 3: a large one. 4: one with a recent activity. 5: the home site.
# Then a OneDrive site, which the listing drops.
function script:Set-RunPages {
    $records = @(
        New-RunRecord -Index 1
        New-RunRecord -Index 2 -Override @{ Template = 'SITEPAGEPUBLISHING#0'; GroupId = '' }
        New-RunRecord -Index 3 -Override @{ StorageUsedMB = [long]5000 }
        New-RunRecord -Index 4
        New-RunRecord -Index 5
        New-RunRecord -Index 6 -Override @{ Url = 'https://contoso-my.sharepoint.com/personal/someone_contoso_com'; Template = 'SPSPERS#10'; GroupId = '' }
    )
    & $script:Module {
        param($r)
        $script:StubData.Pages = @(, @($r[0], $r[1], $r[2]); , @($r[3], $r[4], $r[5]))
    } $records
}

# A settings file and the files that it names, in a folder of its own.
function script:New-RunFolder {
    param([string]$Settings = '', $Usage = $null, $Teams = $null, [string]$Delimiter = ',', $Locks = $null)

    $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $folder -ItemType Directory

    $header = 'Report Refresh Date,Site Id,Site URL,Owner Display Name,Is Deleted,Last Activity Date,Root Web Template,Report Period'
    if ($null -eq $Usage) {
        $rows = foreach ($index in 1..5) {
            $id = '{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index
            $last = if ($index -eq 4) { '2026-10-01' } else { '2025-01-10' }
            "2026-10-29,$id,https://contoso.sharepoint.com/sites/site$index,Owner,False,$last,Group,180"
        }
        $Usage = $header + "`r`n" + ($rows -join "`r`n") + "`r`n"
    }

    [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'usage.csv'), $Usage)

    if ($null -eq $Locks) {
        $lockRows = foreach ($index in 1..5) {
            "https://contoso.sharepoint.com/sites/site$index,2025-09-18,$('{0:x8}-0000-4000-8000-{1:x12}' -f $index, $index)"
        }
        $Locks = "Url,LockedOn,SiteId`r`n" + ($lockRows -join "`r`n") + "`r`n"
    }

    [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'lot1.csv'), $Locks)

    if ($null -ne $Teams) {
        [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'teams.csv'), $Teams)
    }

    $body = @"
@{
TenantName    = 'contoso'
ClientId      = '11111111-2222-3333-4444-555555555555'
OutputFolder  = 'Reports'
CsvDelimiter  = '$Delimiter'
LockDateFiles = @('lot1.csv')
$Settings
Scan          = @{ SharePointUsageReport = 'usage.csv'$(if ($null -ne $Teams) { "; TeamsActivityReport = 'teams.csv'" }) }
}
"@
    $config = Join-Path -Path $folder -ChildPath 'settings.psd1'
    [System.IO.File]::WriteAllText($config, $body)

    [PSCustomObject]@{ Folder = $folder; Config = $config; Reports = Join-Path -Path $folder -ChildPath 'Reports' }
}


# Replaces the adapters of the listing for the length of a test, and sets the five sites of the tenant.
function script:Set-ScanStub {
    Set-ModuleStub -Stub @{
        'Open-SPSLifecycleTenantSession'  = @'
param($Setting)
$script:StubLog.Add('open')
[PSCustomObject]@{ Connection = 'a connection'; TenantName = 'contoso' }
'@
        'Get-SPSLifecycleHomeSiteUrl'     = @'
param($Session)
$script:StubLog.Add('home site')
if ($script:StubData.HomeSiteFails) { throw $script:StubData.HomeSiteFails }
$script:StubData.HomeSite
'@
        'Close-SPSLifecycleTenantSession' = @'
param($Session)
$script:StubLog.Add('close')
'@
        'Test-SPSLifecycleListingApi'     = @'
$script:StubLog.Add('api checked')
[PSCustomObject]@{ Available = $true; Reason = '' }
'@
        'Start-Sleep'                     = @'
param([double]$Seconds)
'@
        'Get-SPSLifecycleTenantSitePage'  = @'
param($Session, $Source, [string]$StartIndex, [string]$Filter)
$script:StubLog.Add("page start=[$StartIndex]")
$pages = $script:StubData.Pages
$index = if ($StartIndex -eq '') { 0 } else { [int]$StartIndex.Substring(1) }
if ($script:StubData.FailAt -eq $StartIndex) { throw 'The server did not answer.' }
$next = if ($index + 1 -lt $pages.Count) { 't' + ($index + 1) } else { '' }
[PSCustomObject]@{ Items = @($pages[$index]); NextStartIndex = $next }
'@
    } -Data @{ Pages = @(); FailAt = $null; HomeSite = 'https://contoso.sharepoint.com/sites/site5'; HomeSiteFails = '' }
    Set-RunPages
}
