function Add-SPSLifecycleSiteAdmin {
    <#
        .SYNOPSIS
        Adds an account to the administrators of a site collection. This changes the tenant.

        .DESCRIPTION
        One operation: Set-PnPTenantSite -Owners, which adds the account and leaves the administrators that the site has. An
        archive of a read-only site works when the signed-in administrator already is an administrator of the site collection
        (lab, 27 October 2026); a read-only site refuses the change of owners, so the caller unlocks the site first. The account
        must be written as an e-mail address, on one line. The target is checked first (see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER Url
        The address of the site.

        .PARAMETER Account
        The account to add, as an e-mail address.

        .EXAMPLE
        Add-SPSLifecycleSiteAdmin -Session $session -Url $url -Account 'admin@contoso.example'
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Url,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Account
    )

    Assert-SPSLifecycleWriteTarget -Session $Session -Url $Url

    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($Account, '\A[^@\s,;\p{Cc}\p{Cf}\p{Z}]+@[^@\s,;\p{Cc}\p{Cf}\p{Z}]+\.[^@\s,;\p{Cc}\p{Cf}\p{Z}]+\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "The account '$(ConvertTo-SPSLifecycleVisibleText -Text $Account)' is not the address of an account (one e-mail address, without a space or a hidden character)."
    }

    if (-not $PSCmdlet.ShouldProcess($Url, "Add $Account to the administrators of the site collection")) {
        return
    }

    $owners = [System.Collections.Generic.List[System.String]]::new()
    $owners.Add($Account)
    try {
        $null = Set-PnPTenantSite -Identity $Url -Owners $owners -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The administrator '$Account' of the site '$Url' could not be added: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }
}
