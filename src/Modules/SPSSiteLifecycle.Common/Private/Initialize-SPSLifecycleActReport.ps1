function Initialize-SPSLifecycleActReport {
    <#
        .SYNOPSIS
        Creates the Act report, with its header, and gives its path.

        .DESCRIPTION
        The file is named act-<time of the run>.csv and created in OutputFolder, which is created when it is missing. An existing
        file is never replaced: the report is the record of what was done to a tenant, and a run that starts in the same second as
        an earlier one stops instead. It is written as UTF-8 with a byte order mark, with Windows line endings and the separator
        that the settings ask for, like the Scan report. The rows are added one at a time (see Add-SPSLifecycleActReportRow).

        .PARAMETER OutputFolder
        The folder to write in. A relative folder is relative to the location of the PowerShell session.

        .PARAMETER Delimiter
        A comma, a semicolon or a tab. Default: the comma.

        .PARAMETER GeneratedOn
        The time of the run. Default: now.

        .EXAMPLE
        $path = Initialize-SPSLifecycleActReport -OutputFolder .\Reports -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFolder,

        [Parameter()]
        [ValidateSet(',', ';', "`t")]
        [System.Char]
        $Delimiter = ',',

        [Parameter()]
        [System.DateTime]
        $GeneratedOn = [System.DateTime]::UtcNow
    )

    $folder = Resolve-SPSLifecycleFileSystemPath -Path $OutputFolder
    $null = [System.IO.Directory]::CreateDirectory($folder)
    $path = Join-Path -Path $folder -ChildPath ('act-{0}.csv' -f (ConvertTo-SPSLifecycleReportCell -Kind Run -Value $GeneratedOn))

    $header = ((Get-SPSLifecycleActReportColumn | ForEach-Object { $_.Name }) -join $Delimiter) + "`r`n"
    $stream = $null
    try {
        try {
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $path) {
                throw "The report '$path' already exists and is never overwritten: it is the record of what was done. Wait a second and run again, or move the file."
            }

            throw
        }

        $bytes = [System.Text.UTF8Encoding]::new($true).GetPreamble() + [System.Text.UTF8Encoding]::new($false).GetBytes($header)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    $path
}
