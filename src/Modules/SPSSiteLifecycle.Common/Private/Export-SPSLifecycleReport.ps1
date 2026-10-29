function Export-SPSLifecycleReport {
    <#
        .SYNOPSIS
        Writes the Scan report: the CSV file that a person reviews and that the Act phase reads.

        .DESCRIPTION
        One line per site, with the columns of Get-SPSLifecycleReportColumn in that order (D10). The file is
        written to be opened and saved again in a spreadsheet:

        - UTF-8 with a byte order mark, so that Excel reads the accents, Windows line endings, and the
          separator that the settings ask for (a semicolon for French).
        - Sizes in whole megabytes, dates in ISO 8601 and the time of the run in the compact form
          20261028T163000Z, whatever the culture of the machine.
        - Decision is always empty: the tool never decides in the place of a person, whatever the record
          holds. GeneratedOn is the time of the run, the same on every line.
        - Texts that come from the tenant are neutralized against formula injection (CWE-1236).
        - No owners (personal data): a property of the record that is not a column is not written.

        The file is named sites-<time of the run>.csv and written in OutputFolder, which is created when
        it is missing. An existing file is never overwritten: it is a reviewed document, and a run that
        starts in the same second as an earlier one stops instead of replacing it.

        Returns the full path of the file.

        .PARAMETER Row
        The site records. A property that a record does not have gives an empty cell.

        .PARAMETER OutputFolder
        The folder to write in. A relative folder is relative to the location of the PowerShell session.

        .PARAMETER Delimiter
        A comma, a semicolon or a tab. Default: the comma.

        .PARAMETER GeneratedOn
        The time of the run. Default: now.

        .PARAMETER Prefix
        The start of the file name. Default: sites.

        .EXAMPLE
        Export-SPSLifecycleReport -Row $rows -OutputFolder .\Reports -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Row,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [ValidateSet(',', ';', "`t")]
        [System.Char]
        $Delimiter = ',',

        [Parameter()]
        [System.DateTime]
        $GeneratedOn = [System.DateTime]::UtcNow,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
        [System.String]
        $Prefix = 'sites'
    )

    $columns = @(Get-SPSLifecycleReportColumn)
    $runCell = ConvertTo-SPSLifecycleReportCell -Kind Run -Value $GeneratedOn

    $folder = Resolve-SPSLifecycleFileSystemPath -Path $OutputFolder
    $null = [System.IO.Directory]::CreateDirectory($folder)
    $path = Join-Path -Path $folder -ChildPath "$Prefix-$runCell.csv"
    if (Test-Path -LiteralPath $path) {
        throw "The report '$path' already exists and is never overwritten. Wait a second and run again, or move the file."
    }

    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append((($columns | ForEach-Object { $_.Name }) -join $Delimiter)).Append("`r`n")

    foreach ($record in $Row) {
        $cells = foreach ($column in $columns) {
            $property = $record.PSObject.Properties[$column.Name]
            $value = if ($null -ne $property) { $property.Value } else { $null }
            if ($column.Kind -eq 'Run') {
                $value = $GeneratedOn
            }

            $cell = ConvertTo-SPSLifecycleReportCell -Kind $column.Kind -Value $value
            ConvertTo-SPSLifecycleCsvField -Text $cell -Delimiter $Delimiter
        }

        $null = $builder.Append(($cells -join $Delimiter)).Append("`r`n")
    }

    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $bytes = [System.Text.UTF8Encoding]::new($true).GetPreamble() + [System.Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }

    $path
}
