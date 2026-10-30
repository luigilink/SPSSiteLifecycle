function Test-SPSLifecycleNotFoundMessage {
    <#
        .SYNOPSIS
        Tells whether the message of a read that failed says that the site or the group is not there.

        .DESCRIPTION
        A site that is not there and a read that failed (throttling, access denied, a network that is down) are not the
        same thing, and the Act phase treats them differently: the first is a verdict that leaves the site alone, the second
        is an error that the loop counts for its stop after 3 in a row. Only the messages that the tenant is known to give
        for a thing that does not exist are taken for it: PnP.PowerShell writes "failed with status code NotFound" for an
        answer 404 of Microsoft Graph, Graph writes Request_ResourceNotFound, and the admin API of SharePoint writes
        "Cannot get site" for an address that is not a site. Any other message is an error.

        The list has not been checked against a tenant (the lab is the first run, see #15), and a message that it does not
        know is read as an error: that never leads to an action. A message that it knew wrongly would give a verdict that
        leaves the site alone, which does not either.

        .PARAMETER Message
        The message of the error.

        .EXAMPLE
        Test-SPSLifecycleNotFoundMessage -Message $_.Exception.Message
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Message
    )

    if ([System.String]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    foreach ($pattern in @('failed with status code NotFound', 'Request_ResourceNotFound', '\(404\) Not Found', '\bCannot get site\b')) {
        if ([System.Text.RegularExpressions.Regex]::IsMatch($Message, $pattern, $options)) {
            return $true
        }
    }

    $false
}
