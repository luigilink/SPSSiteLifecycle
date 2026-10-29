function Get-SPSLifecycleExclusionIndex {
    <#
        .SYNOPSIS
        Reads the exclusion lists and merges them into one index of the sites that must never be touched.

        .DESCRIPTION
        Both phases need the same index: the Scan phase to give a listed site SKIP-EXCLUDED, and the Act phase to
        check it again before an action, because a decision never lifts a safeguard. The addresses of all the lists are
        merged by their canonical form (see ConvertTo-SPSLifecycleUrlKey), so that two spellings of an address are one
        key, and the first file that holds an address is the one that is named.

        A list that cannot be read stops the tool and names the file (see Import-SPSLifecycleExclusionList): a row
        that is lost would protect nothing, and no one would notice.

        Returns an object with Keys (a hashtable from the canonical address to the name of the file that holds it)
        and Imports (what Import-SPSLifecycleExclusionList gave for each file).

        .PARAMETER ExclusionFile
        The paths of the exclusion lists (the ExclusionFiles setting).

        .EXAMPLE
        Get-SPSLifecycleExclusionIndex -ExclusionFile .\exclusions.csv, .\vip.csv
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.String[]]
        $ExclusionFile = @()
    )

    $imports = [System.Collections.Generic.List[System.Object]]::new()
    $keys = @{}
    foreach ($file in @($ExclusionFile)) {
        if (-not $file) {
            continue
        }

        $import = Import-SPSLifecycleExclusionList -Path $file
        $imports.Add($import)
        foreach ($key in $import.Keys.Keys) {
            if (-not $keys.ContainsKey($key)) {
                $keys[$key] = $import.Name
            }
        }
    }

    [PSCustomObject]@{
        Keys    = $keys
        Imports = $imports.ToArray()
    }
}
