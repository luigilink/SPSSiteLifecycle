function Read-SPSLifecycleListingCheckpoint {
    <#
        .SYNOPSIS
        Finds out whether the checkpoint of an output folder can be taken up, and says why when it cannot.

        .DESCRIPTION
        A listing is the live state of the tenant at the time it was read, and a Scan that reuses pages that are too
        old would work on a state that is gone. A checkpoint is therefore taken up only when all of this holds:

        - the run that wrote it did not finish (a finished listing is never reused to answer a new Scan);
        - it is for the same tenant, with the same filter and the same options (what is asked about OneDrive sites,
          the call that is used), because the pages hold what was asked;
        - it is not older than MaxAgeHours (24), counted from the start of the listing, because the first pages are
          the oldest, and it is not dated in the future (a clock that was set back);
        - the manifest is the one that the tool writes, and every page it lists is there and has the hash that was
          saved, so that a page that was changed, cut or replaced is never read.

        Returns an object with Exists (something was found), Usable, Finished (what was found is the manifest of a
        listing that finished, which is normal and not a problem), Reason (empty when there was nothing, or when it
        is usable) and Manifest (the manifest to add pages to, when it is usable).

        .PARAMETER Folder
        The folder of the checkpoint.

        .PARAMETER Tenant
        The name of the tenant that is listed (the case is ignored).

        .PARAMETER Filter
        The server filter of the listing, empty for none.

        .PARAMETER Options
        The text that Initialize-SPSLifecycleListingManifest was given.

        .PARAMETER Now
        The time of the check.

        .PARAMETER MaxAgeHours
        The age beyond which a checkpoint is not taken up. Default: 24.

        .EXAMPLE
        Read-SPSLifecycleListingCheckpoint -Folder $folder -Tenant contoso -Filter '' -Options 'Source=Csom' -Now ([System.DateTime]::UtcNow)
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Folder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Tenant,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Filter,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Options,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $Now,

        [Parameter()]
        [ValidateRange(0.001, 8760)]
        [System.Double]
        $MaxAgeHours = 24
    )

    $result = {
        param($Exists, $Usable, $Reason, $Manifest, $Finished = $false, $Code = '')
        [PSCustomObject][ordered]@{ Exists = $Exists; Usable = $Usable; Finished = $Finished; Reason = $Reason; Code = $Code; Manifest = $Manifest }
    }

    $fullFolder = Resolve-SPSLifecycleFileSystemPath -Path $Folder
    $path = Join-Path -Path $fullFolder -ChildPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return & $result $false $false '' $null
    }

    $json = $null
    try {
        $json = Get-Content -LiteralPath $path -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return & $result $true $false "The checkpoint is damaged: the manifest cannot be read as JSON ($($_.Exception.Message))." $null $false 'damaged'
    }

    if ($json -is [System.Management.Automation.PSCustomObject] -and $null -ne $json.PSObject.Properties['Version'] -and $json.Version -ne 1) {
        return & $result $true $false "The checkpoint was written by another version of the tool (version $(ConvertTo-SPSLifecycleVisibleText -Text "$($json.Version)"), and this one reads version 1)." $null $false 'other-version'
    }

    $problem = Get-SPSLifecycleListingManifestProblem -Manifest $json
    if ($problem) {
        return & $result $true $false "The checkpoint is damaged: $problem" $null $false 'damaged'
    }

    if ([System.String]::Equals($json.State, 'Completed', [System.StringComparison]::Ordinal)) {
        return & $result $true $false 'The previous listing finished, and a finished listing is never reused to answer a new Scan: a new one starts.' $null $true 'finished'
    }

    if (-not [System.String]::Equals($json.Tenant, $Tenant, [System.StringComparison]::OrdinalIgnoreCase)) {
        return & $result $true $false "The checkpoint was made for the tenant '$(ConvertTo-SPSLifecycleVisibleText -Text $json.Tenant)', not for '$(ConvertTo-SPSLifecycleVisibleText -Text $Tenant)'." $null $false 'other-tenant'
    }

    if (-not [System.String]::Equals($json.Filter, $Filter, [System.StringComparison]::Ordinal)) {
        $was = if ($json.Filter) { $json.Filter } else { '(none)' }
        $is = if ($Filter) { $Filter } else { '(none)' }
        return & $result $true $false "The filter changed (it was $was, it is $is)." $null $false 'other-filter'
    }

    if (-not [System.String]::Equals($json.Options, $Options, [System.StringComparison]::Ordinal)) {
        return & $result $true $false "The way the sites are asked changed (it was $($json.Options), it is $Options)." $null $false 'other-options'
    }

    $started = ConvertFrom-SPSLifecycleCheckpointDate -Text $json.StartedOn
    $updated = ConvertFrom-SPSLifecycleCheckpointDate -Text $json.UpdatedOn
    $age = $Now.ToUniversalTime() - $started
    if ($age.TotalMinutes -lt -5 -or ($updated - $Now.ToUniversalTime()).TotalMinutes -gt 5) {
        return & $result $true $false 'The checkpoint is dated in the future (was the clock of this machine set back?), so it is not trusted.' $null $false 'clock'
    }

    if ($updated -lt $started) {
        return & $result $true $false 'The dates of the checkpoint are not in order (the last update is before the start: was the clock of this machine set back while the listing ran?), so it is not trusted.' $null $false 'clock'
    }

    if ($age.TotalHours -gt $MaxAgeHours) {
        return & $result $true $false ('The checkpoint is {0} hours old, more than the {1} hours that a listing stays true.' -f $age.TotalHours.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $MaxAgeHours.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)) $null $false 'too-old'
    }

    foreach ($page in @($json.Pages)) {
        $pagePath = Join-Path -Path $fullFolder -ChildPath $page.File
        if (-not (Test-Path -LiteralPath $pagePath -PathType Leaf)) {
            return & $result $true $false "The checkpoint is damaged: the page $($page.Number) is missing." $null $false 'damaged'
        }

        if (-not [System.String]::Equals((Get-FileHash -LiteralPath $pagePath -Algorithm SHA256).Hash.ToLowerInvariant(), $page.Sha256, [System.StringComparison]::Ordinal)) {
            return & $result $true $false "The checkpoint is damaged: the page $($page.Number) was changed (its hash is not the one that was saved)." $null $false 'damaged'
        }
    }

    $manifest = [PSCustomObject][ordered]@{
        Version         = 1
        State           = 'Running'
        Tenant          = $json.Tenant
        Filter          = $json.Filter
        Options         = $json.Options
        StartedOn       = $json.StartedOn
        UpdatedOn       = $json.UpdatedOn
        FinishedOn      = ''
        ListingComplete = $json.ListingComplete
        NextToken       = $json.NextToken
        Pages           = [System.Collections.Generic.List[System.Object]]::new()
    }
    foreach ($page in @($json.Pages)) {
        $manifest.Pages.Add([PSCustomObject][ordered]@{
                Number  = [System.Int32]$page.Number
                File    = $page.File
                Token   = $page.Token
                NextToken = $page.NextToken
                Read    = [System.Int32]$page.Read
                Sites   = [System.Int32]$page.Sites
                Sha256  = $page.Sha256
                Seconds = [System.Double]$page.Seconds
            })
    }

    & $result $true $true '' $manifest
}
