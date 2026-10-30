# Getting Started

## Prerequisites

* **PowerShell 7.4 or later.** PnP.PowerShell 3.x does not run on Windows PowerShell 5.1.
* **PnP.PowerShell 3.x**, installed with `Install-Module -Name PnP.PowerShell -Scope CurrentUser`.
* **An Entra ID app registration** for the interactive sign-in. PnP.PowerShell has required your own application since 9 September 2024: see [Register an Entra ID application to use with PnP PowerShell](https://pnp.github.io/powershell/articles/registerapplication.html). The tool asks for its client ID.
* **Roles on the tenant:** SharePoint Administrator to read and act on the sites, and Groups Administrator to delete Microsoft 365 groups.
* **Microsoft Graph delegated permissions of the app:** `Group.Read.All` is enough for a report-only run, `Group.ReadWrite.All` is needed to delete groups.
* **Archiving only:** Microsoft 365 Archive turned on (pay-as-you-go billing) and a site collection admin role on each site to archive.

## Before the first run

* Use a non-production tenant first.
* Check the retention settings of the tenant: a deleted site or group can be restored only while the retention lasts.
* Run the report phase, read the CSV, then start with a single action (`MaxActions = 1`).

## Run the Scan

1. Copy `src/config/SPSSiteLifecycle.example.psd1`, and fill in `TenantName`, `ClientId` and at least one activity report under `Scan` (the SharePoint site usage report, the Teams activity report or the Microsoft 365 groups activity report, exported as CSV from the Microsoft 365 admin center). Everything else has a default, and every setting is explained on the [Configuration](./Configuration) page.
2. Run it:

   ```powershell
   pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan
   ```

3. The settings and the files are checked first: a problem stops the run before the sign-in window opens. Then the window opens (sign in with a SharePoint administrator account), the home site and the sites are listed page by page (an interrupted listing is taken up the next time you run it), and the report is written in `OutputFolder`: `sites-<time of the run>.csv`.
4. The run ends with a few lines: how long it took, how the sites were listed, how many are in the report and how many were left out, what the report suggests, the verdicts by count, and the path of the report. `-InformationAction SilentlyContinue` hides them.
5. Open the report in a spreadsheet and read it. `Decision` is empty on every row: the tool never decides in your place.

The Scan only reads: nothing is changed in the tenant, and a run that stops half-way leaves no report. The exit code is `0` when the run ended and `1` on any error, after a message that says what stopped it.

## Between the two phases

The tool never decides in your place. Open the report (`sites-<time>.csv`) in a spreadsheet, filter it (the `Verdict` and `SuggestedAction` columns help), write `Delete`, `Archive` or `Lock` in the `Decision` column of the sites that you want to act on, and save the file as CSV (UTF-8 or the CSV that your Excel saves: the semicolon of a French Excel is read). An empty `Decision` leaves the site untouched, and any other word stops the tool before the first action. Put the path of the file in `Act.InputFile` of the settings. The file must not be older than `Act.MaxCsvAgeDays` (30 days by default): a site can change in the meantime, and the tool reads each site again anyway.

## Run the Act

1. **Report only first** (the default: `Act.Execute` is not set). Run it:

   ```powershell
   pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Act
   ```

   The tool checks the whole file before it signs in, shows a banner (the file, its date, the decisions), reads each decided site again from the tenant and says what it would do. Nothing is changed and nothing is asked. It writes `act-<time>.csv` in `OutputFolder`: a row for each decision, with the verdict (a site that is protected, excluded, locked for less than `MinLockedDays`, whose content changed or that has a hold is left alone), and the outcome.
2. **Then one action.** Put `Execute = $true` and `MaxActions = 1` in the `Act` section, and run it again. The tool shows the banner, asks you to type the name of the tenant, then a phrase that carries the number of actions (`DELETE 1`, `ARCHIVE 1` or `APPLY 1`), and only then signs in and does the first action that passes every check. Check the result in the tenant, then raise `MaxActions` (25 by default). The tool stops when its input is redirected: the confirmation is typed by a person.
3. **What a deletion does.** A site that has a Microsoft 365 group is deleted through its group (SharePoint deletes the site some time later, from minutes to hours: a later run sees the group in the recycle bin and does not delete it twice). A site that has none is unlocked, read again, and deleted into the recycle bin (it can be restored while the retention lasts), and locked again if that fails. `Archive` needs Microsoft 365 Archive to be on for sites, and `Lock` writes the date in the lock journal, which a later run reads as the age of the lock.
4. **The exit code** is `0` when the run ended as planned, `1` on an error, and `2` when the run ended but a row failed or could not be read, or when it stopped after 3 errors in a row (the run stops by itself, and the Act report says which rows).

Start with a non-production tenant, and read the Design Decisions page (D6) for every check that is made before an action.
