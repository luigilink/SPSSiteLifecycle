# Design decisions

This page records the main decisions behind SPSSiteLifecycle and the facts they rest on. It changes only through a pull request, so that the reasons stay visible.

The measurements come from a Microsoft 365 demonstration tenant of about 10,000 sites. Read them as orders of magnitude, not as guarantees.

| # | Subject | Decision in one line |
|---|---------|----------------------|
| D1 | Name, license, versions | Public, MIT, 0.x pre-releases until a real run is validated |
| D2 | Architecture and settings | One script, one common module, settings in a `.psd1` file |
| D3 | Activity sources | SharePoint, Teams and groups reports (the inactive site policy report later), the most recent date wins |
| D4 | Who decides | A person, in the `Decision` column of the CSV |
| D5 | Unlocked sites | Lock first, direct deletion is off by default |
| D6 | Safeguards of the Act phase | Checks on the whole file, then on each row just before its action |
| D7 | Reading the tenant | Paged, resumable listing, filtered on the server |
| D8 | Input files | Lock-date lists and exclusion lists, in the formats of this tool |
| D9 | Tests and CI | Offline Pester 6 tests, invariant tests, Windows and Linux CI |
| D10 | CSV and Excel | Tolerant reading, Act reads four columns, separator of the culture |
| D11 | Graph and PnP.PowerShell | Graph v1.0 when the operation is available, PnP.PowerShell otherwise |
| D12 | Scope | SharePoint sites only, never OneDrive |

## D1 - Name, license, versions

- **Name:** SPSSiteLifecycle, in the SPS* family. "Lifecycle" because the tool covers the whole path (report, lock, delete or archive), not only deletion.
- **Visibility and license:** public repository, MIT license, so that as many organizations as possible can use it.
- **Versions:** 0.x pre-releases (tags `v0.*` are published as pre-releases). Version 1.0.0 comes only after a real run, limited to one action (`MaxActions = 1`), has been validated on a production tenant.

## D2 - Architecture and settings

- One entry script, `src/SPSSiteLifecycle.ps1`, with two parameters: `-ConfigFile` and `-Phase` (`Scan` or `Act`).
- One common module, `SPSSiteLifecycle.Common`, with `Public/` and `Private/` functions named `<Verb>-SPSLifecycle<Noun>`.
- Settings live in a `.psd1` file, read with `Import-PowerShellDataFile` (data only, no code runs): shared keys at the top level, then a `Scan` section and an `Act` section. The aim is a light script and short command lines.
- `Execute` and `MaxActions` are settings of the `Act` section, not parameters. Defaults: `Execute = $false` and `MaxActions = 25`. The typed confirmation, not the setting, is the barrier before any change: the tool shows a banner (file path, date, age of the CSV, number and type of actions), asks for the tenant name, then for `DELETE n`, `ARCHIVE n` or `APPLY n`, and stops when the input is redirected.
- The file is validated as a whole before anything runs. An unknown key stops the tool (a typo must not disable a safeguard), types are strict (`$true` or `$false` only, the string `'false'` is refused), and relative paths resolve against the folder of the file.
- The schema (key, type, default, check) is a data table in the module. The example file and the Configuration page follow it (see D10).

## D3 - Activity sources

