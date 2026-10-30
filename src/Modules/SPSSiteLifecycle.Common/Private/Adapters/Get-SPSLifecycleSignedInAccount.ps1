function Get-SPSLifecycleSignedInAccount {
    <#
        .SYNOPSIS
        Reads the account that signed in, as an e-mail address, from the token of the connection.

        .DESCRIPTION
        A read: Get-PnPAccessToken -Decoded for SharePoint, and the first of the claims upn, unique_name, preferred_username and
        email that is written as an e-mail address. The Act phase adds this account to the administrators of the site collection
        before an archive (GrantSiteAdmin). It throws when the token could not be read, or when no claim is an address: the
        account that signed in cannot be told, and nothing is guessed.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .EXAMPLE
        Get-SPSLifecycleSignedInAccount -Session $session
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
        $token = Get-PnPAccessToken -Decoded -ResourceTypeName SharePoint -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The account that signed in could not be read from the token: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }

    $claims = @($token.Claims)
    foreach ($type in 'upn', 'unique_name', 'preferred_username', 'email') {
        foreach ($claim in $claims) {
            if ([System.String]::Equals("$($claim.Type)", $type, [System.StringComparison]::Ordinal)) {
                $value = "$($claim.Value)"
                if ([System.Text.RegularExpressions.Regex]::IsMatch($value, '\A[^@\s,;\p{Cc}\p{Cf}\p{Z}]+@[^@\s,;\p{Cc}\p{Cf}\p{Z}]+\.[^@\s,;\p{Cc}\p{Cf}\p{Z}]+\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
                    return $value
                }
            }
        }
    }

    throw 'The account that signed in cannot be told: no claim of the token (upn, unique_name, preferred_username, email) is an e-mail address, and the tool does not guess it.'
}
