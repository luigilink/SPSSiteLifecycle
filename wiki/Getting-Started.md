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
