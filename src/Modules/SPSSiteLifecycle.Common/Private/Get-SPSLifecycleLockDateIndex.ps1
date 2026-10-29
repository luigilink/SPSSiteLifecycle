function Get-SPSLifecycleLockDateIndex {
    <#
        .SYNOPSIS
        Reads the lock date lists and the lock journal, and merges them into one index.

        .DESCRIPTION
        Both phases need the same index: the Scan phase to give each site its verdict, and the Act phase to
        check it again before an action. The lists come first, then the journal, so that on equal dates the
        list that a person provided is the one that is named. See Merge-SPSLifecycleLockDate for the rules.

        A list that cannot be read stops the tool and names the file: a lock date that is lost could make a
        recent lock look old.

        .PARAMETER LockDateFile
        The paths of the lock date lists (the LockDateFiles setting).

        .PARAMETER LockJournal
        The path of the lock journal (the LockJournal setting). It may not exist yet.

        .PARAMETER DateFormat
        Extra date formats from the CsvDateFormats setting.

        .EXAMPLE
        Get-SPSLifecycleLockDateIndex -LockDateFile .\lot1.csv, .\lot2.csv -LockJournal .\lock-journal.csv
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $LockDateFile = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $LockJournal = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $DateFormat = @()
    )

    $imports = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($file in @($LockDateFile)) {
        if ($file) {
            $imports.Add((Import-SPSLifecycleLockDateList -Path $file -DateFormat $DateFormat))
        }
    }

    if ($LockJournal) {
        $imports.Add((Import-SPSLifecycleLockJournal -Path $LockJournal -DateFormat $DateFormat))
    }

    Merge-SPSLifecycleLockDate -Import $imports.ToArray()
}
