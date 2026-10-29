# Configuration

> This page is generated from the settings schema of the module. Do not edit it by hand: change the schema, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.

SPSSiteLifecycle reads its settings from one PowerShell data file (`.psd1`). Copy [`src/config/SPSSiteLifecycle.example.psd1`](https://github.com/luigilink/SPSSiteLifecycle/blob/main/src/config/SPSSiteLifecycle.example.psd1), fill it in, and give it to the script:

```powershell
pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan
pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Act
```

## How the file is read

- The file holds data only. It is read with `Import-PowerShellDataFile`, so no code in it ever runs.
- Shared settings are written at the top of the file. The settings of one phase are written in the `Scan` or the `Act` section.
- The whole file is checked before anything runs, and every problem is reported at once.
- An unknown setting stops the tool, so that a typo cannot silently disable a safeguard. The message suggests the closest name and says when a setting is in the wrong section.
- Types are strict. A number is written `25`, not `'25'`, and a boolean is `$true` or `$false`, never `'false'` (a non-empty text would count as true).
- A relative path is relative to the folder of the settings file, not to the current folder. Both `\` and `/` are accepted.
- The required settings and the existence of the input files are checked for the requested phase only, so that a Scan can run before the settings of the Act section are filled in.
- `Execute` and `MaxActions` are settings of the `Act` section. They are not command-line parameters.
- The tool refuses the Microsoft corporate tenants (`microsoft` and `microsoftonline`) whatever the settings say. `RefusedTenants` only adds names.

## Shared settings

Written at the top of the file.

| Setting | Type | Default | Required in | Used by | Description |
|---------|------|---------|-------------|---------|-------------|
| `TenantName` | text | (none) | Scan and Act | Scan and Act | Name of the tenant: the first part of the SharePoint address (`contoso` for `contoso.sharepoint.com`). |
| `ClientId` | GUID | (none) | Scan and Act | Scan and Act | Application (client) ID of the Microsoft Entra app registration that PnP.PowerShell uses for the interactive sign-in. |
| `OutputFolder` | folder path | `Reports` | no | Scan and Act | Folder where the reports, the checkpoints and the lock journal are written. It is created when missing. A relative path is relative to the folder of the settings file. |
| `RefusedTenants` | list of texts | `@()` | no | Scan and Act | Tenant names that the tool refuses, in addition to the built-in list (`microsoft`, `microsoftonline`), which cannot be removed. |
| `AcceptedLockStates` | list of `ReadOnly`, `Unlock` | `@('ReadOnly')` | no | Scan and Act | Lock states in which a site can be deleted or archived. `ReadOnly` is the safe default, because a person already decided to lock the site. Add `Unlock` to allow the direct deletion of an unlocked site. `NoAccess` is never accepted. |
| `MinLockedDays` | whole number, 0 to 3650 | `365` | no | Scan and Act | A read-only site is deleted or archived only after it has been locked for this many days. The lock date comes from the lock date lists or the lock journal. A read-only site without a lock date is never deleted or archived. |
| `DeleteMaxSizeGB` | number, 0 to 25600 | `1` | no | Scan and Act | A site larger than this size, in GB, is never deleted. The Scan phase suggests an archive instead, and the Act phase gives the row a `SKIP-TOO-LARGE-TO-DELETE` verdict. Set 25600, the largest possible size of a site, to remove the limit. |
| `LockDateFiles` | list of file paths | `@()` | no | Scan and Act | CSV files that give the date each site was locked: a `Url` column, a `LockedOn` column and, optionally, a `SiteId` column. A row that has a site ID is matched to the site by that ID, whatever its address (a renamed site keeps its date, and a site that reuses an address does not inherit it); a row without one is matched by its URL. A header that only looks like `SiteId` (`Site ID`, a hidden character) stops the tool, because the site IDs would be lost without a message. A date before 2000-01-01 stops the tool, because a spreadsheet writes a blank date as `1900-01-01` or `1970-01-01`, and the site would look as if it had been locked for ever. When a site appears several times, in these files or in the lock journal, the latest date is kept. |
| `ExclusionFiles` | list of file paths | `@()` | no | Scan and Act | CSV files with a `Url` column: the sites that must never be touched. Both phases read them, because a decision never lifts a safeguard. Every filled cell must be a full address on one line: a row that cannot be read would protect nothing, so the tool stops instead of skipping it. |
| `LockJournal` | file path | `lock-journal.csv` in `OutputFolder` | no | Scan and Act | CSV file where the Act phase records each site it locks (URL, site ID, lock date). Nothing is written in the tenant. Both phases read it as a source of lock dates. A journal that does not exist yet is an empty one, and one that exists is read strictly: a row that cannot be used, or a line that breaks the CSV rules (a stray quote, a quote that is never closed, a row too long or cut short), stops the tool and names the line, because a row that is lost could leave an older date in force. The journal must be UTF-8: a file in another encoding, or with a damaged byte, stops the tool instead of being repaired, because a character that is read wrong changes a web address. A date before 2000-01-01 stops the tool as well. The tool adds to it in UTF-8 and keeps the separator of the file, so a person can open it in Excel, but must save it as `CSV UTF-8` and close it before an Act run that locks sites. |
| `CsvDelimiter` | one of `Culture`, `,`, `;`, `Tab` | `Culture` | no | Scan and Act | Separator of the CSV files the tool writes: `Culture` (the list separator of the current culture, a semicolon for French), `,`, `;` or `Tab`. The tool reads any of them. |
| `CsvDateFormats` | list of texts | `@()` | no | Scan and Act | Extra date formats accepted in the CSV files you provide, for example `dd/MM/yyyy`. ISO 8601 dates are always accepted. The value `Culture` also accepts the date patterns of the current culture. The tool never guesses a format. |

## Scan section

Written inside `Scan = @{ ... }`. Only the Scan phase uses them.

| Setting | Type | Default | Required in | Used by | Description |
|---------|------|---------|-------------|---------|-------------|
| `InactiveDays` | whole number, 1 to 3650 | `365` | no | Scan only | A site is a candidate when its last activity is older than this many days. |
| `LockStates` | list of `ReadOnly`, `Unlock` | `@('ReadOnly')` | no | Scan only | Lock states that the Scan phase lists. With `ReadOnly` alone, the server filters the listing, which is much faster on a large tenant. Add `Unlock` to also look for inactive sites that are not locked (suggested action `Lock`). A site in another lock state is left out of the report and counted in the summary, whether the server filtered the listing or not. |
| `SharePointUsageReport` | file path | (none) | no | Scan only | CSV file of the SharePoint site usage report (Microsoft 365 admin center, Reports, Usage). The Scan phase needs at least one of the three activity reports. |
| `TeamsActivityReport` | file path | (none) | no | Scan only | CSV file of the Microsoft Teams activity report (teams). It shows the activity that the SharePoint report does not see. |
| `GroupsActivityReport` | file path | (none) | no | Scan only | CSV file of the Microsoft 365 groups activity report. |

## Act section

Written inside `Act = @{ ... }`. Only the Act phase uses them.

| Setting | Type | Default | Required in | Used by | Description |
|---------|------|---------|-------------|---------|-------------|
| `InputFile` | file path | (required) | Act only | Act only | The Scan CSV, once a person has filled in its `Decision` column. |
| `Execute` | `$true` or `$false` | `$false` | no | Act only | `$false`: report only, nothing is changed. `$true`: apply the decisions, after the typed confirmation. |
| `MaxActions` | whole number, 1 to 10000 | `25` | no | Act only | Maximum number of actions in one run. |
| `DelaySeconds` | whole number, 0 to 300 | `2` | no | Act only | Pause, in seconds, between two actions. |
| `MaxCsvAgeDays` | whole number, 1 to 365 | `30` | no | Act only | The Scan CSV must not be older than this many days: a site may have changed since. |
| `GrantSiteAdmin` | `$true` or `$false` | `$false` | no | Act only | Before archiving a site, add the signed-in administrator as administrator of the site collection, which the archive needs. Requires `UnlockBeforeArchive`, because a read-only site refuses an owner change. |
| `UnlockBeforeArchive` | `$true` or `$false` | `$false` | no | Act only | Unlock a read-only site before archiving it, and lock it again afterwards. |

## Checks across settings

- The Scan phase needs at least one activity report (`SharePointUsageReport`, `TeamsActivityReport` or `GroupsActivityReport`). Without one, the tool cannot tell which sites are inactive.
- `GrantSiteAdmin` requires `UnlockBeforeArchive`, because a read-only site refuses a change of owners.
- `TenantName` must not be a refused tenant.
