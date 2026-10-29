# Verdicts

> This page is generated from the verdict catalog of the module. Do not edit it by hand: change the catalog, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.

Every site gets one verdict, in the `Verdict` column of the CSV and in the summary. The gates are checked in the order of the table below, and the first one that matches decides.

- **`SKIP-`**: the tool leaves the site alone, whatever the decision. A decision never lifts a safeguard.
- **`REVIEW-`**: a person has to look. The tool does nothing to the site.
- **An action** (`LOCK`, `ARCHIVE`, `DELETE-SITE`, `DELETE-VIA-GROUP`): what the Scan phase suggests, and what the Act phase does after the typed confirmation, when `Execute` is `$true`.

## All verdicts

| Verdict | Kind | Phase | Meaning |
|---------|------|-------|---------|
| `SKIP-ONEDRIVE` | Skip | Scan and Act | A OneDrive site, or a site whose address cannot be read as a plain web address (nothing can say what it is). The tool never touches them: Scan leaves these sites out and counts them, Act refuses the row. |
| `SKIP-CHANNEL-SITE` | Skip | Scan and Act | A private or shared channel site. It goes with its channel and is never handled alone. |
| `SKIP-PROTECTED` | Skip | Scan and Act | The root site, a hub site, the home site, or a system site (by its template or its path). |
| `SKIP-ALREADY-ARCHIVED` | Skip | Scan and Act | The site is archived, or an archive or a reactivation is in progress. |
| `SKIP-LOCK-STATE` | Skip | Scan and Act | The lock state is not accepted for this action (`AcceptedLockStates`; `Lock` only accepts an unlocked site; `NoAccess` is never accepted). |
| `SKIP-EXCLUDED` | Skip | Scan and Act | The site is in an exclusion file. Act checks the files again, because a decision never lifts a safeguard. |
| `SKIP-NO-LOCK-DATE` | Skip | Scan and Act | A read-only site with no known lock date, so its age cannot be proven. Add it to a lock date file. |
| `SKIP-TOO-RECENT-LOCK` | Skip | Scan and Act | The site was locked less than `MinLockedDays` ago. |
| `REVIEW-NO-ACTIVITY-ROW` | Review | Scan only | The site is in none of the activity reports you gave, so nothing says whether it is active. |
| `SKIP-RECENT-ACTIVITY` | Skip | Scan only | The last activity, or the last content change, is more recent than `InactiveDays`. |
| `REVIEW-NO-SIZE` | Review | Scan and Act | The size of the site is unknown (missing, blank, negative or not a number), and the verdict depends on it. |
| `REVIEW-GROUP-SOFTDELETED` | Review | Act only | The Microsoft 365 group of the site is in the Microsoft Entra recycle bin. Restore it or delete it for good first. |
| `REVIEW-GROUP-NOTFOUND` | Review | Act only | The group of the site cannot be confirmed active: its ID points to nothing (a group deleted for good, an orphan site), or its state was not read. |
| `SKIP-NOT-ARCHIVABLE` | Skip | Scan and Act | An archive is wanted (or is the only option, because the site is too large to delete), but Microsoft 365 Archive does not support the template of the site. |
| `SKIP-TOO-LARGE-TO-DELETE` | Skip | Scan and Act | The site is larger than `DeleteMaxSizeGB`: it is never deleted. |
| `LOCK` | Action | Scan and Act | Make the site read-only. The tool records the date in the lock journal. |
| `ARCHIVE` | Action | Scan and Act | Archive the site with Microsoft 365 Archive. |
| `DELETE-SITE` | Action | Scan and Act | The site has no Microsoft 365 group: delete the site (an unlock comes first, and the site is locked again if the deletion fails). |
| `DELETE-VIA-GROUP` | Action | Scan and Act | The site belongs to a Microsoft 365 group: delete the group, which deletes the site some time later (from minutes to hours). |
| `SKIP-NOT-FOUND` | Skip | Act only | The site no longer exists in the tenant. |
| `SKIP-SITEID-MISMATCH` | Skip | Act only | The URL exists, but with another site ID than in the CSV: the URL was reused by a new site. |
| `REVIEW-CONTENT-MODIFIED` | Review | Act only | The content of the site changed after the CSV was generated. |
| `REVIEW-RETENTION` | Review | Act only | A retention policy or a hold is known for the site (best effort: the tool cannot see every Microsoft Purview policy). |

## System sites that are never touched

A site with one of these templates or paths gets `SKIP-PROTECTED`. The lists follow [Manage sites in the SharePoint admin center](https://learn.microsoft.com/sharepoint/manage-sites-in-new-admin-center), plus a few sites that would break a service if they were deleted. The root site, hub sites and the home site are protected as well.

| Template | Site |
|----------|------|
| `APPCATALOG#*` | App catalog site |
| `CENTRALADMIN#*` | Central admin site |
| `CSPCONTAINER#*` | CSP container (SharePoint Embedded) |
| `EDISC#*` | eDiscovery center |
| `FunSite#*` | SharePoint tenant fundamental site |
| `POINTPUBLISHING*` | PointPublishing hub, personal blog and topic sites |
| `POLICYCTR#*` | Compliance policy center |
| `REDIRECTSITE#*` | Redirect site |
| `REVIEWCTR#*` | Review center |
| `SPSMSITEHOST#*` | My Site host |
| `SRCHCEN#*` | Search center |
| `TENANTADMIN#*` | Tenant admin site |
| `TestSite#*` | Test site |

| Path | Site |
|------|------|
| `/sites/contenttypehub` | Content type hub: holds the content types shared by the whole tenant |
| `/sites/compliancepolicycenter` | Compliance policy center |
| `/portal/hub` | PointPublishing hub |
| `/search` | Search site |

OneDrive sites (`SPSPERS#*`, or the OneDrive host of the tenant) get `SKIP-ONEDRIVE`, and so does a site whose address cannot be read as a plain web address (an address that does not parse, another scheme than http and https, a host that DNS changes or refuses), because nothing can say what it is. Teams channel sites (`TEAMCHANNEL#*`) get `SKIP-CHANNEL-SITE`.

## Templates that Microsoft 365 Archive supports

Only these templates can get the `ARCHIVE` verdict. The table follows [Manage Microsoft 365 Archive](https://learn.microsoft.com/microsoft-365/archive/archive-manage#site-templates-supported). A template that Microsoft adds later is refused (`SKIP-NOT-ARCHIVABLE`) until the table of the module is updated.

| Template | Site |
|----------|------|
| `STS#0` | Team site (classic experience) |
| `STS#1` | Blank site |
| `STS#2` | Document workspace |
| `STS#3` | Team site |
| `SITEPAGEPUBLISHING#0` | Communication site |
| `GROUP#0` | Microsoft 365 group-connected team site |
| `SPSNEWS#0` | News site |
| `SPSNHOME#0` | News site |
| `WIKI#0` | Wiki site |
| `ENTERWIKI#0` | Enterprise wiki |
| `BDR#0` | Document center |
| `OFFILE#0` | Records center |
| `OFFILE#1` | Records center |
