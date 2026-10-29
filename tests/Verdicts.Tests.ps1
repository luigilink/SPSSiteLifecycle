BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    $script:Setting = [PSCustomObject]@{
        TenantName         = 'contoso'
        TenantUrl          = 'https://contoso.sharepoint.com'
        AcceptedLockStates = @('ReadOnly')
        MinLockedDays      = 365
        DeleteMaxSizeGB    = 1.0
        Scan               = [PSCustomObject]@{ InactiveDays = 365 }
    }
    $script:Now = [System.DateTime]::new(2026, 10, 29, 8, 0, 0, [System.DateTimeKind]::Utc)
    $script:Old = [System.DateTime]::new(2025, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $script:GroupId = '11111111-1111-1111-1111-111111111111'
    $script:Quiet = [PSCustomObject]@{ HasRow = $true; LastActivity = $null }

    function script:New-TestSite {
        param(
            [string]$Url = 'https://contoso.sharepoint.com/sites/a',
            [string]$Template = 'GROUP#0',
            [string]$LockState = 'ReadOnly',
            [string]$GroupId = $script:GroupId,
            $Size = 100,
            [string]$Archive = 'NotArchived',
            [bool]$Hub = $false,
            [bool]$Channel = $false,
            $Modified = $null
        )

        [PSCustomObject]@{
            Url                     = $Url
            Template                = $Template
            LockState               = $LockState
            GroupId                 = $GroupId
            StorageUsedMB           = $Size
            ArchiveStatus           = $Archive
            IsHubSite               = $Hub
            IsTeamsChannelConnected = $Channel
            LastContentModified     = $Modified
        }
    }

    function script:Get-TestVerdict {
        param(
            $Site,
            [string]$Action,
            $LockedOn = $script:Old,
            $Activity = $null,
            [string]$GroupState = '',
            [bool]$Excluded = $false,
            $Setting = $script:Setting,
            [string]$HomeSiteUrl = ''
        )

        $parameters = @{ Site = $Site; Setting = $Setting; Action = $Action; Now = $script:Now; Excluded = $Excluded; GroupState = $GroupState; HomeSiteUrl = $HomeSiteUrl }
        if ($null -ne $LockedOn) { $parameters.LockedOn = $LockedOn }
        if ($null -ne $Activity) { $parameters.Activity = $Activity }
        & $script:Module { param($p) Get-SPSLifecycleVerdict @p } $parameters
    }
}

