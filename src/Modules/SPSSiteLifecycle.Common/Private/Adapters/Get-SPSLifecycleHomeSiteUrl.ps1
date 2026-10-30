function Get-SPSLifecycleHomeSiteUrl {
    <#
        .SYNOPSIS
        Reads the address of the SharePoint home site of the tenant, which the tool never touches.

        .DESCRIPTION
        The home site is protected (see Test-SPSLifecycleProtectedSite), and nothing in the listing of the sites says which
        one it is, so the Scan asks the tenant, once a run, with Get-PnPHomeSite (a read, like the listing).

        A tenant that has no home site gives an empty text. An answer that is not the web address of a site, with https, stops
        the run, and so does a failure to read: a home site that is not recognized would be listed like the others, and
        suggested for deletion.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .EXAMPLE
        Get-SPSLifecycleHomeSiteUrl -Session $session
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session
    )

    try {
        $answer = @(Get-PnPHomeSite -Connection $Session.Connection -ErrorAction Stop)
    }
    catch {
        throw "The home site of the tenant could not be read: $($_.Exception.Message.Trim().TrimEnd('.')). The tool stops: the home site is never touched, and it cannot be recognized without its address."
    }

    if ($answer.Count -eq 0) {
        return ''
    }

    if ($answer.Count -eq 1) {
        $value = $answer[0]
        if ($null -eq $value) {
            return ''
        }

        if ($value -is [System.String]) {
            $text = $value.Trim()
            if (-not $text) {
                return ''
            }

            if ($text -match '^https://' -and (Test-SPSLifecycleWebAddress -Text $text)) {
                return $text
            }
        }
    }

    $shown = ConvertTo-SPSLifecycleVisibleText -Text "$($answer -join ' ')"
    if ($shown.Length -gt 100) {
        $shown = "$($shown.Substring(0, 100))..."
    }

    throw "The answer of the tenant about its home site is not the web address of a site, with https ('$shown'). The tool stops: a home site that is not recognized would be listed like any other site."
}
