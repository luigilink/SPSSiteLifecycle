function Get-SPSLifecycleListingFilter {
    <#
        .SYNOPSIS
        Gives the filter that the SharePoint admin API applies on the server when the Scan lists the sites.

        .DESCRIPTION
        The server filters the listing on one property at a time, and the lock state is the one that matters: with
        ReadOnly alone, the lab (10,030 sites) gave its 9 read-only sites in 7 pages and 8.8 s, against 36 s for the
        whole listing (D7), and a page that holds none of them comes back empty. With a single lock state the filter
        is LockState -eq 'ReadOnly'. With several, there is no filter and the Scan core leaves out the sites whose
        lock state it does not list, which it does in any case.

        The text goes to the server as it is. A state is therefore one that the server knows (ReadOnly, Unlock or
        NoAccess, written as the server writes it, whatever the case and the culture), and nothing else.

        .PARAMETER LockState
        The lock states that the Scan lists (the Scan.LockStates setting).

        .EXAMPLE
        Get-SPSLifecycleListingFilter -LockState 'ReadOnly'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.String[]]
        $LockState
    )

    if (@($LockState).Count -eq 0) {
        throw 'Give at least one lock state: a Scan that asks for none lists nothing.'
    }

    $known = @('ReadOnly', 'Unlock', 'NoAccess')
    $states = [System.Collections.Generic.List[System.String]]::new()
    foreach ($state in $LockState) {
        $canonical = $null
        foreach ($name in $known) {
            if ([System.String]::Equals("$state", $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $canonical = $name
                break
            }
        }

        if ($null -eq $canonical) {
            throw "'$(ConvertTo-SPSLifecycleVisibleText -Text "$state")' is not a lock state that the server knows ($($known -join ', '))."
        }

        if (-not $states.Contains($canonical)) {
            $states.Add($canonical)
        }
    }

    if ($states.Count -eq 1) {
        return "LockState -eq '$($states[0])'"
    }

    ''
}
