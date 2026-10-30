# SPSSiteLifecycle

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
[![SPSSiteLifecycle CI Pester Tests](https://github.com/luigilink/SPSSiteLifecycle/actions/workflows/pester.yml/badge.svg)](https://github.com/luigilink/SPSSiteLifecycle/actions/workflows/pester.yml)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![PnP.PowerShell](https://img.shields.io/badge/PnP.PowerShell-3.x-0078D4)](https://www.powershellgallery.com/packages/PnP.PowerShell)

**SPSSiteLifecycle** is a PowerShell tool that finds inactive or read-only **SharePoint Online** sites, then deletes or archives the ones you have reviewed. It works in two phases, so that a person reads a CSV file between the analysis and the action.

> **Pre-release, under construction.** There is no release yet. The tool is being built in 0.x versions. Until a real run has been validated on a production tenant, use it on a non-production tenant only.

## Why

The inactive site policy of Microsoft 365 can make inactive sites read-only, then archive them; deleting them stays up to you. On a large tenant, that deletion has to be planned, reviewed and repeated safely. SPSSiteLifecycle is built for that: one reviewable CSV, then actions taken from that file only after each site has been checked again live.

## How it works

1. **Report (read-only).** Finds the sites that have been inactive, or read-only, for longer than a threshold you set, and writes a CSV: one line per site, with its lock state, size, last activity and a suggested action. Nothing is changed in the tenant.
2. **Act (after review).** Reads the CSV once you have reviewed it, checks each site again live (its lock state and its Microsoft 365 group, at least), then deletes or archives it. A site connected to a Microsoft 365 group is deleted through its group (a connected Team goes with it); the other sites are deleted directly. Archiving (Microsoft 365 Archive) keeps the content in cold storage instead.

## Safeguards

- **Report only by default.** The Scan phase never changes anything, and the Act phase only simulates until `Execute = $true` is set in the `Act` section of the settings file.
- **Double confirmation.** With `Execute = $true`, the tool shows a summary, asks for the tenant name, then for a phrase that carries the number of actions (`DELETE n`, `ARCHIVE n` or `APPLY n`). It stops if the input is redirected.
- **Capped runs.** `MaxActions` limits the number of actions of a run (25 by default).
- **Stops on repeated errors.** A run stops after 3 consecutive errors.
- **Live re-check.** Each site is read again from the tenant right before every action.
- **Protected sites.** A channel site, a hub site, the root site and a system site are never deleted or archived.
- **Explicit verdicts.** Every site gets a verdict: an action, a `SKIP-...` (nothing to do, with the reason) or a `REVIEW-...` (a person must look at it).

## Requirements

- **PowerShell 7.4 or later** (PnP.PowerShell 3.x does not run on Windows PowerShell 5.1).
- **PnP.PowerShell 3.x.**
- **An Entra ID app registration** for the interactive sign-in, as PnP.PowerShell requires your own app: see [Register an Entra ID application to use with PnP PowerShell](https://pnp.github.io/powershell/articles/registerapplication.html).
- **SharePoint Administrator** on the tenant, plus **Groups Administrator** to delete Microsoft 365 groups. Archiving also needs Microsoft 365 Archive turned on (pay-as-you-go billing) and a site collection admin role on each archived site.

## Usage

```powershell
# Phase 1: read the tenant and write the report (nothing is changed)
pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan
```

The script has two parameters. Everything else is a setting in the `.psd1` file (see `src/config/SPSSiteLifecycle.example.psd1`). The Act phase (`-Phase Act`) is not available in this version. See [Getting Started](https://github.com/luigilink/SPSSiteLifecycle/wiki/Getting-Started).

## Quick links

- 📖 [Documentation (Wiki)](https://github.com/luigilink/SPSSiteLifecycle/wiki)
- 🚀 [Getting Started](https://github.com/luigilink/SPSSiteLifecycle/wiki/Getting-Started)
- 📝 [Changelog](CHANGELOG.md)
- 🔒 [Security policy](SECURITY.md)
- 🤝 [Contributing](.github/CONTRIBUTING.md)

## Disclaimer

SPSSiteLifecycle deletes SharePoint sites and Microsoft 365 groups. It is provided as is, without warranty (see [LICENSE](LICENSE)). A deleted site can be restored from the recycle bin only while the retention lasts: check the retention settings of your tenant first, run the report, then start with a single action (`MaxActions = 1`).

## Code of conduct

This project adopts the [Contributor Covenant](CODE_OF_CONDUCT.md).
