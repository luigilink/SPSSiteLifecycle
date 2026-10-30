function Get-SPSLifecycleVerdictCatalog {
    <#
        .SYNOPSIS
        Returns the table of every verdict, in the order the gates are checked.

        .DESCRIPTION
        This table is the single source of truth for the verdicts: tools/Update-Documentation.ps1
        reads it to write the Verdicts page, and a test checks that every verdict returned by
        Get-SPSLifecycleVerdict is in it.

        Each row has: Verdict, Kind (Action, Skip or Review), Phases (Scan and Act, or one of them)
        and Meaning. An Action verdict is what the tool suggests (Scan) or does (Act). A Skip verdict
        leaves the site alone, whatever the decision. A Review verdict needs a person to look.

        .EXAMPLE
        Get-SPSLifecycleVerdictCatalog | Where-Object { $_.Kind -eq 'Review' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    $both = @('Scan', 'Act')
    $rows = @(
        , @('SKIP-ONEDRIVE', 'Skip', $both, 'A OneDrive site, or a site whose address is not in the form that SharePoint gives (https, a host that DNS reads as it is written, no other port than the default one): nothing can say what it is. The tool never touches them: Scan leaves these sites out and counts them, Act refuses the row.')
        , @('SKIP-CHANNEL-SITE', 'Skip', $both, 'A private or shared channel site. It goes with its channel and is never handled alone.')
        , @('SKIP-PROTECTED', 'Skip', $both, 'The root site, a hub site, the home site, or a system site (by its template or its path).')
        , @('SKIP-ALREADY-ARCHIVED', 'Skip', $both, 'The site is archived, or an archive or a reactivation is in progress.')
        , @('SKIP-LOCK-STATE', 'Skip', $both, 'The lock state is not accepted for this action (`AcceptedLockStates`; `Lock` only accepts an unlocked site; `NoAccess` is never accepted).')
        , @('SKIP-EXCLUDED', 'Skip', $both, 'The site is in an exclusion file. Act checks the files again, because a decision never lifts a safeguard.')
        , @('SKIP-NO-LOCK-DATE', 'Skip', $both, 'A read-only site with no known lock date, so its age cannot be proven. Add it to a lock date file.')
        , @('SKIP-TOO-RECENT-LOCK', 'Skip', $both, 'The site was locked less than `MinLockedDays` ago.')
        , @('REVIEW-NO-ACTIVITY-ROW', 'Review', @('Scan'), 'The site is in none of the activity reports you gave, so nothing says whether it is active.')
        , @('SKIP-RECENT-ACTIVITY', 'Skip', @('Scan'), 'The last activity, or the last content change, is more recent than `InactiveDays`.')
        , @('REVIEW-NO-SIZE', 'Review', $both, 'The size of the site is unknown (missing, blank, negative or not a number), and the verdict depends on it.')
        , @('REVIEW-GROUP-SOFTDELETED', 'Review', @('Act'), 'The Microsoft 365 group of the site is in the Microsoft Entra recycle bin. Restore it or delete it for good first.')
        , @('REVIEW-GROUP-NOTFOUND', 'Review', @('Act'), 'The group of the site cannot be confirmed active: its ID points to nothing (a group deleted for good, an orphan site), or its state was not read.')
        , @('SKIP-NOT-ARCHIVABLE', 'Skip', $both, 'An archive is wanted (or is the only option, because the site is too large to delete), but Microsoft 365 Archive does not support the template of the site.')
        , @('SKIP-TOO-LARGE-TO-DELETE', 'Skip', $both, 'The site is larger than `DeleteMaxSizeGB`: it is never deleted.')
        , @('LOCK', 'Action', $both, 'Make the site read-only. The tool records the date in the lock journal.')
        , @('ARCHIVE', 'Action', $both, 'Archive the site with Microsoft 365 Archive.')
        , @('DELETE-SITE', 'Action', $both, 'The site has no Microsoft 365 group: delete the site (an unlock comes first, and the site is locked again if the deletion fails).')
        , @('DELETE-VIA-GROUP', 'Action', $both, 'The site belongs to a Microsoft 365 group: delete the group, which deletes the site some time later (from minutes to hours).')
        , @('SKIP-NOT-FOUND', 'Skip', @('Act'), 'The site no longer exists in the tenant.')
        , @('SKIP-SITEID-MISMATCH', 'Skip', @('Act'), 'The URL exists, but with another site ID than in the CSV: the URL was reused by a new site.')
        , @('REVIEW-CONTENT-MODIFIED', 'Review', @('Act'), 'The content of the site changed after the CSV was generated, or the tenant gives no date for it, so a change cannot be ruled out.')
        , @('REVIEW-RETENTION', 'Review', @('Act'), 'The tenant reports a hold on the site (`HasHolds`). Best effort: a retention policy that the site does not report is not seen, because the tool cannot see every Microsoft Purview policy.')
    )

    foreach ($row in $rows) {
        [PSCustomObject]@{
            Verdict = $row[0]
            Kind    = $row[1]
            Phases  = @($row[2])
            Meaning = $row[3]
        }
    }
}
