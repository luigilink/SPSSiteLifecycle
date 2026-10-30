function Assert-SPSLifecycleAppTarget {
    <#
        .SYNOPSIS
        Stops, right before an app is registered, when the tenant is one that the tool refuses or the name of the app is not valid.

        .DESCRIPTION
        The setup script checks its inputs first, and the adapter that registers the app checks again with this function, whatever the
        caller did: the registration creates an object in a tenant, and it is never done in a tenant that the tool refuses. It uses the
        rules of the settings (see Assert-SPSLifecycleTenantAllowed): the name of the tenant is ASCII, read one character at a time, and
        it is not microsoft or microsoftonline in any case.

        .PARAMETER TenantName
        The name of the tenant (contoso for contoso.sharepoint.com).

        .PARAMETER ApplicationName
        The name of the app.

        .EXAMPLE
        Assert-SPSLifecycleAppTarget -TenantName contoso -ApplicationName SPSSiteLifecycle
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $TenantName,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $ApplicationName
    )

    $name = "$TenantName".Trim()
    Assert-SPSLifecycleTenantAllowed -Setting ([PSCustomObject]@{ TenantName = $name; AdminUrl = "https://$name-admin.sharepoint.com"; RefusedTenants = @() })

    if (-not (Test-SPSLifecycleAppName -Name $ApplicationName)) {
        throw "ApplicationName: '$(ConvertTo-SPSLifecycleVisibleText -Text "$ApplicationName" -AsciiOnly)' is not a valid name: use 1 to 64 letters, digits, dots, dashes or underscores, starting with a letter or a digit, and not the name of a Windows device (CON, NUL, COM1...). It is also the name of the certificate files."
    }
}
