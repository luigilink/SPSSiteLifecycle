function Import-SPSLifecycleReviewedReport {
    <#
        .SYNOPSIS
        Reads the Scan report that a person reviewed, and checks the whole file before any action (D6).

        .DESCRIPTION
        The Act phase works from the CSV that the Scan wrote and that a person reviewed in a spreadsheet (D4). Nothing
        may be touched until the whole file has been checked, and any problem stops the tool and names the line and the
        value, so that a person fixes it in Excel. The file is read as the lists that a person gives are (see
        Read-SPSLifecycleStrictCsv, TolerantEncoding): the structure is strict, so that no row is swallowed or dropped, and
        the encoding is the one that Excel writes (UTF-8, UTF-16, Windows-1252). Act reads four columns only (D10), the
        others being read again from their source or live: Url, SiteId, GeneratedOn and Decision.

        Every row is checked, whether it has a decision or not, in the order of the file, and each row in this order
        (the first problem stops the tool). The text of a message (the place, the value written so that a hidden character
        shows) is made only when there is a problem: writing the value of a row costs more than checking it, and a file
        of 260,000 rows would take twice as long.

        1. the address: it is a full web address, in the form that SharePoint gives (https, no port, no user
           information, a host that DNS reads as it is written), and it is an address of the tenant of the settings
           (https://<tenant>.sharepoint.com/...). A refused tenant, a OneDrive address, another tenant and the admin site are
           refused, each with its own message;
        2. the site ID is a GUID, and not the GUID of zeros that a report with concealed names gives;
        3. the site does not appear twice, by its address (the canonical form, see ConvertTo-SPSLifecycleUrlKey: the case,
           a trailing slash, the default port and the percent-encoding do not count) or by its site ID: two rows for one site
           could carry two decisions. Rows without a decision count, because a file where a site appears twice is not the
           Scan report;
        4. the decision is empty (the site is left untouched), or Delete, Archive or Lock, whatever the case and the spaces
           around it. A hidden character, or a letter that only looks like another one, is not accepted;
        5. GeneratedOn can be read (ISO 8601, or a format of the CsvDateFormats setting: Excel rewrites a date that it
           understands), is not in the future (a margin of 5 minutes is left for the clocks of two machines), and is not older
           than MaxCsvAgeDays: a site may have changed since the Scan.

        An empty list of decisions is not an error: NothingToDo says that there is nothing to do.

        Returns an object with Path, Name, RowCount (the rows of the file), Rows (the rows that have a decision, in the order
        of the file, each with Line, Url, UrlKey, SiteId, Decision and GeneratedOn), Counts (Delete, Archive and Lock),
        ActionCount, NothingToDo, GeneratedOn (the oldest of the rows, UTC, or nothing when there is no row) and AgeDays
        (the age of that date). It reads the file and nothing else: it signs in to nothing and changes nothing.

        .PARAMETER Setting
        The settings of the Act phase (see Get-SPSLifecycleSetting): TenantName, RefusedTenants, CsvDateFormats, and
        Act.InputFile and Act.MaxCsvAgeDays.

        .PARAMETER Now
        The time of the run, in UTC. Default: now.

        .EXAMPLE
        Import-SPSLifecycleReviewedReport -Setting (Get-SPSLifecycleSetting -Path .\contoso.psd1 -Phase Act)
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Setting,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $missing = [System.Collections.Generic.List[System.String]]::new()
    if ($null -eq $Setting.PSObject.Properties['TenantName'] -or -not "$($Setting.TenantName)".Trim()) {
        $missing.Add('TenantName')
    }

    if ($null -eq $Setting.PSObject.Properties['Act'] -or $null -eq $Setting.Act) {
        $missing.Add('Act')
    }
    else {
        foreach ($name in 'InputFile', 'MaxCsvAgeDays') {
            if ($null -eq $Setting.Act.PSObject.Properties[$name] -or $null -eq $Setting.Act.$name) {
                $missing.Add("Act.$name")
            }
        }
    }

    if ($missing.Count -gt 0) {
        throw "The settings lack $($missing -join ', '). Read them with Get-SPSLifecycleSetting -Phase Act."
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $tenant = "$($Setting.TenantName)".Trim().ToLowerInvariant()
    $refused = @(Get-SPSLifecycleRefusedTenantList -RefusedTenant @($Setting.RefusedTenants))
    $dateFormats = if ($null -ne $Setting.PSObject.Properties['CsvDateFormats']) { @($Setting.CsvDateFormats) } else { @() }
    $maxAge = [System.TimeSpan]::FromDays([System.Int32]$Setting.Act.MaxCsvAgeDays)
    $utcNow = $Now.ToUniversalTime()
    $latestAllowed = $utcNow.AddMinutes(5)

    $fullPath = Resolve-SPSLifecycleFileSystemPath -Path "$($Setting.Act.InputFile)"
    $table = Read-SPSLifecycleStrictCsv -Path $fullPath -RequiredColumn 'Url', 'SiteId', 'GeneratedOn', 'Decision' -TolerantEncoding
    $name = $table.Name
    $rows = @($table.Rows)
    $lines = @($table.Line)

    $seenUrl = @{}
    $seenId = @{}
    $dateCache = @{}
    $decided = [System.Collections.Generic.List[System.Object]]::new()
    $counts = [ordered]@{ Delete = 0; Archive = 0; Lock = 0 }
    $oldest = $null

    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $line = $lines[$index]

        # 1. The address.
        $url = "$($row.Url)".Trim()
        if (-not $url) {
            throw "File '$name', line $line, column 'Url' is empty: the row cannot be matched with a site. Fix the row, or delete it."
        }

        if (-not (Test-SPSLifecycleWebAddress -Text $url)) {
            throw "File '$name', line $line`: '$(ConvertTo-SPSLifecycleVisibleText -Text $url)' is not a full web address (https://...). A row whose address cannot be used cannot be matched with a site. Fix the row, or delete it."
        }

        $uri = [System.Uri]::new($url)
        $hostText = $uri.Host
        $reason = ''
        if ($uri.Scheme -ne 'https') {
            $reason = 'it is not https'
        }
        elseif (-not $uri.IsDefaultPort) {
            $reason = 'it has a port'
        }
        elseif ($uri.UserInfo) {
            $reason = 'it has user information'
        }
        elseif ($hostText.EndsWith('.', [System.StringComparison]::Ordinal)) {
            $reason = 'its host ends with the dot of the DNS root'
        }
        elseif (-not [System.String]::Equals($uri.IdnHost, $hostText, [System.StringComparison]::Ordinal)) {
            $reason = "its host is '$(ConvertTo-SPSLifecycleVisibleText -Text $hostText -AsciiOnly)', which DNS does not read as it is written"
        }

        if (-not $reason) {
            $hostName = $hostText.ToLowerInvariant()
            $label = ''
            if ($hostName.EndsWith('.sharepoint.com', [System.StringComparison]::Ordinal)) {
                $label = $hostName.Substring(0, $hostName.Length - '.sharepoint.com'.Length)
            }

            # A refused tenant is told first, at its site, its OneDrive host and its admin site.
            $candidates = if ($label) { @($label) + @($label -replace '-(my|admin)\z', '') } else { @() }
            foreach ($candidate in $candidates) {
                if ($candidate -and $refused -contains $candidate) {
                    throw "File '$name', line $line`: the tenant '$candidate' of '$(ConvertTo-SPSLifecycleVisibleText -Text $url)' is refused: the tool never runs on the Microsoft corporate tenants or on a tenant listed in RefusedTenants. The file is not used."
                }
            }

            if ([System.String]::Equals($hostName, "$tenant.sharepoint.com", [System.StringComparison]::Ordinal)) {
                $reason = ''
            }
            elseif ([System.String]::Equals($hostName, "$tenant-my.sharepoint.com", [System.StringComparison]::Ordinal)) {
                throw "File '$name', line $line`: '$(ConvertTo-SPSLifecycleVisibleText -Text $url)' is a OneDrive address, and the tool never touches OneDrive sites (D12). Delete the row."
            }
            else {
                $reason = "its host is '$(ConvertTo-SPSLifecycleVisibleText -Text $hostText -AsciiOnly)'"
            }
        }

        if ($reason) {
            throw "File '$name', line $line`: '$(ConvertTo-SPSLifecycleVisibleText -Text $url)' is not an address of the tenant '$tenant': $reason. The tool needs https://$tenant.sharepoint.com/..., as the Scan writes it, and a file that holds another address is not the report of this tenant."
        }

        # 2. The site ID.
        $givenId = "$($row.SiteId)".Trim()
        if (-not $givenId) {
            throw "File '$name', line $line, column 'SiteId' is empty: Act confirms each site by its ID, because a URL can be reused by another site. Fix the row, or delete it."
        }

        $siteId = ConvertTo-SPSLifecycleId -Value $givenId
        if (-not $siteId) {
            throw "File '$name', line $line`: SiteId '$(ConvertTo-SPSLifecycleVisibleText -Text $givenId)' is not a GUID, or is all zeros (a report with concealed names gives zeros). Fix the row, or delete it."
        }

        # 3. The site does not appear twice.
        $urlKey = ConvertTo-SPSLifecycleUrlKey -Url $url
        if ($seenUrl.ContainsKey($urlKey)) {
            throw "File '$name', line $line`: this site is already on line $($seenUrl[$urlKey]), by its address '$(ConvertTo-SPSLifecycleVisibleText -Text $url)'. A site must appear once: two rows for one site could carry two decisions, and this file is not the Scan report. Delete one of the rows."
        }

        if ($seenId.ContainsKey($siteId)) {
            throw "File '$name', line $line`: this site is already on line $($seenId[$siteId]), by its site ID '$siteId'. A site must appear once: two rows for one site could carry two decisions, and this file is not the Scan report. Delete one of the rows."
        }

        $seenUrl[$urlKey] = $line
        $seenId[$siteId] = $line

        # 4. The decision.
        $decisionText = "$($row.Decision)".Trim()
        $decision = ''
        if ($decisionText) {
            foreach ($known in 'Delete', 'Archive', 'Lock') {
                if ([System.String]::Equals($decisionText, $known, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $decision = $known
                    break
                }
            }

            if (-not $decision) {
                throw "File '$name', line $line`: Decision '$(ConvertTo-SPSLifecycleVisibleText -Text $decisionText -AsciiOnly)' is not Delete, Archive or Lock. An empty Decision leaves the site untouched, and any other value stops the tool before the first action."
            }
        }

        # 5. GeneratedOn.
        $dateText = "$($row.GeneratedOn)".Trim()
        if (-not $dateText) {
            throw "File '$name', line $line, column 'GeneratedOn' is empty: the age of the file cannot be told, so the tool cannot know whether a site changed since the Scan."
        }

        if (-not $dateCache.ContainsKey($dateText)) {
            try {
                $parsed = ConvertTo-SPSLifecycleDate -Text $dateText -DateFormat $dateFormats
            }
            catch {
                throw "File '$name', line $line, column 'GeneratedOn': $($_.Exception.Message)"
            }

            $parsedText = $parsed.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant)
            if ($parsed -gt $latestAllowed) {
                throw "File '$name', line $line, column 'GeneratedOn': $parsedText is in the future (now: $($utcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant))). The clock of this machine, or of the one that wrote the file, is wrong, or this file is not a Scan report."
            }

            $age = $utcNow - $parsed
            if ($age -gt $maxAge) {
                throw "File '$name', line $line, column 'GeneratedOn': the file was generated on $parsedText, $([System.Math]::Floor($age.TotalDays).ToString('0', $invariant)) days ago, which is older than MaxCsvAgeDays ($($Setting.Act.MaxCsvAgeDays) days): a site may have changed since. Run the Scan again."
            }

            $dateCache[$dateText] = $parsed
        }

        $generated = $dateCache[$dateText]
        if ($null -eq $oldest -or $generated -lt $oldest) {
            $oldest = $generated
        }

        if ($decision) {
            $counts[$decision]++
            $decided.Add([PSCustomObject][ordered]@{
                    Line        = $line
                    Url         = $url
                    UrlKey      = $urlKey
                    SiteId      = $siteId
                    Decision    = $decision
                    GeneratedOn = $generated
                })
        }
    }

    [PSCustomObject][ordered]@{
        Path        = $fullPath
        Name        = $name
        RowCount    = $rows.Count
        Rows        = $decided.ToArray()
        Counts      = $counts
        ActionCount = $decided.Count
        NothingToDo = ($decided.Count -eq 0)
        GeneratedOn = $oldest
        AgeDays     = if ($null -ne $oldest) { ($utcNow - $oldest).TotalDays } else { $null }
    }
}