Describe 'Get-SPSLifecycleVerdict' {
    Context 'Scan: what the tool suggests' {
        It 'suggests <Expected> for <Name>' -ForEach @(
            @{ Name = 'a quiet read-only site with a group'; Expected = 'DELETE-VIA-GROUP'; Case = 'group' }
            @{ Name = 'a quiet read-only site without a group'; Expected = 'DELETE-SITE'; Case = 'nogroup' }
            @{ Name = 'a large site'; Expected = 'ARCHIVE'; Case = 'large' }
            @{ Name = 'a large site that cannot be archived'; Expected = 'SKIP-NOT-ARCHIVABLE'; Case = 'largeunarchivable' }
            @{ Name = 'an unlocked site'; Expected = 'LOCK'; Case = 'unlocked' }
            @{ Name = 'a read-only site without a lock date'; Expected = 'SKIP-NO-LOCK-DATE'; Case = 'nodate' }
            @{ Name = 'a site locked 100 days ago'; Expected = 'SKIP-TOO-RECENT-LOCK'; Case = 'recentlock' }
            @{ Name = 'a site with a recent activity'; Expected = 'SKIP-RECENT-ACTIVITY'; Case = 'activity' }
            @{ Name = 'a site whose content changed recently'; Expected = 'SKIP-RECENT-ACTIVITY'; Case = 'modified' }
            @{ Name = 'a site that is in no report'; Expected = 'REVIEW-NO-ACTIVITY-ROW'; Case = 'norow' }
            @{ Name = 'a site whose size is unknown'; Expected = 'REVIEW-NO-SIZE'; Case = 'nosize' }
        ) {
            $site = New-TestSite
            $lockedOn = $script:Old
            $activity = $script:Quiet
            switch ($Case) {
                'nogroup' { $site = New-TestSite -GroupId '' }
                'large' { $site = New-TestSite -Size 5000 }
                'largeunarchivable' { $site = New-TestSite -Size 5000 -Template 'BLANKINTERNET#0' }
                'unlocked' { $site = New-TestSite -LockState 'Unlock'; $lockedOn = $null }
                'nodate' { $lockedOn = $null }
                'recentlock' { $lockedOn = $script:Now.AddDays(-100) }
                'activity' { $activity = [PSCustomObject]@{ HasRow = $true; LastActivity = [System.DateTime]::new(2026, 10, 1, 0, 0, 0, [System.DateTimeKind]::Utc) } }
                'modified' { $site = New-TestSite -Modified $script:Now.AddDays(-10) }
                'norow' { $activity = [PSCustomObject]@{ HasRow = $false; LastActivity = $null } }
                'nosize' { $site = New-TestSite -Size $null }
            }

            Get-TestVerdict -Site $site -Action Suggest -LockedOn $lockedOn -Activity $activity | Should -Be $Expected
        }

        It 'treats a missing activity object as a site that is in no report' {
            Get-TestVerdict -Site (New-TestSite) -Action Suggest | Should -Be 'REVIEW-NO-ACTIVITY-ROW'
        }

        It 'does not take an old content change for a proof of inactivity' {
            $absent = [PSCustomObject]@{ HasRow = $false; LastActivity = $null }

            Get-TestVerdict -Site (New-TestSite -Modified $script:Old) -Action Suggest -Activity $absent | Should -Be 'REVIEW-NO-ACTIVITY-ROW'
        }

        It 'suggests a direct deletion of an unlocked site when Unlock is accepted, without a lock date' {
            $setting = $script:Setting.PSObject.Copy()
            $setting.AcceptedLockStates = @('ReadOnly', 'Unlock')

            Get-TestVerdict -Site (New-TestSite -LockState 'Unlock') -Action Suggest -LockedOn $null -Activity $script:Quiet -Setting $setting | Should -Be 'DELETE-VIA-GROUP'
        }

        It 'does not suggest anything for a site in the lock state <State>' -ForEach @(
            @{ State = 'NoAccess' }
            @{ State = 'NoAdditions' }
            @{ State = '' }
        ) {
            Get-TestVerdict -Site (New-TestSite -LockState $State) -Action Suggest -Activity $script:Quiet | Should -Be 'SKIP-LOCK-STATE'
        }
    }

    Context 'Act: what a decision leads to' {
        It 'gives <Expected> to a Delete decision on <Name>' -ForEach @(
            @{ Name = 'a read-only site with an active group'; Expected = 'DELETE-VIA-GROUP'; Case = 'active' }
            @{ Name = 'a read-only site without a group'; Expected = 'DELETE-SITE'; Case = 'nogroup' }
            @{ Name = 'a site larger than the limit'; Expected = 'SKIP-TOO-LARGE-TO-DELETE'; Case = 'large' }
            @{ Name = 'a site whose group is in the recycle bin'; Expected = 'REVIEW-GROUP-SOFTDELETED'; Case = 'softdeleted' }
            @{ Name = 'a site whose group cannot be found'; Expected = 'REVIEW-GROUP-NOTFOUND'; Case = 'notfound' }
            @{ Name = 'a site in an exclusion list'; Expected = 'SKIP-EXCLUDED'; Case = 'excluded' }
            @{ Name = 'a site locked too recently'; Expected = 'SKIP-TOO-RECENT-LOCK'; Case = 'recent' }
            @{ Name = 'a site with an unknown size'; Expected = 'REVIEW-NO-SIZE'; Case = 'nosize' }
        ) {
            $site = New-TestSite
            $parameters = @{ GroupState = 'Active' }
            switch ($Case) {
                'nogroup' { $site = New-TestSite -GroupId ''; $parameters = @{ GroupState = 'None' } }
                'large' { $site = New-TestSite -Size 2048 }
                'softdeleted' { $parameters = @{ GroupState = 'SoftDeleted' } }
                'notfound' { $parameters = @{ GroupState = 'NotFound' } }
                'excluded' { $parameters.Excluded = $true }
                'recent' { $parameters.LockedOn = $script:Now.AddDays(-30) }
                'nosize' { $site = New-TestSite -Size $null }
            }

            Get-TestVerdict -Site $site -Action Delete @parameters | Should -Be $Expected
        }

        It 'archives a large site' {
            Get-TestVerdict -Site (New-TestSite -Size 2048) -Action Archive -GroupState Active | Should -Be 'ARCHIVE'
        }

        It 'does not need the size to archive' {
            Get-TestVerdict -Site (New-TestSite -Size $null) -Action Archive -GroupState Active | Should -Be 'ARCHIVE'
        }

        It 'refuses to archive the template <Template>' -ForEach @(
            @{ Template = 'BLANKINTERNET#0' }
            @{ Template = 'PWA#0' }
            @{ Template = 'SPSPORTAL#0' }
        ) {
            Get-TestVerdict -Site (New-TestSite -Template $Template) -Action Archive -GroupState Active | Should -Be 'SKIP-NOT-ARCHIVABLE'
        }

        It 'locks an unlocked site' {
            Get-TestVerdict -Site (New-TestSite -LockState 'Unlock') -Action Lock -LockedOn $null -GroupState Active | Should -Be 'LOCK'
        }

        It 'does not lock a site that is not unlocked: <State>' -ForEach @(
            @{ State = 'ReadOnly' }
            @{ State = 'NoAccess' }
        ) {
            Get-TestVerdict -Site (New-TestSite -LockState $State) -Action Lock | Should -Be 'SKIP-LOCK-STATE'
        }

        It 'refuses to delete an unlocked site by default' {
            Get-TestVerdict -Site (New-TestSite -LockState 'Unlock') -Action Delete -LockedOn $null -GroupState Active | Should -Be 'SKIP-LOCK-STATE'
        }

        It 'deletes an unlocked site when the settings accept the Unlock state' {
            $setting = $script:Setting.PSObject.Copy()
            $setting.AcceptedLockStates = @('ReadOnly', 'Unlock')

            Get-TestVerdict -Site (New-TestSite -LockState 'Unlock') -Action Delete -LockedOn $null -GroupState Active -Setting $setting | Should -Be 'DELETE-VIA-GROUP'
        }

        It 'never accepts NoAccess, whatever the settings' {
            $setting = $script:Setting.PSObject.Copy()
            $setting.AcceptedLockStates = @('ReadOnly', 'Unlock')

            Get-TestVerdict -Site (New-TestSite -LockState 'NoAccess') -Action Delete -GroupState Active -Setting $setting | Should -Be 'SKIP-LOCK-STATE'
        }
    }

    Context 'Boundaries' {
        It 'accepts a site locked exactly MinLockedDays ago' {
            Get-TestVerdict -Site (New-TestSite -GroupId '') -Action Delete -LockedOn $script:Now.AddDays(-365) | Should -Be 'DELETE-SITE'
        }

        It 'refuses a site locked one day less than MinLockedDays ago' {
            Get-TestVerdict -Site (New-TestSite -GroupId '') -Action Delete -LockedOn $script:Now.AddDays(-364) | Should -Be 'SKIP-TOO-RECENT-LOCK'
        }

        It 'deletes a site of exactly DeleteMaxSizeGB' {
            Get-TestVerdict -Site (New-TestSite -GroupId '' -Size 1024) -Action Delete | Should -Be 'DELETE-SITE'
        }

        It 'refuses a site larger than DeleteMaxSizeGB' {
            Get-TestVerdict -Site (New-TestSite -GroupId '' -Size 1025) -Action Delete | Should -Be 'SKIP-TOO-LARGE-TO-DELETE'
        }

        It 'treats a site as inactive when its last activity is exactly InactiveDays old' {
            $activity = [PSCustomObject]@{ HasRow = $true; LastActivity = $script:Now.AddDays(-365) }

            Get-TestVerdict -Site (New-TestSite -GroupId '') -Action Suggest -Activity $activity | Should -Be 'DELETE-SITE'
        }
    }

    Context 'A decision never lifts a safeguard' {
        It 'gives <Expected> to <Name>, whatever the action (<Action>)' -ForEach @(
            @{ Name = 'a OneDrive template'; Expected = 'SKIP-ONEDRIVE'; Action = 'Delete'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'SPSPERS#10' }
            @{ Name = 'a OneDrive template'; Expected = 'SKIP-ONEDRIVE'; Action = 'Archive'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'SPSPERS#10' }
            @{ Name = 'a OneDrive template'; Expected = 'SKIP-ONEDRIVE'; Action = 'Lock'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'SPSPERS#10' }
            @{ Name = 'a OneDrive URL on a team template'; Expected = 'SKIP-ONEDRIVE'; Action = 'Delete'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'STS#3' }
            @{ Name = 'a channel site'; Expected = 'SKIP-CHANNEL-SITE'; Action = 'Delete'; Url = 'https://contoso.sharepoint.com/sites/a-channel'; Template = 'TEAMCHANNEL#1' }
            @{ Name = 'a channel site'; Expected = 'SKIP-CHANNEL-SITE'; Action = 'Archive'; Url = 'https://contoso.sharepoint.com/sites/a-channel'; Template = 'TEAMCHANNEL#0' }
            @{ Name = 'the root site'; Expected = 'SKIP-PROTECTED'; Action = 'Delete'; Url = 'https://contoso.sharepoint.com/'; Template = 'SITEPAGEPUBLISHING#0' }
            @{ Name = 'the root site'; Expected = 'SKIP-PROTECTED'; Action = 'Lock'; Url = 'https://contoso.sharepoint.com'; Template = 'STS#3' }
            @{ Name = 'the content type hub'; Expected = 'SKIP-PROTECTED'; Action = 'Delete'; Url = 'https://contoso.sharepoint.com/sites/contentTypeHub'; Template = 'STS#3' }
            @{ Name = 'the app catalog'; Expected = 'SKIP-PROTECTED'; Action = 'Delete'; Url = 'https://contoso.sharepoint.com/sites/appcatalog'; Template = 'APPCATALOG#0' }
            @{ Name = 'an archived site'; Expected = 'SKIP-ALREADY-ARCHIVED'; Action = 'Delete'; Url = 'https://contoso.sharepoint.com/sites/a'; Template = 'GROUP#0'; Archive = 'Archived' }
            @{ Name = 'a site being archived'; Expected = 'SKIP-ALREADY-ARCHIVED'; Action = 'Archive'; Url = 'https://contoso.sharepoint.com/sites/a'; Template = 'GROUP#0'; Archive = 'Archiving' }
        ) {
            $archive = if ($Archive) { $Archive } else { 'NotArchived' }
            $site = New-TestSite -Url $Url -Template $Template -Archive $archive

            Get-TestVerdict -Site $site -Action $Action -GroupState Active | Should -Be $Expected
        }

        It 'protects a hub site' {
            Get-TestVerdict -Site (New-TestSite -Hub $true) -Action Delete -GroupState Active | Should -Be 'SKIP-PROTECTED'
        }

        It 'protects the home site' {
            Get-TestVerdict -Site (New-TestSite -Url 'https://contoso.sharepoint.com/sites/home') -Action Delete -GroupState Active -HomeSiteUrl 'https://contoso.sharepoint.com/sites/Home/' | Should -Be 'SKIP-PROTECTED'
        }

        It 'protects the system template <Pattern>' -ForEach @(
            @{ Pattern = 'APPCATALOG#0' }, @{ Pattern = 'CENTRALADMIN#0' }, @{ Pattern = 'CSPCONTAINER#1' }, @{ Pattern = 'EDISC#0' }
            @{ Pattern = 'FunSite#0' }, @{ Pattern = 'POINTPUBLISHINGHUB#0' }, @{ Pattern = 'POINTPUBLISHINGPERSONAL#0' }, @{ Pattern = 'POINTPUBLISHINGTOPIC#0' }
            @{ Pattern = 'POLICYCTR#0' }, @{ Pattern = 'REDIRECTSITE#0' }, @{ Pattern = 'REVIEWCTR#0' }, @{ Pattern = 'SPSMSITEHOST#0' }
            @{ Pattern = 'SRCHCEN#0' }, @{ Pattern = 'TENANTADMIN#0' }, @{ Pattern = 'TestSite#0' }
        ) {
            Get-TestVerdict -Site (New-TestSite -Template $Pattern) -Action Delete -GroupState Active | Should -Be 'SKIP-PROTECTED'
        }

        It 'protects the system path <Path>' -ForEach @(
            @{ Path = '/sites/contenttypehub' }, @{ Path = '/sites/CompliancePolicyCenter' }, @{ Path = '/portal/hub' }, @{ Path = '/search' }
        ) {
            Get-TestVerdict -Site (New-TestSite -Url "https://contoso.sharepoint.com$Path" -Template 'STS#3') -Action Delete -GroupState Active | Should -Be 'SKIP-PROTECTED'
        }
    }

    Context 'Unknown or unreadable input fails closed' {
        It 'does not act on a group-connected site whose group state was not read: <Action>' -ForEach @(
            @{ Action = 'Delete' }
            @{ Action = 'Archive' }
        ) {
            Get-TestVerdict -Site (New-TestSite) -Action $Action | Should -Be 'REVIEW-GROUP-NOTFOUND'
        }

        It 'does not lock a group-connected site whose group state was not read' {
            Get-TestVerdict -Site (New-TestSite -LockState 'Unlock') -Action Lock -LockedOn $null | Should -Be 'REVIEW-GROUP-NOTFOUND'
        }

        It 'does not act when the live read finds no group but the site has a group ID' {
            Get-TestVerdict -Site (New-TestSite) -Action Delete -GroupState None | Should -Be 'REVIEW-GROUP-NOTFOUND'
        }

        It 'does not need a group state for a site without a group' {
            Get-TestVerdict -Site (New-TestSite -GroupId '') -Action Delete | Should -Be 'DELETE-SITE'
        }

        It 'does not need a group state in Scan, which does not read groups' {
            Get-TestVerdict -Site (New-TestSite) -Action Suggest -Activity $script:Quiet | Should -Be 'DELETE-VIA-GROUP'
        }

        It 'refuses a group state that does not exist, instead of reading it as not active' {
            { Get-TestVerdict -Site (New-TestSite) -Action Delete -GroupState 'Actif' } | Should -Throw
        }

        It 'treats the size <Name> as unknown, never as zero' -ForEach @(
            @{ Name = 'a blank text'; Size = ' ' }
            @{ Name = 'an empty text'; Size = '' }
            @{ Name = 'NaN'; Size = [System.Double]::NaN }
            @{ Name = 'a text that is not a number'; Size = 'unknown' }
            @{ Name = 'a negative number'; Size = -5 }
            @{ Name = 'infinity'; Size = [System.Double]::PositiveInfinity }
            @{ Name = 'a number with a decimal comma'; Size = '1,5' }
            @{ Name = 'a boolean'; Size = $true }
        ) {
            Get-TestVerdict -Site (New-TestSite -GroupId '' -Size $Size) -Action Delete | Should -Be 'REVIEW-NO-SIZE'
            Get-TestVerdict -Site (New-TestSite -GroupId '' -Size $Size) -Action Suggest -Activity $script:Quiet | Should -Be 'REVIEW-NO-SIZE'
        }

        It 'reads the size <Name>' -ForEach @(
            @{ Name = 'zero'; Size = 0; Expected = 'DELETE-SITE' }
            @{ Name = 'a whole number'; Size = 100; Expected = 'DELETE-SITE' }
            @{ Name = 'a text with a decimal point'; Size = '100.5'; Expected = 'DELETE-SITE' }
            @{ Name = 'a double'; Size = 100.5; Expected = 'DELETE-SITE' }
            @{ Name = 'an exponent'; Size = '1E3'; Expected = 'DELETE-SITE' }
            @{ Name = 'a double above the limit'; Size = 1500.5; Expected = 'SKIP-TOO-LARGE-TO-DELETE' }
            @{ Name = 'a text above the limit'; Size = '1500.5'; Expected = 'SKIP-TOO-LARGE-TO-DELETE' }
        ) {
            Get-TestVerdict -Site (New-TestSite -GroupId '' -Size $Size) -Action Delete | Should -Be $Expected
        }

        It 'reads the size the same way under <Culture>' -ForEach @(
            @{ Culture = 'en-US' }
            @{ Culture = 'fr-FR' }
            @{ Culture = 'de-DE' }
        ) {
            $previous = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                Get-TestVerdict -Site (New-TestSite -GroupId '' -Size 1500.5) -Action Delete | Should -Be 'SKIP-TOO-LARGE-TO-DELETE'
                Get-TestVerdict -Site (New-TestSite -GroupId '' -Size '1500.5') -Action Delete | Should -Be 'SKIP-TOO-LARGE-TO-DELETE'
                Get-TestVerdict -Site (New-TestSite -GroupId '' -Size 100.5) -Action Delete | Should -Be 'DELETE-SITE'
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $previous
            }
        }
    }

    Context 'The catalog' {
        BeforeAll {
            $script:Catalog = @(& $script:Module { Get-SPSLifecycleVerdictCatalog })
        }

        It 'lists every verdict once' {
            @($script:Catalog | Group-Object -Property Verdict | Where-Object { $_.Count -gt 1 }) | Should -HaveCount 0
        }

        It 'names the kind of each verdict by its prefix' {
            foreach ($row in $script:Catalog) {
                $expected = if ($row.Verdict -like 'SKIP-*') { 'Skip' } elseif ($row.Verdict -like 'REVIEW-*') { 'Review' } else { 'Action' }
                $row.Kind | Should -Be $expected -Because $row.Verdict
                $row.Meaning | Should -Not -BeNullOrEmpty
            }
        }

        It 'contains the verdict <Expected>' -ForEach @(
            @{ Expected = 'SKIP-ONEDRIVE' }, @{ Expected = 'SKIP-CHANNEL-SITE' }, @{ Expected = 'SKIP-PROTECTED' }, @{ Expected = 'SKIP-ALREADY-ARCHIVED' }
            @{ Expected = 'SKIP-LOCK-STATE' }, @{ Expected = 'SKIP-EXCLUDED' }, @{ Expected = 'SKIP-NO-LOCK-DATE' }, @{ Expected = 'SKIP-TOO-RECENT-LOCK' }
            @{ Expected = 'REVIEW-NO-ACTIVITY-ROW' }, @{ Expected = 'SKIP-RECENT-ACTIVITY' }, @{ Expected = 'REVIEW-NO-SIZE' }
            @{ Expected = 'REVIEW-GROUP-SOFTDELETED' }, @{ Expected = 'REVIEW-GROUP-NOTFOUND' }, @{ Expected = 'SKIP-NOT-ARCHIVABLE' }
            @{ Expected = 'SKIP-TOO-LARGE-TO-DELETE' }, @{ Expected = 'LOCK' }, @{ Expected = 'ARCHIVE' }, @{ Expected = 'DELETE-SITE' }
            @{ Expected = 'DELETE-VIA-GROUP' }, @{ Expected = 'SKIP-NOT-FOUND' }, @{ Expected = 'SKIP-SITEID-MISMATCH' }
            @{ Expected = 'REVIEW-CONTENT-MODIFIED' }, @{ Expected = 'REVIEW-RETENTION' }
        ) {
            $script:Catalog.Verdict | Should -Contain $Expected
        }

        It 'covers every verdict that the function can return' {
            $tokens = $null
            $errors = $null
            $path = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/Private/Get-SPSLifecycleVerdict.ps1'
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            $returned = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -cmatch '^(SKIP|REVIEW)-[A-Z-]+$|^(LOCK|ARCHIVE|DELETE-SITE|DELETE-VIA-GROUP)$' }, $true) | ForEach-Object { $_.Value } | Sort-Object -Unique

            $returned | Should -Not -BeNullOrEmpty
            foreach ($verdict in $returned) {
                $script:Catalog.Verdict | Should -Contain $verdict
            }
        }
    }
}

