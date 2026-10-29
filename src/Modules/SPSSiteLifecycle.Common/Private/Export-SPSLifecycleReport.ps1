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

        The records can come from the pipeline, and each line is written as soon as its record arrives, so
        that a report of 260,000 sites needs no more memory than one of 100. PowerShell keeps several KB for
        each record that it has read and that is still referenced: pass the records through the pipeline
        instead of collecting them first.

        The lines go to a partial file in the same folder. The partial file takes the name of the report only
        when it is complete, by a move that refuses to replace a file. A run that stops half-way (a record
        that cannot be written, a full disk, Ctrl+C) leaves no report that looks complete: a reader would take
        the lines written so far for the whole report.

        A character that UTF-8 cannot hold (half of a surrogate pair) is written as U+FFFD, because one odd
        title must not stop a report of 260,000 sites.

        Returns the full path of the file.

        .PARAMETER Row
        The site records, as objects or as dictionaries (a hashtable), from the pipeline or as an array. A
        property or a key that a record does not have gives an empty cell.

        .PARAMETER OutputFolder
        The folder to write in. A relative folder is relative to the location of the PowerShell session.

        .PARAMETER Delimiter
        A comma, a semicolon or a tab. Default: the comma.

        .PARAMETER GeneratedOn
        The time of the run. Default: now.

        .PARAMETER Prefix
        The start of the file name. Default: sites.

        .EXAMPLE
        $verdicts | Export-SPSLifecycleReport -OutputFolder .\Reports -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
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

    begin {
        $stream = $null
        $writer = $null
        $partial = ''
        $published = $false
        $number = 0

        $columns = @(Get-SPSLifecycleReportColumn)
        $runCell = ConvertTo-SPSLifecycleReportCell -Kind Run -Value $GeneratedOn

        $folder = Resolve-SPSLifecycleFileSystemPath -Path $OutputFolder
        $null = [System.IO.Directory]::CreateDirectory($folder)
        $path = Join-Path -Path $folder -ChildPath "$Prefix-$runCell.csv"
        $existsMessage = "The report '$path' already exists and is never overwritten. Wait a second and run again, or move the file."
        if (Test-Path -LiteralPath $path) {
            throw $existsMessage
        }

        $partial = '{0}.{1}.partial' -f $path, [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
        $stream = [System.IO.File]::Open($partial, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($true, $false), 65536)
        $writer.Write((($columns | ForEach-Object { $_.Name }) -join $Delimiter) + "`r`n")
    }

    process {
        foreach ($record in $Row) {
            $number++
            $current = ''
            try {
                if ($null -eq $record) {
                    throw 'the record is empty.'
                }

                $isDictionary = $record -is [System.Collections.IDictionary]
                $cells = foreach ($column in $columns) {
                    $current = $column.Name
                    $value = $null
                    if ($isDictionary) {
                        if ($record.Contains($column.Name)) {
                            $value = $record[$column.Name]
                        }
                    }
                    else {
                        $property = $record.PSObject.Properties[$column.Name]
                        if ($null -ne $property) {
                            $value = $property.Value
                        }
                    }

                    if ($column.Kind -eq 'Run') {
                        $value = $GeneratedOn
                    }

                    $cell = ConvertTo-SPSLifecycleReportCell -Kind $column.Kind -Value $value
                    ConvertTo-SPSLifecycleCsvField -Text $cell -Delimiter $Delimiter
                }
            }
            catch {
                $site = if ($isDictionary) { "$($record['Url'])" } elseif ($null -ne $record) { "$($record.Url)" } else { '' }
                $where = if ($site) { " ($site)" } else { '' }
                $what = if ($current) { ", column $current" } else { '' }
                throw "Cannot write row $number$where$what`: $($_.Exception.Message)"
            }

            $writer.Write(($cells -join $Delimiter) + "`r`n")
        }
    }

    end {
        $writer.Flush()
        $stream.Flush($true)
        $writer.Dispose()

        try {
            [System.IO.File]::Move($partial, $path)
        }
        catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $path) {
                throw $existsMessage
            }

            throw
        }

        $published = $true
        $path
    }

    clean {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }

        if ($partial -and -not $published) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }
}
