# SPSSiteLifecycle

SPSSiteLifecycle is a PowerShell tool (PnP.PowerShell) that finds inactive or read-only SharePoint Online sites, then deletes or archives the ones you have reviewed. It works in two phases: a read-only report that writes a CSV, then an action phase that works from that file.

> **Pre-release, under construction.** There is no release yet. Until a real run has been validated on a production tenant, use the tool on a non-production tenant only.

## Safeguards

* **Report only by default:** the Scan phase never changes anything, and the Act phase only simulates until `Execute = $true` is set in the `Act` section of the settings file.
* **Double confirmation:** with `Execute = $true`, the tool shows a summary, asks for the tenant name, then for a phrase that carries the number of actions (`DELETE n`, `ARCHIVE n` or `APPLY n`). It stops if the input is redirected.
* **Capped runs:** `MaxActions` limits the number of actions of a run (25 by default).
* **Stops on repeated errors:** a run stops after 3 consecutive errors.
* **Live re-check:** each site is read again from the tenant right before every action.
* **Protected sites:** a channel site, a hub site, the root site and a system site are never deleted or archived.
* **Explicit verdicts:** every site gets a verdict, an action, a `SKIP-...` (nothing to do, with the reason) or a `REVIEW-...` (a person must look at it).

## Pages

* [Getting Started](./Getting-Started)
* [Configuration](./Configuration)
* [Verdicts](./Verdicts)
* [Report](./Report)
* [Design decisions](./Design-Decisions)
* [Release process](./Release-Process)
