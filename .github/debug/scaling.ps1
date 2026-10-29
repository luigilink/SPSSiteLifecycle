# Runs the work of the Size tests outside Pester, step by step, with a timestamp before and after every step.
param
(
    [ValidateSet('scaling', 'raw', 'others', 'import')]
    [string]
    $Stage = 'scaling'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
$module = Import-Module -Name (Join-Path -Path $root -ChildPath 'src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1') -Force -PassThru

function Write-Step {
    param([string]$Message)
    [System.Console]::Out.WriteLine(('{0:HH:mm:ss.fff}Z {1}' -f [System.DateTime]::UtcNow, $Message))
    [System.Console]::Out.Flush()
}

function Invoke-Strict {
    param([string]$Text, [switch]$ValidateOnly)
    & $module {
        param($t, $v)
        ConvertFrom-SPSLifecycleStrictCsv -Text $t -Delimiter ',' -Source 'debug.csv' -ValidateOnly:$v
    } $Text ([bool]$ValidateOnly)
}

function New-Text {
    param([int]$Count)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($i in 1..$Count) {
        $null = $builder.Append("https://contoso.sharepoint.com/sites/site$i,a6e20079-2d1a-4e9d-bc9f-94e3f2efeb64,2025-09-18T10:00:00Z`r`n")
    }

    $builder.ToString()
}

switch ($Stage) {
    'scaling' {
        foreach ($count in 1000, 5000, 20000, 50000, 100000, 200000, 260000) {
            Write-Step "== $count records: building the text"
            $text = New-Text -Count $count
            Write-Step ('   text built, {0:N1} MB' -f ($text.Length / 1MB))
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Step '   validating'
            $valid = Invoke-Strict -Text $text -ValidateOnly
            Write-Step ('   validated: {0} in {1:N2} s' -f $valid, $watch.Elapsed.TotalSeconds)
            $watch.Restart()
            Write-Step '   parsing'
            $records = @(Invoke-Strict -Text $text)
            Write-Step ('   parsed: {0} records in {1:N2} s' -f $records.Count, $watch.Elapsed.TotalSeconds)
        }
    }

    'raw' {
        $text = New-Text -Count 260000
        $separator = [System.Text.RegularExpressions.Regex]::Escape(',')
        $quoted = '"(?>[^"]+|"")*"'
        $plain = '[^"' + $separator + '\r\n]*'
        $lineEnd = '(?:\r\n|\n|\r)'
        $options = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        $record = [System.Text.RegularExpressions.Regex]::new("\G(?<f>$quoted|$plain)(?:$separator(?<f>$quoted|$plain))*(?:$lineEnd|\z)", $options, [System.TimeSpan]::FromSeconds(120))

        foreach ($mode in 'nextmatch', 'nextmatch-captures', 'match') {
            Write-Step "raw regex, mode $mode"
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $position = 0
            $count = 0
            $found = $null
            while ($position -lt $text.Length) {
                $found = if ($mode -like 'nextmatch*') {
                    if ($null -eq $found) { $record.Match($text) } else { $found.NextMatch() }
                }
                else {
                    $record.Match($text, $position)
                }

                if (-not $found.Success) {
                    throw "no match at $position"
                }

                $position = $found.Index + $found.Length
                $value = $found.Value
                if ($mode -eq 'nextmatch-captures') {
                    $captures = $found.Groups['f'].Captures
                    for ($i = 0; $i -lt $captures.Count; $i++) {
                        $cell = $captures[$i].Value
                    }
                }

                $count++
                $every = if ($mode -eq 'match') { 500 } else { 20000 }
                if ($count % $every -eq 0) {
                    Write-Step ('   {0} records, position {1}, {2:N1} s' -f $count, $position, $watch.Elapsed.TotalSeconds)
                }

                if ($mode -eq 'match' -and $count -ge 3000) {
                    Write-Step '   stopped at 3000 records: the full run would last hours'
                    break
                }
            }

            Write-Step ('mode {0} done: {1} records in {2:N1} s' -f $mode, $count, $watch.Elapsed.TotalSeconds)
        }

        Write-Step 'creating 260000 PSCustomObject, collected by the foreach'
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $list = foreach ($i in 1..260000) {
            [PSCustomObject]@{ Line = $i; Fields = [System.String[]]@('a', 'b', 'c') }
        }
        Write-Step ('   {0} objects in {1:N1} s' -f @($list).Count, $watch.Elapsed.TotalSeconds)

        function Get-Objects {
            foreach ($i in 1..260000) {
                [PSCustomObject]@{ Line = $i; Fields = [System.String[]]@('a', 'b', 'c') }
            }
        }

        Write-Step 'creating 260000 PSCustomObject, emitted by a function and collected by @()'
        $watch.Restart()
        $emitted = @(Get-Objects)
        Write-Step ('   {0} objects in {1:N1} s' -f $emitted.Count, $watch.Elapsed.TotalSeconds)
    }

    'import' {
        foreach ($count in 20000, 100000, 260000) {
            Write-Step "== a journal of $count rows: writing the file"
            $path = Join-Path -Path $env:RUNNER_TEMP -ChildPath "journal-$count.csv"
            $writer = [System.IO.StreamWriter]::new($path, $false, [System.Text.UTF8Encoding]::new($true))
            $writer.WriteLine('Url,SiteId,LockedOn')
            foreach ($i in 1..$count) {
                $writer.WriteLine("https://contoso.sharepoint.com/sites/site$i,$([System.Guid]::NewGuid()),2026-10-29T10:00:00Z")
            }

            $writer.Dispose()
            Write-Step ('   written, {0:N1} MB' -f ((Get-Item -LiteralPath $path).Length / 1MB))
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $journal = & $module { param($p) Import-SPSLifecycleLockJournal -Path $p } $path
            Write-Step ('   Import-SPSLifecycleLockJournal: {0} entries in {1:N1} s' -f @($journal.Entries).Count, $watch.Elapsed.TotalSeconds)
            $watch.Restart()
            $index = & $module { param($p) Get-SPSLifecycleLockDateIndex -LockJournal $p } $path
            Write-Step ('   Get-SPSLifecycleLockDateIndex: {0} sites in {1:N1} s' -f $index.ById.Count, $watch.Elapsed.TotalSeconds)
            Remove-Item -LiteralPath $path
        }
    }

    'others' {
        Write-Step 'a quoted field of 5 MB with many quotes'
        $text = '"' + (('ab""' * 1250000)) + '"' + "`r`n"
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $valid = Invoke-Strict -Text $text -ValidateOnly
        Write-Step ('   validated: {0} in {1:N2} s' -f $valid, $watch.Elapsed.TotalSeconds)

        Write-Step 'a text that cannot match'
        $text = ('"a' * 200000) + "`r`n"
        $watch.Restart()
        try {
            $null = Invoke-Strict -Text $text -ValidateOnly
            Write-Step '   NOT refused'
        }
        catch {
            Write-Step ('   refused in {0:N2} s: {1}' -f $watch.Elapsed.TotalSeconds, $_.Exception.Message.Substring(0, 80))
        }
    }
}

Write-Step "stage $Stage finished"
