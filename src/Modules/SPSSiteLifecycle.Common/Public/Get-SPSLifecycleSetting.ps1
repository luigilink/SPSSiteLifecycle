function Get-SPSLifecycleSetting {
    <#
        .SYNOPSIS
        Reads and checks the settings file of SPSSiteLifecycle.

        .DESCRIPTION
        The settings live in a PowerShell data file (.psd1). Shared keys are written at the top of
        the file; the keys of one phase are written in the Scan or Act section. The file is read
        with Import-PowerShellDataFile, so no code in it is ever run.

        The whole file is checked, and every problem is reported at once:

        - an unknown key stops the tool, so that a typo cannot silently disable a safeguard (the
          message suggests the closest name, and says when a key is in the wrong section);
        - types are strict (a number is a number, a boolean is $true or $false, never the text 'false');
        - a relative path is relative to the folder of the settings file;
        - the required keys and the existence of the input files are checked for the requested
          phase only, so that a Scan can run before the Act settings are filled in;
        - the tenant must not be one of the refused tenants.

        Returns an object with the effective settings (defaults applied, paths resolved): the shared
        settings, then the Scan and Act sections, plus Phase, ConfigPath, ConfigFolder, TenantUrl,
        AdminUrl and CsvDelimiterChar.

        .PARAMETER Path
        Path of the settings file.

        .PARAMETER Phase
        Scan or Act.

        .EXAMPLE
        Get-SPSLifecycleSetting -Path .\SPSSiteLifecycle.psd1 -Phase Scan
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Scan', 'Act')]
        [System.String]
        $Phase
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Settings file not found: '$Path'. Copy src/config/SPSSiteLifecycle.example.psd1 and fill it in."
    }

    $configPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $configFolder = Split-Path -Path $configPath -Parent
    $fileName = Split-Path -Path $configPath -Leaf

    try {
        $data = Import-PowerShellDataFile -LiteralPath $configPath -ErrorAction Stop
    }
    catch {
        throw "Cannot read the settings file '$configPath'. It must be a PowerShell data file: @{ Key = value }, with no code. $($_.Exception.Message)"
    }

    if ($data -isnot [System.Collections.IDictionary]) {
        throw "The settings file '$configPath' must hold one hashtable: @{ Key = value }."
    }

    $schema = @(Get-SPSLifecycleSettingSchema)
    $problems = [System.Collections.Generic.List[System.String]]::new()
    $sections = @('Scan', 'Act')
    $sharedNames = @($schema | Where-Object { $_.Section -eq 'Shared' } | ForEach-Object { $_.Name })
    $allNames = @($schema | ForEach-Object { $_.Name }) + $sections

    # A name is compared one character at a time, ignoring the case: the comparison operators of PowerShell (-in, -ieq,
    # -contains) skip a zero-width space and a soft hyphen, so 'Refused<zero-width space>Tenants' would be read as the
    # name RefusedTenants, kept under its own spelling, never found when the setting is read, and the refusal of the
    # tenants would silently not apply. The name that is returned is the one of the schema, and the settings are kept
    # under it.
    $findName = {
        param($Names, $Key)
        foreach ($candidate in $Names) {
            if ([System.String]::Equals($candidate, "$Key", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $candidate
            }
        }

        $null
    }

    $describeUnknown = {
        param($Key, $Where)
        $shown = ConvertTo-SPSLifecycleVisibleText -Text "$Key" -AsciiOnly
        $elsewhere = @($schema | Where-Object { [System.String]::Equals($_.Name, "$Key", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($elsewhere.Count -gt 0) {
            $row = $elsewhere[0]
            if ($row.Section -eq 'Shared') {
                return "'$($row.Name)' is a shared setting: write it at the top of the file, outside the $Where section."
            }

            return "'$($row.Name)' belongs in the $($row.Section) section: $($row.Section) = @{ $($row.Name) = ... }."
        }

        $similar = Get-SPSLifecycleSimilarName -Name "$Key" -Candidate $allNames
        $hint = if ($similar) { " Did you mean '$similar'?" } else { '' }
        "Unknown setting '$shown'.$hint"
    }

    $raw = @{ Shared = @{}; Scan = @{}; Act = @{} }
    foreach ($key in $data.Keys) {
        $sharedName = & $findName $sharedNames $key
        $canonical = & $findName $sections $key
        if ($sharedName) {
            $raw.Shared[$sharedName] = $data[$key]
        }
        elseif ($canonical) {
            if ($data[$key] -isnot [System.Collections.IDictionary]) {
                $problems.Add("$canonical must be a section: $canonical = @{ ... }.")
                continue
            }

            $sectionNames = @($schema | Where-Object { $_.Section -eq $canonical } | ForEach-Object { $_.Name })
            foreach ($inner in $data[$key].Keys) {
                $innerName = & $findName $sectionNames $inner
                if ($innerName) {
                    $raw[$canonical][$innerName] = $data[$key][$inner]
                }
                else {
                    $problems.Add("$canonical section: $(& $describeUnknown $inner $canonical)")
                }
            }
        }
        else {
            $problems.Add((& $describeUnknown $key 'top-level'))
        }
    }

    $effective = @{ Shared = [ordered]@{}; Scan = [ordered]@{}; Act = [ordered]@{} }
    $provided = @{}
    foreach ($row in $schema) {
        $source = $raw[$row.Section]
        $label = if ($row.Section -eq 'Shared') { $row.Name } else { "$($row.Section).$($row.Name)" }
        $isUsed = $row.UsedIn -contains $Phase
        $hasValue = $source.ContainsKey($row.Name)

        if ($hasValue) {
            $check = Resolve-SPSLifecycleSettingValue -Row $row -Value $source[$row.Name] -BaseFolder $configFolder -CheckExistence:$isUsed
            if ($check.Error) {
                $problems.Add("${label}: $($check.Error)")
                $effective[$row.Section][$row.Name] = $row.Default
                continue
            }

            $effective[$row.Section][$row.Name] = $check.Value
            $isEmpty = ($row.Type -eq 'Path' -and -not $check.Value)
            $provided[$label] = -not $isEmpty
        }
        else {
            $effective[$row.Section][$row.Name] = $row.Default
            if ($row.Type -eq 'Path' -and $row.Default) {
                $effective[$row.Section][$row.Name] = ConvertTo-SPSLifecyclePath -Path $row.Default -BaseFolder $configFolder
            }

            $provided[$label] = $false
        }

        if ($row.RequiredIn -contains $Phase -and -not $provided[$label]) {
            $problems.Add("${label}: required for the $Phase phase.")
        }
    }

    $shared = $effective.Shared
    $scan = $effective.Scan
    $act = $effective.Act

    if ($shared.TenantName) {
        $shared.TenantName = $shared.TenantName.ToLowerInvariant()
    }

    $refused = @(Get-SPSLifecycleRefusedTenantList -RefusedTenant $shared.RefusedTenants)
    $shared.RefusedTenants = $refused
    if ($shared.TenantName -and (Test-SPSLifecycleRefusedTenant -TenantName $shared.TenantName -RefusedTenant $refused)) {
        $problems.Add("TenantName: the tenant '$($shared.TenantName)' is refused. The tool never runs on the Microsoft corporate tenants or on a tenant listed in RefusedTenants.")
    }

    if ($Phase -eq 'Scan') {
        $reports = @('Scan.SharePointUsageReport', 'Scan.TeamsActivityReport', 'Scan.GroupsActivityReport')
        if (@($reports | Where-Object { $provided[$_] }).Count -eq 0) {
            $problems.Add('Scan: give at least one activity report: SharePointUsageReport, TeamsActivityReport or GroupsActivityReport. Without one, the tool cannot tell which sites are inactive.')
        }
    }

    if ($act.GrantSiteAdmin -eq $true -and $act.UnlockBeforeArchive -ne $true) {
        $problems.Add('Act.GrantSiteAdmin: requires Act.UnlockBeforeArchive = $true, because a read-only site refuses a change of owners.')
    }

    if ($problems.Count -gt 0) {
        $lines = $problems | ForEach-Object { "  - $_" }
        throw "The settings file '$fileName' has $($problems.Count) problem(s):`n$($lines -join "`n")"
    }

    if (-not $shared.LockJournal) {
        $shared.LockJournal = Join-Path -Path $shared.OutputFolder -ChildPath 'lock-journal.csv'
    }

    $delimiterChar = switch ($shared.CsvDelimiter) {
        'Culture' {
            $separator = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ListSeparator
            if ($separator) { $separator[0] } else { [System.Char]',' }
        }
        'Tab' { [System.Char]"`t" }
        default { [System.Char]$shared.CsvDelimiter }
    }

    $result = [ordered]@{
        Phase        = $Phase
        ConfigPath   = $configPath
        ConfigFolder = $configFolder
        TenantUrl    = "https://$($shared.TenantName).sharepoint.com"
        AdminUrl     = "https://$($shared.TenantName)-admin.sharepoint.com"
    }

    foreach ($name in $shared.Keys) {
        $result[$name] = $shared[$name]
    }

    $result['CsvDelimiterChar'] = $delimiterChar
    $result['Scan'] = [PSCustomObject]$scan
    $result['Act'] = [PSCustomObject]$act

    [PSCustomObject]$result
}
