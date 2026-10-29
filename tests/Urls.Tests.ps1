BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
}

Describe 'ConvertTo-SPSLifecycleUrlKey' {
    It 'gives the key <Expected> to <Url>' -ForEach @(
        @{ Url = 'https://contoso.sharepoint.com/sites/sales'; Expected = 'https://contoso.sharepoint.com/sites/sales' }
        @{ Url = '  HTTPS://Contoso.SharePoint.com/Sites/Sales/  '; Expected = 'https://contoso.sharepoint.com/sites/sales' }
        @{ Url = 'https://contoso.sharepoint.com/sites/sales///'; Expected = 'https://contoso.sharepoint.com/sites/sales' }
        @{ Url = 'https://contoso.sharepoint.com'; Expected = 'https://contoso.sharepoint.com' }
        @{ Url = 'https://contoso.sharepoint.com/'; Expected = 'https://contoso.sharepoint.com' }
        @{ Url = 'https://contoso.sharepoint.com:443/'; Expected = 'https://contoso.sharepoint.com' }
        @{ Url = 'https://contoso.sharepoint.com:443/sites/sales'; Expected = 'https://contoso.sharepoint.com/sites/sales' }
        @{ Url = 'https://contoso.sharepoint.com:8443/sites/sales'; Expected = 'https://contoso.sharepoint.com:8443/sites/sales' }
        @{ Url = 'https://contoso.sharepoint.com/sites/%C3%A9quipe'; Expected = 'https://contoso.sharepoint.com/sites/équipe' }
        @{ Url = 'https://contoso.sharepoint.com/sites/équipe'; Expected = 'https://contoso.sharepoint.com/sites/équipe' }
        @{ Url = 'https://contoso.sharepoint.com/sites/%C3%89quipe'; Expected = 'https://contoso.sharepoint.com/sites/équipe' }
        @{ Url = 'https://contoso.sharepoint.com/sites/my%20team'; Expected = 'https://contoso.sharepoint.com/sites/my team' }
        @{ Url = 'https://contoso.sharepoint.com/sites/sales?csf=1#top'; Expected = 'https://contoso.sharepoint.com/sites/sales' }
        @{ Url = 'http://contoso.sharepoint.com/sites/sales'; Expected = 'http://contoso.sharepoint.com/sites/sales' }
    ) {
        $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $Url

        $key | Should -BeExactly $Expected
    }

    It 'gives the same key to two spellings of one site: <A> and <B>' -ForEach @(
        @{ A = 'https://contoso.sharepoint.com/sites/équipe'; B = 'https://contoso.sharepoint.com/sites/%C3%A9quipe' }
        @{ A = 'https://contoso.sharepoint.com/'; B = 'https://CONTOSO.sharepoint.com:443' }
        @{ A = 'https://contoso.sharepoint.com/sites/Été/'; B = 'https://contoso.sharepoint.com/sites/%c3%a9t%c3%a9' }
    ) {
        $keyA = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $A
        $keyB = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $B

        $keyA | Should -BeExactly $keyB
    }

    It 'keeps two different sites apart' {
        $keyA = & $script:Module { ConvertTo-SPSLifecycleUrlKey -Url 'https://contoso.sharepoint.com/sites/sales' }
        $keyB = & $script:Module { ConvertTo-SPSLifecycleUrlKey -Url 'https://contoso.sharepoint.com/sites/sales2' }
        $keyC = & $script:Module { ConvertTo-SPSLifecycleUrlKey -Url 'https://contoso.sharepoint.com/teams/sales' }

        $keyA | Should -Not -BeExactly $keyB
        $keyA | Should -Not -BeExactly $keyC
    }

    It 'falls back to trimming and lowercasing for a text that is not a web address: <Name>' -ForEach @(
        @{ Name = 'a server-relative path'; Url = '/Sites/Sales/'; Expected = '/sites/sales' }
        @{ Name = 'a file address'; Url = 'file:///srv/Sales/'; Expected = 'file:///srv/sales' }
        @{ Name = 'a name'; Url = '  Sales Team  '; Expected = 'sales team' }
    ) {
        $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $Url

        $key | Should -BeExactly $Expected
    }

    It 'gives an empty key to <Name>' -ForEach @(
        @{ Name = 'null'; Url = $null }
        @{ Name = 'an empty text'; Url = '' }
        @{ Name = 'spaces'; Url = '   ' }
    ) {
        $key = & $script:Module { param($u) ConvertTo-SPSLifecycleUrlKey -Url $u } $Url

        $key | Should -BeExactly ''
    }

    It 'gives the same key under <Culture>, for a name with an I' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            $key = & $script:Module { ConvertTo-SPSLifecycleUrlKey -Url 'https://CONTOSO.sharepoint.com/sites/INFO' }
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }

        $key | Should -BeExactly 'https://contoso.sharepoint.com/sites/info'
    }
}

