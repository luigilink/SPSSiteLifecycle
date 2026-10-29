function Get-SPSLifecycleEarliestLockDate {
    <#
        .SYNOPSIS
        Gives the earliest date that the tool accepts as the date of a lock: 2000-01-01, in UTC.

        .DESCRIPTION
        SharePoint Online did not exist before 2000, so no site was locked before. A date earlier than that is what a
        spreadsheet writes for a blank cell (1900-01-01, 1899-12-30, 1970-01-01) or what a program writes for no date
        at all (0001-01-01), and a site whose date is read as a century old looks as if it had been locked for ever and
        passes any MinLockedDays: the error whose direction is dangerous.

        The reader of the lists and of the lock journal (Import-SPSLifecycleLockDateList) refuses a date before it, and
        the function that adds to the journal (Add-SPSLifecycleLockJournalEntry) refuses it too, so that the tool never
        writes a journal that it would then refuse to read. A date in the future only delays a deletion, and is accepted.

        .EXAMPLE
        Get-SPSLifecycleEarliestLockDate
    #>
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param ()

    [System.DateTime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
}
