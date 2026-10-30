function Get-SPSLifecycleListingManifestProblem {
    <#
        .SYNOPSIS
        Tells what is wrong with a manifest that was read from a checkpoint, or gives an empty text when nothing is.

        .DESCRIPTION
        A manifest is the tool's own file, and the tool reads it strictly: the properties are exactly the ones that
        Initialize-SPSLifecycleListingManifest gives, each of the right type, the dates in the form of
        ConvertTo-SPSLifecycleCheckpointDate (a date that a JSON reader has already turned into a date was written by
        someone else), the pages numbered from 1 without a gap and named after their number (a name that could leave
        the folder is never followed), the counts and the hashes plausible, and the state consistent: a listing that is
        complete has no token to go on with, and a listing that is not complete and has pages has one.

        .PARAMETER Manifest
        What ConvertFrom-Json gave for manifest.json.

        .EXAMPLE
        Get-SPSLifecycleListingManifestProblem -Manifest $json
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Manifest
    )

    if ($Manifest -isnot [System.Management.Automation.PSCustomObject]) {
        return 'the manifest is not a JSON object.'
    }

    $expected = @('Version', 'State', 'Tenant', 'Filter', 'Options', 'StartedOn', 'UpdatedOn', 'FinishedOn', 'ListingComplete', 'NextToken', 'Pages')
    $names = @($Manifest.PSObject.Properties.Name)
    foreach ($name in $expected) {
        if ($names -cnotcontains $name) {
            return "the property '$name' is missing."
        }
    }

    foreach ($name in $names) {
        if ($expected -cnotcontains $name) {
            return "the property '$(ConvertTo-SPSLifecycleVisibleText -Text $name)' is not one that the tool writes."
        }
    }

    foreach ($name in 'State', 'Tenant', 'Filter', 'Options', 'StartedOn', 'UpdatedOn', 'FinishedOn', 'NextToken') {
        if ($Manifest.$name -isnot [System.String]) {
            return "the value of '$name' is not a text."
        }
    }

    if (-not [System.String]::Equals($Manifest.State, 'Running', [System.StringComparison]::Ordinal) -and -not [System.String]::Equals($Manifest.State, 'Completed', [System.StringComparison]::Ordinal)) {
        return "the state '$(ConvertTo-SPSLifecycleVisibleText -Text $Manifest.State)' is not one that the tool writes (Running or Completed)."
    }

    foreach ($name in 'StartedOn', 'UpdatedOn') {
        if ($null -eq (ConvertFrom-SPSLifecycleCheckpointDate -Text $Manifest.$name)) {
            return "the value of '$name' is not a date that the tool writes."
        }
    }

    if ($Manifest.FinishedOn -ne '' -and $null -eq (ConvertFrom-SPSLifecycleCheckpointDate -Text $Manifest.FinishedOn)) {
        return "the value of 'FinishedOn' is not a date that the tool writes."
    }

    if ($Manifest.ListingComplete -isnot [System.Boolean]) {
        return "the value of 'ListingComplete' is not true or false."
    }

    if ($Manifest.Pages -isnot [System.Array]) {
        return "the value of 'Pages' is not a list."
    }

    $pages = @($Manifest.Pages)
    $entryNames = @('Number', 'File', 'Token', 'NextToken', 'Read', 'Sites', 'Sha256', 'Seconds')
    for ($index = 0; $index -lt $pages.Count; $index++) {
        $page = $pages[$index]
        $label = "page $($index + 1)"
        if ($page -isnot [System.Management.Automation.PSCustomObject]) {
            return "the entry of $label is not an object."
        }

        $pageNames = @($page.PSObject.Properties.Name)
        foreach ($name in $entryNames) {
            if ($pageNames -cnotcontains $name) {
                return "the entry of $label lacks '$name'."
            }
        }

        foreach ($name in $pageNames) {
            if ($entryNames -cnotcontains $name) {
                return "the entry of $label has a property that the tool does not write ('$(ConvertTo-SPSLifecycleVisibleText -Text $name)')."
            }
        }

        foreach ($name in 'Number', 'Read', 'Sites') {
            if (($page.$name -isnot [System.Int32] -and $page.$name -isnot [System.Int64]) -or $page.$name -lt 0) {
                return "the value of '$name' in $label is not a whole number that is zero or more."
            }
        }

        if ($page.Number -ne ($index + 1)) {
            return "the pages are not numbered from 1 without a gap ($label is numbered $($page.Number))."
        }

        if ($page.File -isnot [System.String] -or -not [System.String]::Equals($page.File, ('page-{0}.csv' -f ($index + 1).ToString('D6', [System.Globalization.CultureInfo]::InvariantCulture)), [System.StringComparison]::Ordinal)) {
            return "the file of $label is not the one that the tool names after its number."
        }

        if ($page.Token -isnot [System.String]) {
            return "the token of $label is not a text."
        }

        if ($page.NextToken -isnot [System.String]) {
            return "the next token of $label is not a text."
        }

        if ($index -eq 0) {
            if ($page.Token.Length -ne 0) {
                return "the first page was not asked with the first token (an empty one), but with '$(ConvertTo-SPSLifecycleVisibleText -Text $page.Token)'."
            }
        }
        elseif (-not [System.String]::Equals($page.Token, $pages[$index - 1].NextToken, [System.StringComparison]::Ordinal)) {
            return "the token of $label is not the one that page $index gave."
        }

        if ($page.Sites -gt $page.Read) {
            return "$label kept more sites than it read."
        }

        if ($page.Sha256 -isnot [System.String] -or -not [System.Text.RegularExpressions.Regex]::IsMatch($page.Sha256, '\A[0-9a-f]{64}\z')) {
            return "the hash of $label is not a SHA-256 in lowercase hexadecimal."
        }

        if (($page.Seconds -isnot [System.Double] -and $page.Seconds -isnot [System.Int32] -and $page.Seconds -isnot [System.Int64]) -or $page.Seconds -lt 0) {
            return "the time of $label is not a number of seconds."
        }
    }

    if ($Manifest.ListingComplete -and $Manifest.NextToken.Length -ne 0) {
        return 'the listing is complete and still has a token to go on with.'
    }

    if ([System.String]::Equals($Manifest.State, 'Running', [System.StringComparison]::Ordinal) -and $Manifest.ListingComplete -and $pages.Count -eq 0) {
        return 'the listing is running, complete, and lists no page (a listing that is not finished always has read at least one, even for a tenant of no site).'
    }

    # The first page is asked with no token, so a listing that has saved no page has none to go on with: a token without a page
    # would be asked as it is, and the pages before it would be lost without anything saying so.
    if ($pages.Count -eq 0 -and $Manifest.NextToken.Length -ne 0) {
        return 'the listing has no page and still has a token to go on with.'
    }

    if (-not $Manifest.ListingComplete -and $pages.Count -gt 0 -and $Manifest.NextToken.Length -eq 0) {
        return 'the listing is not complete and has no token to go on with.'
    }

    if ([System.String]::Equals($Manifest.State, 'Completed', [System.StringComparison]::Ordinal) -and -not $Manifest.ListingComplete) {
        return 'the listing is marked finished and is not complete.'
    }

    if ($pages.Count -gt 0 -and -not [System.String]::Equals($pages[$pages.Count - 1].NextToken, $Manifest.NextToken, [System.StringComparison]::Ordinal)) {
        return 'the token to go on with is not the one that the last page gave.'
    }

    ''
}
