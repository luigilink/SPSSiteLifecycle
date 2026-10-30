function Get-SPSLifecycleTenantId {
    <#
        .SYNOPSIS
        Reads the ID of a Microsoft Entra tenant from the public OpenID configuration of its initial domain.

        .DESCRIPTION
        A read of one public address, https://login.microsoftonline.com/<domain>/.well-known/openid-configuration, which needs no sign-in
        and holds no secret: the endpoints in it carry the ID of the tenant (a GUID). The certificate sign-in of the tool asks for that ID
        (TenantId), and the setup script reads it so that a person does not have to look for it. The domain must be the initial domain of
        a tenant (<name>.onmicrosoft.com, ASCII): nothing else is put in the address. It throws when the call fails or when the answer
        holds no ID (a GUID that is not all zeros), and gives the ID in lowercase.

        .PARAMETER TenantDomain
        The initial domain of the tenant, contoso.onmicrosoft.com.

        .EXAMPLE
        Get-SPSLifecycleTenantId -TenantDomain contoso.onmicrosoft.com
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $TenantDomain
    )

    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($TenantDomain, '\A[a-z0-9][a-z0-9-]{0,62}\.onmicrosoft\.com\z', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "'$(ConvertTo-SPSLifecycleVisibleText -Text $TenantDomain -AsciiOnly)' is not the initial domain of a tenant (<name>.onmicrosoft.com, in lowercase)."
    }

    $address = "https://login.microsoftonline.com/$TenantDomain/.well-known/openid-configuration"
    try {
        $configuration = Invoke-RestMethod -Uri $address -Method Get -TimeoutSec 20 -ErrorAction Stop
    }
    catch {
        throw "The ID of the tenant could not be read from $address ($($_.Exception.Message.Trim().TrimEnd('.')))."
    }

    foreach ($name in 'token_endpoint', 'issuer', 'authorization_endpoint') {
        $property = if ($null -ne $configuration -and $configuration -isnot [System.String]) { $configuration.PSObject.Properties[$name] } else { $null }
        $text = if ($null -ne $property) { "$($property.Value)" } else { '' }
        $match = [System.Text.RegularExpressions.Regex]::Match($text, '/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})(?:/|\z)', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if ($match.Success) {
            $guid = [System.Guid]::Parse($match.Groups[1].Value)
            if ($guid -ne [System.Guid]::Empty) {
                return $guid.ToString()
            }
        }
    }

    throw "The answer of $address holds no tenant ID."
}
