function Get-SPSLifecycleSettingSchema {
    <#
        .SYNOPSIS
        Returns the table that describes every key of the settings file.

        .DESCRIPTION
        This table is the single source of truth for the settings: Get-SPSLifecycleSetting reads it to
        validate the file and to apply the defaults, tools/Update-Documentation.ps1 reads it to write
        the Configuration page, and a test checks that the example file mentions every key.

        Each row has: Section (Shared, Scan or Act; Shared keys are written at the top of the file,
        the others inside the Scan or Act section), Name, Type (String, Guid, Path, PathList,
        StringList, Choice, ChoiceList, Int, Double, Bool), Default, DefaultText (for the
        documentation), RequiredIn and UsedIn (phases), Min and Max, Pattern and PatternHint, Values,
        Kind (File or Folder, for the paths), MustExist, AllowEmpty (lists) and Description.

        .EXAMPLE
        Get-SPSLifecycleSettingSchema | Where-Object { $_.Section -eq 'Act' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    $both = @('Scan', 'Act')

    $definitions = @(
        @{
            Section = 'Shared'; Name = 'TenantName'; Type = 'String'; RequiredIn = $both; UsedIn = $both
            Pattern = '^[a-z0-9][a-z0-9-]{0,62}$'
            PatternHint = 'letters, digits and hyphens only: the first part of the SharePoint address (contoso for contoso.sharepoint.com), not a URL'
            Description = 'Name of the tenant: the first part of the SharePoint address (`contoso` for `contoso.sharepoint.com`).'
        }
        @{
            Section = 'Shared'; Name = 'ClientId'; Type = 'Guid'; RequiredIn = $both; UsedIn = $both
            Description = 'Application (client) ID of the Microsoft Entra app registration that PnP.PowerShell uses for the interactive sign-in.'
        }
        @{
            Section = 'Shared'; Name = 'OutputFolder'; Type = 'Path'; Kind = 'Folder'; UsedIn = $both
            Default = 'Reports'; DefaultText = '`Reports`'
            Description = 'Folder where the reports, the checkpoints and the lock journal are written. It is created when missing. A relative path is relative to the folder of the settings file.'
        }
        @{
            Section = 'Shared'; Name = 'RefusedTenants'; Type = 'StringList'; UsedIn = $both; AllowEmpty = $true
            Default = @(); DefaultText = '`@()`'
            Description = 'Tenant names that the tool refuses, in addition to the built-in list (`microsoft`, `microsoftonline`), which cannot be removed.'
        }
        @{
            Section = 'Shared'; Name = 'AcceptedLockStates'; Type = 'ChoiceList'; UsedIn = $both
            Values = @('ReadOnly', 'Unlock')
            Default = @('ReadOnly'); DefaultText = '`@(''ReadOnly'')`'
            Description = 'Lock states in which a site can be deleted or archived. `ReadOnly` is the safe default, because a person already decided to lock the site. Add `Unlock` to allow the direct deletion of an unlocked site. `NoAccess` is never accepted.'
        }
        @{
            Section = 'Shared'; Name = 'MinLockedDays'; Type = 'Int'; UsedIn = $both
            Min = 0; Max = 3650; Default = 365; DefaultText = '`365`'
            Description = 'A read-only site is deleted or archived only after it has been locked for this many days. The lock date comes from the lock date lists or the lock journal. A read-only site without a lock date is never deleted or archived.'
        }
        @{
            Section = 'Shared'; Name = 'DeleteMaxSizeGB'; Type = 'Double'; UsedIn = $both
            Min = 0; Max = 25600; Default = 1.0; DefaultText = '`1`'
            Description = 'A site larger than this size, in GB, is never deleted. The Scan phase suggests an archive instead, and the Act phase gives the row a `SKIP-TOO-LARGE-TO-DELETE` verdict. Set 25600, the largest possible size of a site, to remove the limit.'
        }
        @{
            Section = 'Shared'; Name = 'LockDateFiles'; Type = 'PathList'; Kind = 'File'; MustExist = $true; UsedIn = $both; AllowEmpty = $true
            Default = @(); DefaultText = '`@()`'
            Description = 'CSV files that give the date each site was locked: a `Url` column, a `LockedOn` column and, optionally, a `SiteId` column. When a site appears several times, the latest date is kept.'
        }
        @{
            Section = 'Shared'; Name = 'ExclusionFiles'; Type = 'PathList'; Kind = 'File'; MustExist = $true; UsedIn = $both; AllowEmpty = $true
            Default = @(); DefaultText = '`@()`'
            Description = 'CSV files with a `Url` column: the sites that must never be touched. Both phases read them, because a decision never lifts a safeguard. Every filled cell must be a full address on one line: a row that cannot be read would protect nothing, so the tool stops instead of skipping it.'
        }
        @{
            Section = 'Shared'; Name = 'LockJournal'; Type = 'Path'; Kind = 'File'; UsedIn = $both
            Default = ''; DefaultText = '`lock-journal.csv` in `OutputFolder`'
            Description = 'CSV file where the Act phase records each site it locks (URL, site ID, lock date). Nothing is written in the tenant. Both phases read it as a source of lock dates.'
        }
        @{
            Section = 'Shared'; Name = 'CsvDelimiter'; Type = 'Choice'; UsedIn = $both
            Values = @('Culture', ',', ';', 'Tab'); Default = 'Culture'; DefaultText = '`Culture`'
            Description = 'Separator of the CSV files the tool writes: `Culture` (the list separator of the current culture, a semicolon for French), `,`, `;` or `Tab`. The tool reads any of them.'
        }
        @{
            Section = 'Shared'; Name = 'CsvDateFormats'; Type = 'StringList'; UsedIn = $both; AllowEmpty = $true
            Default = @(); DefaultText = '`@()`'
            Description = 'Extra date formats accepted in the CSV files you provide, for example `dd/MM/yyyy`. ISO 8601 dates are always accepted. The value `Culture` also accepts the date patterns of the current culture. The tool never guesses a format.'
        }
        @{
            Section = 'Scan'; Name = 'InactiveDays'; Type = 'Int'; UsedIn = @('Scan')
            Min = 1; Max = 3650; Default = 365; DefaultText = '`365`'
            Description = 'A site is a candidate when its last activity is older than this many days.'
        }
        @{
            Section = 'Scan'; Name = 'LockStates'; Type = 'ChoiceList'; UsedIn = @('Scan')
            Values = @('ReadOnly', 'Unlock'); Default = @('ReadOnly'); DefaultText = '`@(''ReadOnly'')`'
            Description = 'Lock states that the Scan phase lists. With `ReadOnly` alone, the server filters the listing, which is much faster on a large tenant. Add `Unlock` to also look for inactive sites that are not locked (suggested action `Lock`).'
        }
        @{
            Section = 'Scan'; Name = 'SharePointUsageReport'; Type = 'Path'; Kind = 'File'; MustExist = $true; UsedIn = @('Scan')
            Default = ''; DefaultText = '(none)'
            Description = 'CSV file of the SharePoint site usage report (Microsoft 365 admin center, Reports, Usage). The Scan phase needs at least one of the three activity reports.'
        }
        @{
            Section = 'Scan'; Name = 'TeamsActivityReport'; Type = 'Path'; Kind = 'File'; MustExist = $true; UsedIn = @('Scan')
            Default = ''; DefaultText = '(none)'
            Description = 'CSV file of the Microsoft Teams activity report (teams). It shows the activity that the SharePoint report does not see.'
        }
        @{
            Section = 'Scan'; Name = 'GroupsActivityReport'; Type = 'Path'; Kind = 'File'; MustExist = $true; UsedIn = @('Scan')
            Default = ''; DefaultText = '(none)'
            Description = 'CSV file of the Microsoft 365 groups activity report.'
        }
        @{
            Section = 'Act'; Name = 'InputFile'; Type = 'Path'; Kind = 'File'; MustExist = $true; RequiredIn = @('Act'); UsedIn = @('Act')
            Default = ''; DefaultText = '(required)'
            Description = 'The Scan CSV, once a person has filled in its `Decision` column.'
        }
        @{
            Section = 'Act'; Name = 'Execute'; Type = 'Bool'; UsedIn = @('Act')
            Default = $false; DefaultText = '`$false`'
            Description = '`$false`: report only, nothing is changed. `$true`: apply the decisions, after the typed confirmation.'
        }
        @{
            Section = 'Act'; Name = 'MaxActions'; Type = 'Int'; UsedIn = @('Act')
            Min = 1; Max = 10000; Default = 25; DefaultText = '`25`'
            Description = 'Maximum number of actions in one run.'
        }
        @{
            Section = 'Act'; Name = 'DelaySeconds'; Type = 'Int'; UsedIn = @('Act')
            Min = 0; Max = 300; Default = 2; DefaultText = '`2`'
            Description = 'Pause, in seconds, between two actions.'
        }
        @{
            Section = 'Act'; Name = 'MaxCsvAgeDays'; Type = 'Int'; UsedIn = @('Act')
            Min = 1; Max = 365; Default = 30; DefaultText = '`30`'
            Description = 'The Scan CSV must not be older than this many days: a site may have changed since.'
        }
        @{
            Section = 'Act'; Name = 'GrantSiteAdmin'; Type = 'Bool'; UsedIn = @('Act')
            Default = $false; DefaultText = '`$false`'
            Description = 'Before archiving a site, add the signed-in administrator as administrator of the site collection, which the archive needs. Requires `UnlockBeforeArchive`, because a read-only site refuses an owner change.'
        }
        @{
            Section = 'Act'; Name = 'UnlockBeforeArchive'; Type = 'Bool'; UsedIn = @('Act')
            Default = $false; DefaultText = '`$false`'
            Description = 'Unlock a read-only site before archiving it, and lock it again afterwards.'
        }
    )

    $template = [ordered]@{
        Section     = ''
        Name        = ''
        Type        = ''
        Default     = $null
        DefaultText = '(none)'
        RequiredIn  = @()
        UsedIn      = @()
        Min         = $null
        Max         = $null
        Pattern     = ''
        PatternHint = ''
        Values      = @()
        Kind        = ''
        MustExist   = $false
        AllowEmpty  = $false
        Description = ''
    }

    foreach ($definition in $definitions) {
        $row = [ordered]@{}
        foreach ($property in $template.Keys) {
            if ($definition.ContainsKey($property)) {
                $row[$property] = $definition[$property]
            }
            else {
                $row[$property] = $template[$property]
            }
        }

        [PSCustomObject]$row
    }
}
