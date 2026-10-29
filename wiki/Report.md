# Report

> This page is generated from the table of the report columns of the module. Do not edit it by hand: change the table, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.

The Scan phase writes one CSV file, `sites-<time of the run>.csv`, in `OutputFolder`. A person reviews it in a spreadsheet and fills in the `Decision` column. The Act phase reads it.

## How the file is written

- UTF-8 with a byte order mark, so that Excel reads the accents. Windows line endings.
- The separator comes from the `CsvDelimiter` setting (a semicolon for French by default). The tool reads a comma, a semicolon or a tab.
- Sizes are whole megabytes and dates are ISO 8601 in UTC, whatever the culture of the machine. The time of the run is written in the compact form `20261028T163000Z`, which is meant to survive a round trip through a spreadsheet unchanged.
- A size that is unknown stays empty. It is never written as 0.
- Texts that come from the tenant, the title of a site above all, are neutralized against formula injection ([CWE-1236](https://cwe.mitre.org/data/definitions/1236.html)): a text that starts with `=`, `+`, `-`, `@`, a tab or a carriage return gets a leading apostrophe, so that a spreadsheet shows it and does not run it.
- There is no column for the owners of a site, because they are personal data.
- `Decision` is always written empty. The tool never decides in the place of a person.
- An existing file is never overwritten. It is a reviewed document.
- The report is written to a partial file (`.partial`) that takes the name of the report only when it is complete. A run that stops half-way (a record that cannot be written, a full disk, Ctrl+C) never leaves a report that looks complete.

## Columns

The Act phase reads four columns only: `Url`, `SiteId`, `GeneratedOn` and `Decision`. Everything else is read again from its source or live, so what a spreadsheet changes (dates, `VRAI` and `FAUX`, decimal commas) cannot alter an action.

| # | Column | Kind | Read by Act | Meaning |
|---|--------|------|-------------|---------|
| 1 | `Url` | text | yes | The address of the site. |
| 2 | `Verdict` | text | no | What the tool concluded: an action, a SKIP- or a REVIEW- verdict (see the Verdicts page). |
| 3 | `SuggestedAction` | text | no | What the tool suggests: Delete, Archive or Lock. It only helps to filter and to fill in Decision. |
| 4 | `Decision` | empty, filled in by a person | yes | Filled in by a person: Delete, Archive or Lock. Empty leaves the site untouched. |
| 5 | `SiteId` | GUID | yes | The ID of the site. The Act phase checks that the address still belongs to this site. |
| 6 | `Title` | text | no | The title of the site. Never read by the Act phase. |
| 7 | `Template` | text | no | The template of the site, for example GROUP#0. |
| 8 | `GroupId` | GUID | no | The ID of the Microsoft 365 group of the site, empty when it has none. |
| 9 | `IsTeamsConnected` | `True` or `False` | no | True when the site belongs to a team. |
| 10 | `LockState` | text | no | The lock state: Unlock, ReadOnly or NoAccess. |
| 11 | `ArchiveStatus` | text | no | The archive status of the site. |
| 12 | `StorageUsedMB` | whole number | no | The storage in use, in whole megabytes. |
| 13 | `LastActivity` | date, ISO 8601, UTC | no | The most recent activity over the reports that were given. |
| 14 | `LastActivitySource` | text | no | The report that gave LastActivity. |
| 15 | `InactiveDays` | whole number | no | The days between LastActivity and the time of the run. |
| 16 | `SharePointActivity` | date, ISO 8601, UTC | no | The last activity in the SharePoint site usage report. |
| 17 | `TeamsActivity` | date, ISO 8601, UTC | no | The last activity in the Teams activity report. |
| 18 | `GroupActivity` | date, ISO 8601, UTC | no | The last activity in the Microsoft 365 groups activity report. |
| 19 | `ContentModified` | date, ISO 8601, UTC | no | The last modification of the content, as the tenant reports it. |
| 20 | `LockedOn` | date, ISO 8601, UTC | no | The date the site was locked, when it is known. |
| 21 | `LockedOnSource` | text | no | Where LockedOn comes from: a lock date list or the lock journal. |
| 22 | `GeneratedOn` | time of the run, `20261028T163000Z` | yes | The time of the run, in UTC. The Act phase refuses a file that is too old. |
