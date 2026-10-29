function Import-SPSLifecycleExclusionList {
    <#
        .SYNOPSIS
        Reads a list of sites that must never be touched.

        .DESCRIPTION
        The file has a Url column. Returns an object with the file name, the number of rows and
        Keys, a hashtable of normalized URLs (see ConvertTo-SPSLifecycleUrlKey).

        .PARAMETER Path
        Path of the CSV file.

        .EXAMPLE
        Import-SPSLifecycleExclusionList -Path .\exclusions.csv
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $name = Split-Path -Path $Path -Leaf
    $rows = @(Read-SPSLifecycleCsv -Path $Path -RequiredColumn 'Url')

    if ($rows.Count -gt 0) {
        Test-SPSLifecycleColumnPattern -Value $rows.Url -Pattern '^https?://' -What "'Url' in $name" -Hint 'The first column must hold the site URLs.'
    }

    $keys = @{}
    foreach ($row in $rows) {
        $key = ConvertTo-SPSLifecycleUrlKey -Url $row.Url
        if ($key) {
            $keys[$key] = $true
        }
    }

    [PSCustomObject]@{
        Name     = $name
        RowCount = $rows.Count
        Keys     = $keys
    }
}
