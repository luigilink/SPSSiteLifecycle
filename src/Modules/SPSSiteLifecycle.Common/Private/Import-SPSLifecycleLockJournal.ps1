function Import-SPSLifecycleLockJournal {
    <#
        .SYNOPSIS
        Reads the lock journal: the file where the Act phase records each site that it locks.

        .DESCRIPTION
        The journal has the format of a list of lock dates (a Url column, a SiteId column and a LockedOn
        column), and it is read with the separator that Excel may have changed and the date formats of
        CsvDateFormats, but not with the tolerance of the lists that a person provides: it must be UTF-8 (see
        Read-SPSLifecycleStrictCsv). The tenant does not give the date a site was locked, and the journal is how
        the tool remembers it.

        A journal that does not exist yet, or that has no byte at all, is an empty one: no site was locked
        by the tool, and a site without a lock date is never deleted. A file that exists but that cannot be
        read as a journal stops the tool, because a lock date that is lost could make a recent lock look old.
        The journal is the tool's own file, so it is read strictly: a row without a date, with a site ID that is
        not a GUID or with no site at all, and a quote that is never closed, stop the tool and name the row,
        where a list that a person provides would ignore the row (see Import-SPSLifecycleLockDateList).

        Returns the same object as Import-SPSLifecycleLockDateList (Name, RowCount, Entries), with Found:
        $false when the file does not exist.

        .PARAMETER Path
        Path of the journal. A relative path is relative to the location of the PowerShell session.

        .PARAMETER DateFormat
        Extra date formats from the CsvDateFormats setting.

        .EXAMPLE
        Import-SPSLifecycleLockJournal -Path .\Reports\lock-journal.csv
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $DateFormat = @()
    )

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path $Path
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        throw "The lock journal '$fullPath' is a folder, not a CSV file."
    }

    $name = Split-Path -Path $fullPath -Leaf
    $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
    if (-not $exists -or [System.IO.FileInfo]::new($fullPath).Length -eq 0) {
        return [PSCustomObject]@{
            Name     = $name
            RowCount = 0
            Entries  = @()
            Found    = $exists
        }
    }

    $list = Import-SPSLifecycleLockDateList -Path $fullPath -DateFormat $DateFormat -Strict
    [PSCustomObject]@{
        Name     = $list.Name
        RowCount = $list.RowCount
        Entries  = $list.Entries
        Found    = $true
    }
}
