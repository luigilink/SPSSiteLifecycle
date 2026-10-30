function Import-SPSLifecycleExclusionList {
    <#
        .SYNOPSIS
        Reads a list of sites that must never be touched.

        .DESCRIPTION
        The file has a Url column. Returns an object with the file name, the number of rows and
        Keys, a hashtable of normalized URLs (see ConvertTo-SPSLifecycleUrlKey).

        The file is read by Read-SPSLifecycleStrictCsv with TolerantEncoding: the structure is read strictly, because
        a row that is swallowed (a quote that is never closed) or dropped (a value beyond the header, a row cut short)
        protects nothing and no one would notice, and the encoding is read as Excel writes it (UTF-8, UTF-16,
        Windows-1252), a byte order mark being a declaration: a byte that does not fit it is a damage and stops
        the tool. The messages name the file and the line.

        Every filled cell must be a full web address (http or https) on one line, without a space.
        A row that cannot be read would protect nothing, and no one would notice, so the tool stops
        and names the first values it could not read instead of skipping them. This is stricter than
        the other lists, on purpose: a lock date that is not read only keeps a site safe, an exclusion
        that is not read puts a site at risk. Blank cells are ignored.

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
    $table = Read-SPSLifecycleStrictCsv -Path $Path -RequiredColumn 'Url' -TolerantEncoding
    $rows = @($table.Rows)
    $lines = @($table.Line)

    $keys = @{}
    $unreadable = [System.Collections.Generic.List[System.Object]]::new()
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $text = "$($rows[$index].Url)".Trim()
        if (-not $text) {
            continue
        }

        $uri = $null
        $valid = $text -notmatch '\s' -and [System.Uri]::TryCreate($text, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in 'http', 'https' -and $uri.Host
        if (-not $valid) {
            $unreadable.Add([PSCustomObject]@{ Text = $text; Line = $lines[$index] })
            continue
        }

        $keys[(ConvertTo-SPSLifecycleUrlKey -Url $text)] = $true
    }

    if ($unreadable.Count -gt 0) {
        $examples = @($unreadable | Select-Object -First 3 | ForEach-Object {
                $oneLine = $_.Text -replace '\s+', ' '
                $shown = if ($oneLine.Length -gt 80) { "'$($oneLine.Substring(0, 80))...'" } else { "'$oneLine'" }
                "$shown (line $($_.Line))"
            }) -join ', '
        throw "File '$name': $($unreadable.Count) value(s) in the 'Url' column are not site URLs, for example $examples. Each one must be a full address on one line, such as https://contoso.sharepoint.com/sites/name. A row that cannot be read would protect nothing, so the tool stops instead of skipping it."
    }

    [PSCustomObject]@{
        Name     = $name
        RowCount = $rows.Count
        Keys     = $keys
    }
}
