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

The Scan only reads: nothing is changed in the tenant, and a run that stops half-way leaves no report. The exit code is `0` when the run ended and `1` on any error, after a message that says what stopped it. `-Phase Act` is not available in this version.