- Sources: the SharePoint site usage report, the Teams activity report and the Microsoft 365 groups activity report. All are optional, and at least one is required. The execution report of the inactive site policy is planned as a fourth source, but it is not read yet: its importer waits for a real export that confirms the column names (see the open points).
- The last activity is the most recent date across the sources that were given. The last content modification date of the site (`LastContentModifiedDate`) only adds caution: it is never a proof of inactivity.
- A site that is absent from every report gets a `REVIEW` verdict.
- Why: the usage report covers SharePoint only, so a team that is active only in Teams would look inactive. The inactive site policy report covers SharePoint, Teams, Exchange and Viva Engage ([Manage inactive sites using inactive site policies](https://learn.microsoft.com/sharepoint/inactive-site-policy)).
- The CSV keeps `LastActivity`, `LastActivitySource` and one column per source.

## D4 - A person decides

- The Scan CSV has a `Decision` column, filled in by a person: `Delete`, `Archive` or `Lock`. An empty cell leaves the site untouched, and any other value stops the tool before the first action. `SuggestedAction` only helps to filter and to fill in the column: `Lock` for an unlocked site, otherwise `Delete` when the size is at most `DeleteMaxSizeGB` (1 GB by default) and `Archive` above it. There is no separate size threshold for archiving, because the person decides.
- A decision never lifts a safeguard: every check of D6 is repeated live.
- There is no automatic rule in 0.x.

## D5 - Unlocked sites

- By default only a read-only site is deleted or archived: `AcceptedLockStates = @('ReadOnly')`. Adding `'Unlock'` allows the direct deletion of an unlocked site. `NoAccess` is never accepted. Only `Lock` accepts an unlocked site.
- Safe path for an unlocked site: `Lock` (the site becomes read-only and the tool writes the date in a local lock journal with the URL, the site ID and the lock date; nothing is written in the tenant), then `Delete` once `MinLockedDays` (365 by default) have passed.
- Lock dates come from lists given by the user (a URL and a date) or from the journal. The "Action taken on" column of the inactive site policy report will be a third source once its importer exists (see D3). The tenant does not return the date a site was locked.
- Why: a read-only site means that a person already made a decision, and it can be unlocked. In the lab, a read-only site refuses a direct deletion (access denied): the tool unlocks it, deletes it, and locks it back if the deletion fails.

## D6 - Safeguards of the Act phase

Two levels.

**The whole file, before any action** (the tool stops):

- a URL outside the configured tenant;
- a refused tenant: the Microsoft corporate tenants (`microsoft` and `microsoftonline`) are refused by the code and cannot be removed, and the `RefusedTenants` setting only adds names to that list. The settings are checked in both phases, so Scan refuses them too;
- a missing mandatory column (`Url`, `SiteId`, `GeneratedOn`, `Decision`);
- an unknown decision;
- a file older than `MaxCsvAgeDays` (30 by default).

**Each row, right before its action** (the row gets a `SKIP-` or `REVIEW-` verdict and the run continues):

- the site still exists, with the same `SiteId` (a URL can be reused);
- its lock state is accepted (D5);
- it is not a channel site, a hub site, the root site, a system site, a home site or a OneDrive site;
- for an archive, its template is one that Microsoft 365 Archive supports (`SKIP-NOT-ARCHIVABLE`). The list is a table in the module, taken from [Manage Microsoft 365 Archive](https://learn.microsoft.com/microsoft-365/archive/archive-manage#site-templates-supported). A template that Microsoft adds later is refused until the table is updated;
- its Microsoft 365 group, if any, is active (a group state that was not read counts as not active);
- its content was not modified since `GeneratedOn`;
- no retention policy or hold is known (best effort: the tool cannot see every Microsoft Purview policy);
- for a deletion, its size is known and not above `DeleteMaxSizeGB` (1 GB by default). A size that is missing, blank, negative or not a number is unknown, never zero.

Always on: report only by default, double typed confirmation, `MaxActions`, a stop after 3 consecutive errors (not configurable), and explicit verdicts. A rule of the code runs through all of them: an input that is missing or cannot be read never leads to an action, it leads to a `SKIP-` or `REVIEW-` verdict, or it stops the tool.

## D7 - Reading the tenant (Scan)

- The activity comes from the reports. The live state (lock state, group, template, size, archive status) comes from a paged listing of the tenant through the SharePoint admin API, about 1,500 sites per page, filtered on the server by lock state when a single state is requested. There is one checkpoint per page, an automatic resume and a progress display. Reports and listing are joined by site ID.
- There is no targeted mode (reading only the sites of a list) in 0.x.
- Measurements (10,030 sites, 9 of them read-only):

| Read | Time |
|------|------|
| `Get-PnPTenantSite -Detailed`, whole tenant | 36 s |
| same cmdlet, server filter on `ReadOnly` | 8.7 s (the same 9 sites as a client-side filter) |
| paged listing | 2.3 to 2.8 s per page of 1,500 sites, resumable |
| one site by URL | 0.92 s one by one, 0.31 s in batches of 100 |

- Reading a site by its site ID was refused in the lab (access denied). The usage report can have an empty `Site URL` (concealed names, BYOK, Customer Lockbox), and it has neither the lock state nor the group: it cannot replace the listing.

## D8 - Input files

SPSSiteLifecycle is a new tool. It does not read the files of any earlier script: its input formats are its own. All inputs are plain CSV files that follow the rules of D10.

- **Lock date lists** (`LockDateFiles`): a `Url` column, a `LockedOn` column and an optional `SiteId` column. When a site appears in several lists or in the lock journal (D5), the latest date is kept: a later lock date can only delay a deletion.
- **Exclusion lists** (`ExclusionFiles`): a `Url` column. A listed site gets `SKIP-EXCLUDED` in Scan, and Act checks the lists again, because a decision never lifts a safeguard (D4).
- No saved inventory is read. The paged listing keeps its own checkpoint files to resume an interrupted Scan (D7), and the Scan CSV is the reviewed list that Act reads.

## D9 - Tests and CI

- Pester 6, pinned to 6.x, with the syntax that Pester 5 and 6 share.
- Offline by construction: the module loads without PnP.PowerShell or Microsoft Graph. Only the adapter functions (D11) call them, and a structure test checks it by analyzing the code. The tests simulate the adapters.
- Invariant tests check every safeguard: report only by default, double confirmation, redirected input stops the tool, `MaxActions`, the stop after 3 errors, the live re-check before each action, protected sites and OneDrive never touched, refused tenant, and an unknown decision or an old CSV stopping the tool before the first action.
- The fixtures are made up (contoso, fictitious GUIDs). The lab cases are a table without identifiers.
- Date, number and CSV functions are tested under en-US, fr-FR and de-DE.
- CI runs on pull requests to `main`: Windows and Linux with PowerShell 7, and PSScriptAnalyzer on `src` and `tools`. There is no Windows PowerShell 5.1 job, because PnP.PowerShell 3.x requires PowerShell 7.4.
- The lab scripts live in `tools/lab` (create test sites, run the tool, compare verdicts). They are generic: `TenantName` and `ClientId` are mandatory with no default, they only simulate by default, the Microsoft corporate tenant is refused, and CI never runs them.

## D10 - CSV and Excel

- **Reading is tolerant.** The separator is detected (comma, semicolon or tab, and a first line `sep=` is skipped). UTF-8 with or without a BOM is read, with a fallback to Windows-1252 (the first CSV format that French Excel offers). Dates are read in ISO 8601 (`2026-10-28`, `2026-10-28T16:30:00Z`, or the compact `20261028T163000Z`) or in the formats listed in `CsvDateFormats`, for example `dd/MM/yyyy`; the value `Culture` in that list accepts the date patterns of the current culture. The tool never guesses otherwise, because a day and a month swapped in a lock date could silently change whether a site is eligible. An unreadable date stops the tool and names the row, the column and the setting to use. Empty rows added by Excel are ignored, a duplicate `Url` or `SiteId` stops the tool, and a file still open in Excel gives a clear message.
- **Act reads four columns only:** `Url`, `SiteId`, `GeneratedOn` and `Decision`. Everything else is read again from its source or live, so what Excel changes (dates, `VRAI` and `FAUX`, decimal commas) cannot alter an action.
- **Writing:** UTF-8 with a BOM and the separator of the current culture (a semicolon for French) unless `CsvDelimiter` says otherwise. Sizes are whole megabytes (`StorageUsedMB`) and dates are ISO. `GeneratedOn` is written in the compact form `20261028T163000Z` (UTC), which is meant to survive a round trip through a spreadsheet unchanged. `Title` is neutralized against formula injection ([CWE-1236](https://cwe.mitre.org/data/definitions/1236.html)) and is never read by Act. There are no owners, because they are personal data.
- **Columns:** `Url`, `Verdict`, `SuggestedAction` and `Decision` first, then `SiteId`, `Title`, `Template`, `GroupId`, `IsTeamsConnected`, `LockState`, `ArchiveStatus`, `StorageUsedMB`, `LastActivity`, `LastActivitySource`, `InactiveDays`, `SharePointActivity`, `TeamsActivity`, `GroupActivity`, `ContentModified`, `LockedOn`, `LockedOnSource` and `GeneratedOn`.
- **Documentation** is written in English with Microsoft Learn references only. The Configuration and Verdicts pages are generated from the settings schema and the verdict table. A test fails when a generated page differs from the committed file, so a key without documentation turns CI red.

## D11 - Graph and PnP.PowerShell

- Microsoft Graph v1.0 is used when the operation exists there as a generally available API. PnP.PowerShell (the SharePoint admin API) is used otherwise. Beta APIs are not used in production.
- Each operation has one private adapter function (usage report, site state, lock, site deletion, archive, group state, group deletion). When Graph covers an operation, only its adapter changes, and the tests do not.
- Coverage on 28 October 2026, from the Microsoft Graph metadata and Microsoft Learn:

| Operation | Graph v1.0 | Graph beta |
|-----------|------------|------------|
| Usage reports, group state, deleting the group of a group-connected site | yes | yes |
| List sites with lock state, template and size | no ([`getAllSites`](https://learn.microsoft.com/graph/api/site-getallsites?view=graph-rest-1.0) is application-only and has none of these) | the lock state and template properties exist |
| Lock or unlock a site | no | not documented |
| Delete a site that has no group | no | not documented |
| Archive a site | reads the archive status only | [`archive` and `unarchive`](https://learn.microsoft.com/graph/api/site-archive?view=graph-rest-beta) actions |

Microsoft states that beta APIs are not supported in production applications.

## D12 - Scope

SharePoint sites only. OneDrive sites are never listed for action and never touched, and there is no option to include them. Scan leaves them out and counts them in its summary. Act refuses any OneDrive row (`SKIP-ONEDRIVE`).

## Open points

- Does the last activity date of the Teams and groups reports depend on the chosen report period? If it does, these reports cannot prove more than 180 days of silence.
- What exactly does the `HasHolds` site property (PnP.PowerShell 3.4.1 and later) report? The retention check of D6 depends on it.
- Does locking or unlocking a site change its last content modification date? A site that the tool locked must not look active because of it.
- Does `GeneratedOn` survive a round trip through a spreadsheet (open the CSV, fill in `Decision`, save as CSV) unchanged, in French Excel in particular? The compact form is meant to, but it has not been tried yet.
- Do the column names of the inactive site policy report, as exported, match the names documented on Microsoft Learn? Its importer, and the `PolicyActivity` column of the CSV, are written only after a real export has been checked (the header line is enough).
- Sign-in is interactive in 0.x (PnP.PowerShell with a `ClientId`). Certificate-based sign-in, for a Scan that runs unattended, is not decided yet.
