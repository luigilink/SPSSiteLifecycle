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
        documentation), RequiredIn and UsedIn (phases), Min and Max, Pattern and PatternHint (for a
        String, and for each entry of a StringList: a .NET regular expression that is matched as it is
        written, one character at a time, with no case folding and no culture, so that the Kelvin sign
        and a dotted capital I are not the letters k and i), Values, Kind (File or Folder, for the
        paths), MustExist, AllowEmpty (lists), NoEcho (a String that may hold a secret by mistake: a
        message about it never tells what it was given) and Description.

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
            Pattern = '\A[A-Za-z0-9][A-Za-z0-9-]{0,62}\z'
            PatternHint = 'letters, digits and hyphens only, starting with a letter or a digit, 63 characters at most: the first part of the SharePoint address (contoso for contoso.sharepoint.com), not a URL'
            Description = 'Name of the tenant: the first part of the SharePoint address (`contoso` for `contoso.sharepoint.com`).'
        }
        @{
            Section = 'Shared'; Name = 'ClientId'; Type = 'Guid'; RequiredIn = $both; UsedIn = $both
            Description = 'Application (client) ID of the Microsoft Entra app registration that PnP.PowerShell uses for the interactive sign-in. The setup script `src/Register-SPSSiteLifecycleApp.ps1` creates the app and shows it (see the [App registration](App-Registration) page).'
        }
        @{
            Section = 'Shared'; Name = 'Authentication'; Type = 'Choice'; UsedIn = $both
            Values = @('Interactive', 'Certificate'); Default = 'Interactive'; DefaultText = '`Interactive`'
            Description = 'How the tool signs in. `Interactive`: a person signs in, in a window, with the app of `ClientId`. `Certificate`: the app signs in alone, with a certificate, for a run that nobody watches (a scheduled task, a server); it needs `TenantId` and exactly one of `CertificateThumbprint` and `CertificatePath`, and an app that was registered for it (see the [App registration](App-Registration) page). The Act phase with `Execute` still needs a person to type its confirmation.'
        }
        @{
            Section = 'Shared'; Name = 'TenantId'; Type = 'Guid'; UsedIn = $both
            Description = 'ID of the Microsoft Entra tenant, a GUID: required when `Authentication` is `Certificate`, and used only then. The tool asks for the ID instead of building a name from `TenantName`, because the SharePoint name is not always the name of the tenant.'
        }
        @{
            Section = 'Shared'; Name = 'CertificateThumbprint'; Type = 'String'; UsedIn = $both
            Pattern = '\A[0-9A-Fa-f]{40}\z'
            PatternHint = '40 hexadecimal characters, with no spaces or colons'
            Description = 'Thumbprint of the certificate that the app signs in with, found in the `My` store of Windows (`CurrentUser`, then `LocalMachine`): Windows only. Exactly one of `CertificateThumbprint` and `CertificatePath` when `Authentication` is `Certificate`.'
        }
        @{
            Section = 'Shared'; Name = 'CertificatePath'; Type = 'Path'; Kind = 'File'; MustExist = $true; UsedIn = $both
            Description = 'The `.pfx` file of the certificate that the app signs in with, on any platform. A relative path is relative to the folder of the settings file. Keep the file outside the repository, in a folder that only the account that runs the tool can read.'
        }
        @{
            Section = 'Shared'; Name = 'CertificatePasswordVariable'; Type = 'String'; UsedIn = $both; NoEcho = $true
            Pattern = '\A[A-Za-z_][A-Za-z0-9_]{0,254}\z'
            PatternHint = 'the name of an environment variable: letters, digits and underscores, not starting with a digit'
            Description = 'Name of the environment variable that holds the password of the `.pfx` file, for `CertificatePath` only. When it is not given, the tool asks for the password, typed and never shown, which a run that nobody watches cannot do. **A password never goes in the settings file:** a key such as `CertificatePassword` is refused.'
        }
        @{
            Section = 'Shared'; Name = 'OutputFolder'; Type = 'Path'; Kind = 'Folder'; UsedIn = $both
            Default = 'Reports'; DefaultText = '`Reports`'
            Description = 'Folder where the reports, the checkpoints and the lock journal are written. It is created when missing. A relative path is relative to the folder of the settings file.'
        }
        @{
            Section = 'Shared'; Name = 'RefusedTenants'; Type = 'StringList'; UsedIn = $both; AllowEmpty = $true
            Pattern = '\A[A-Za-z0-9][A-Za-z0-9-]{0,62}\z'
            PatternHint = 'letters, digits and hyphens only, starting with a letter or a digit, 63 characters at most: the first part of the SharePoint address (contoso for contoso.sharepoint.com), not a URL'
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
            Description = 'CSV files that give the date each site was locked: a `Url` column, a `LockedOn` column and, optionally, a `SiteId` column. A row that has a site ID is matched to the site by that ID, whatever its address (a renamed site keeps its date, and a site that reuses an address does not inherit it); a row without one is matched by its URL. A header that only looks like `SiteId` (`Site ID`, a hidden character) stops the tool, because the site IDs would be lost without a message. A date before 2000-01-01 stops the tool, because a spreadsheet writes a blank date as `1900-01-01` or `1970-01-01`, and the site would look as if it had been locked for ever. When a site appears several times, in these files or in the lock journal, the latest date is kept. The structure of a file is read strictly: a quote that is never closed, a row that is cut short or has a value too many, and a value under a column that has no name stop the tool and name the line, because a row that is lost could leave an older date of the same site in force. The encoding is read as Excel writes it (UTF-8, UTF-16, Windows-1252).'
        }
        @{
            Section = 'Shared'; Name = 'ExclusionFiles'; Type = 'PathList'; Kind = 'File'; MustExist = $true; UsedIn = $both; AllowEmpty = $true
            Default = @(); DefaultText = '`@()`'
            Description = 'CSV files with a `Url` column: the sites that must never be touched. Both phases read them, because a decision never lifts a safeguard. Every filled cell must be a full address on one line: a row that cannot be read would protect nothing, so the tool stops instead of skipping it. The structure of a file is read strictly for the same reason: a quote that is never closed would swallow the rows after it, and a row that is cut short or has a value too many would be dropped, so they stop the tool and name the line. The encoding is read as Excel writes it (UTF-8, UTF-16, Windows-1252).'
        }
        @{
            Section = 'Shared'; Name = 'LockJournal'; Type = 'Path'; Kind = 'File'; UsedIn = $both
            Default = ''; DefaultText = '`lock-journal.csv` in `OutputFolder`'
            Description = 'CSV file where the Act phase records each site it locks (URL, site ID, lock date). Nothing is written in the tenant. Both phases read it as a source of lock dates. A journal that does not exist yet is an empty one, and one that exists is read strictly: a row that cannot be used, or a line that breaks the CSV rules (a stray quote, a quote that is never closed, a row too long or cut short), stops the tool and names the line, because a row that is lost could leave an older date in force. The journal must be UTF-8: a file in another encoding, or with a damaged byte, stops the tool instead of being repaired, because a character that is read wrong changes a web address. A date before 2000-01-01 stops the tool as well. The tool adds to it in UTF-8 and keeps the separator of the file, so a person can open it in Excel, but must save it as `CSV UTF-8` and close it before an Act run that locks sites.'
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
            Description = 'Lock states that the Scan phase lists. With `ReadOnly` alone, the server filters the listing, which is much faster on a large tenant. Add `Unlock` to also look for inactive sites that are not locked (suggested action `Lock`). A site in another lock state is left out of the report and counted in the summary, whether the server filtered the listing or not.'
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
        NoEcho      = $false
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
