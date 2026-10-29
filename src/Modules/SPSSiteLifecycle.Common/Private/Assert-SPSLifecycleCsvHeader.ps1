function Assert-SPSLifecycleCsvHeader {
    <#
        .SYNOPSIS
        Stops the tool when the header of a CSV file cannot be trusted.

        .DESCRIPTION
        Three things stop the tool, in this order, and each message shows a hidden character as \uXXXX:

        - A column that appears twice (the case and the spaces around a name do not count).
        - A header that looks like a column the tool knows (required or optional) and is not spelled as the tool
          expects: Site ID, Site_Id or Site<U+00AD>Id for SiteId. The tool reads a column by its exact name, so
          such a header would be read as a column that is not there, and an optional column that is not there is
          normal: the site ID of every row would be lost without a message. This comes before the missing
          column, because "SiteId is missing" is a poor message when a column that looks like SiteId is there.
        - A required column that is missing.

        The names are compared one character at a time, whatever the case and the culture, the way a row finds
        its properties (see Test-SPSLifecycleColumnName).

        .PARAMETER Name
        The names of the columns, as they are written in the header (they are trimmed).

        .PARAMETER RequiredColumn
        The columns that must exist.

        .PARAMETER OptionalColumn
        The columns that may exist, and that the tool would read if they did. List the ones that carry a safeguard.

        .PARAMETER Source
        What the messages call the file: its name or its path.

        .EXAMPLE
        Assert-SPSLifecycleCsvHeader -Name $header -RequiredColumn 'Url', 'LockedOn' -OptionalColumn 'SiteId' -Source 'lot1.csv'
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.String[]]
        $Name,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $RequiredColumn = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $OptionalColumn = @(),

        [Parameter(Mandatory = $true)]
        [System.String]
        $Source
    )

    $names = @($Name | ForEach-Object { "$_".Trim() })
    $filled = @($names | Where-Object { $_ })

    $seen = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $repeated = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($column in $filled) {
        if (-not $seen.Add($column)) {
            $null = $repeated.Add($column)
        }
    }

    if ($repeated.Count -gt 0) {
        throw "Column(s) that appear more than once in '$Source' (the case and the spaces around a name do not count): $(@($repeated | ForEach-Object { ConvertTo-SPSLifecycleVisibleText -Text $_ }) -join ', ')."
    }

    $known = @(@($RequiredColumn) + @($OptionalColumn) | Where-Object { $_ } | Select-Object -Unique)
    foreach ($column in $filled) {
        if (Test-SPSLifecycleColumnName -Name $known -Column $column) {
            continue
        }

        $key = ConvertTo-SPSLifecycleColumnKey -Name $column
        if (-not $key) {
            continue
        }

        foreach ($candidate in $known) {
            if ((ConvertTo-SPSLifecycleColumnKey -Name $candidate) -ceq $key) {
                throw "In '$Source', the column '$(ConvertTo-SPSLifecycleVisibleText -Text $column)' looks like '$candidate' but is not spelled that way (a space, a separator or a hidden character). The tool reads a column by its exact name, and without '$candidate' the information that it carries would be lost without a message. Rename the column to '$candidate'."
            }
        }
    }

    $missing = @($RequiredColumn | Where-Object { -not (Test-SPSLifecycleColumnName -Name $filled -Column $_) })
    if ($missing.Count -gt 0) {
        $present = if ($filled.Count -gt 0) { @($filled | ForEach-Object { ConvertTo-SPSLifecycleVisibleText -Text $_ }) -join ', ' } else { '(none: the file is empty)' }
        throw "Column(s) not found in '$Source': $($missing -join ', '). Columns present: $present."
    }
}