Describe 'Test-SPSLifecycleArchivableTemplate' {
    It 'knows the 13 templates of Microsoft Learn' {
        @(& $script:Module { Get-SPSLifecycleArchivableTemplate }) | Should -HaveCount 13
    }

    It 'answers <Expected> for <Template>' -ForEach @(
        @{ Template = 'GROUP#0'; Expected = $true }
        @{ Template = 'group#0'; Expected = $true }
        @{ Template = 'STS#3'; Expected = $true }
        @{ Template = 'SITEPAGEPUBLISHING#0'; Expected = $true }
        @{ Template = 'OFFILE#1'; Expected = $true }
        @{ Template = 'BLANKINTERNET#0'; Expected = $false }
        @{ Template = 'SPSPERS#10'; Expected = $false }
        @{ Template = 'TEAMCHANNEL#1'; Expected = $false }
        @{ Template = ''; Expected = $false }
        @{ Template = $null; Expected = $false }
    ) {
        $result = & $script:Module { param($t) Test-SPSLifecycleArchivableTemplate -Template $t } $Template

        $result | Should -Be $Expected
    }
}

Describe 'Test-SPSLifecycleOneDrive' {
    BeforeAll {
        function script:Test-TestOneDrive {
            param([string]$Url, [string]$Template, [string]$Tenant = 'contoso')
            $site = [PSCustomObject]@{ Url = $Url; Template = $Template }
            & $script:Module { param($s, $t) Test-SPSLifecycleOneDrive -Site $s -TenantName $t } $site $Tenant
        }
    }

    It 'answers <Expected> for <Name>' -ForEach @(
        @{ Name = 'the OneDrive template'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'SPSPERS#10'; Tenant = 'contoso'; Expected = $true }
        @{ Name = 'another personal template'; Url = 'https://contoso.sharepoint.com/sites/x'; Template = 'SPSPERS#2'; Tenant = 'contoso'; Expected = $true }
        @{ Name = 'a template in lowercase'; Url = 'https://contoso.sharepoint.com/sites/x'; Template = 'spspers#10'; Tenant = 'contoso'; Expected = $true }
        @{ Name = 'a OneDrive address on a team template'; Url = 'https://contoso-my.sharepoint.com/personal/a_contoso_com'; Template = 'STS#3'; Tenant = 'contoso'; Expected = $true }
        @{ Name = 'a OneDrive address in capitals, for a tenant written in capitals'; Url = 'HTTPS://CONTOSO-MY.sharepoint.com/Personal/A'; Template = 'STS#3'; Tenant = 'Contoso'; Expected = $true }
        @{ Name = 'the root of the OneDrive host'; Url = 'https://contoso-my.sharepoint.com'; Template = ''; Tenant = 'contoso'; Expected = $true }
        @{ Name = 'a team site'; Url = 'https://contoso.sharepoint.com/sites/x'; Template = 'GROUP#0'; Tenant = 'contoso'; Expected = $false }
        @{ Name = 'the OneDrive host of another tenant'; Url = 'https://fabrikam-my.sharepoint.com/personal/a'; Template = 'STS#3'; Tenant = 'contoso'; Expected = $false }
        @{ Name = 'a host that only starts like the OneDrive host'; Url = 'https://contoso-my.sharepoint.com.example.org/personal/a'; Template = 'STS#3'; Tenant = 'contoso'; Expected = $false }
        @{ Name = 'a site whose path looks like OneDrive'; Url = 'https://contoso.sharepoint.com/sites/contoso-my.sharepoint.com'; Template = 'STS#3'; Tenant = 'contoso'; Expected = $false }
        @{ Name = 'no template and no address'; Url = ''; Template = $null; Tenant = 'contoso'; Expected = $false }
    ) {
        (Test-TestOneDrive -Url $Url -Template $Template -Tenant $Tenant) | Should -Be $Expected
    }
}