Describe 'Safeguards that compare URLs' {
    BeforeAll {
        $script:Setting = [PSCustomObject]@{
            TenantName         = 'contoso'
            TenantUrl          = 'https://contoso.sharepoint.com'
            AcceptedLockStates = @('ReadOnly')
            MinLockedDays      = 365
            DeleteMaxSizeGB    = 1.0
            Scan               = [PSCustomObject]@{ InactiveDays = 365 }
        }
        $script:Old = [System.DateTime]::new(2025, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        $script:Now = [System.DateTime]::new(2026, 10, 29, 8, 0, 0, [System.DateTimeKind]::Utc)
    }

    It 'protects the root site, whatever its spelling: <Url>' -ForEach @(
        @{ Url = 'https://contoso.sharepoint.com' }
        @{ Url = 'https://contoso.sharepoint.com/' }
        @{ Url = 'https://contoso.sharepoint.com:443/' }
        @{ Url = 'HTTPS://CONTOSO.SHAREPOINT.COM//' }
    ) {
        $site = [PSCustomObject]@{ Url = $Url; Template = 'SITEPAGEPUBLISHING#0'; LockState = 'ReadOnly'; GroupId = ''; StorageUsedMB = 10; ArchiveStatus = 'NotArchived'; IsHubSite = $false; IsTeamsChannelConnected = $false; LastContentModified = $null }
        $verdict = & $script:Module { param($s, $c, $n, $o) Get-SPSLifecycleVerdict -Site $s -Setting $c -Action Delete -Now $n -LockedOn $o } $site $script:Setting $script:Now $script:Old

        $verdict | Should -Be 'SKIP-PROTECTED'
    }

    It 'protects the home site, whatever its spelling' {
        $site = [PSCustomObject]@{ Url = 'https://contoso.sharepoint.com/sites/%C3%A9quipe'; Template = 'SITEPAGEPUBLISHING#0'; LockState = 'ReadOnly'; GroupId = ''; StorageUsedMB = 10; ArchiveStatus = 'NotArchived'; IsHubSite = $false; IsTeamsChannelConnected = $false; LastContentModified = $null }
        $verdict = & $script:Module { param($s, $c, $n, $o) Get-SPSLifecycleVerdict -Site $s -Setting $c -Action Delete -Now $n -LockedOn $o -HomeSiteUrl 'https://contoso.sharepoint.com/sites/équipe/' } $site $script:Setting $script:Now $script:Old

        $verdict | Should -Be 'SKIP-PROTECTED'
    }

    It 'protects a system path written with another case or an encoded letter' -ForEach @(
        @{ Url = 'https://contoso.sharepoint.com/sites/ContentTypeHub/' }
        @{ Url = 'https://contoso.sharepoint.com/sites/%63ontenttypehub' }
        @{ Url = 'https://contoso.sharepoint.com:443/sites/contenttypehub' }
    ) {
        $site = [PSCustomObject]@{ Url = $Url; Template = 'STS#3'; LockState = 'ReadOnly'; GroupId = ''; StorageUsedMB = 10; ArchiveStatus = 'NotArchived'; IsHubSite = $false; IsTeamsChannelConnected = $false; LastContentModified = $null }
        $verdict = & $script:Module { param($s, $c, $n, $o) Get-SPSLifecycleVerdict -Site $s -Setting $c -Action Delete -Now $n -LockedOn $o } $site $script:Setting $script:Now $script:Old

        $verdict | Should -Be 'SKIP-PROTECTED'
    }

    It 'leaves out a OneDrive site whatever the spelling of its address' {
        $site = [PSCustomObject]@{ Url = 'https://CONTOSO-my.sharepoint.com:443/personal/a_contoso_com/'; Template = 'STS#3'; LockState = 'ReadOnly'; GroupId = ''; StorageUsedMB = 10; ArchiveStatus = 'NotArchived'; IsHubSite = $false; IsTeamsChannelConnected = $false; LastContentModified = $null }
        $verdict = & $script:Module { param($s, $c, $n, $o) Get-SPSLifecycleVerdict -Site $s -Setting $c -Action Delete -Now $n -LockedOn $o } $site $script:Setting $script:Now $script:Old

        $verdict | Should -Be 'SKIP-ONEDRIVE'
    }

    It 'finds a site of an exclusion list or a lock date list when the address is spelled another way' {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $exclusions = Join-Path -Path $folder -ChildPath 'exclusions.csv'
        $locks = Join-Path -Path $folder -ChildPath 'locks.csv'
        [System.IO.File]::WriteAllText($exclusions, "Url`r`nhttps://contoso.sharepoint.com/sites/%C3%A9quipe`r`n", [System.Text.UTF8Encoding]::new($true))
        [System.IO.File]::WriteAllText($locks, "Url,LockedOn`r`nhttps://contoso.sharepoint.com:443/sites/%C3%89quipe/,2025-09-18`r`n", [System.Text.UTF8Encoding]::new($true))

        $result = & $script:Module {
            param($e, $l)
            $live = ConvertTo-SPSLifecycleUrlKey -Url 'https://contoso.sharepoint.com/sites/équipe'
            $excluded = (Import-SPSLifecycleExclusionList -Path $e).Keys
            $locked = @((Import-SPSLifecycleLockDateList -Path $l).Entries | Where-Object { $_.UrlKey -eq $live })
            [PSCustomObject]@{ Excluded = $excluded.ContainsKey($live); LockCount = $locked.Count }
        } $exclusions $locks

        $result.Excluded | Should -BeTrue
        $result.LockCount | Should -Be 1
    }
}
