function Test-SPSLifecycleTenantName {
    <#
        .SYNOPSIS
        Tells whether a text is the name of a tenant: letters of ASCII, digits and hyphens, and nothing else.

        .DESCRIPTION
        The rule is the one of the TenantName setting (see Get-SPSLifecycleSettingSchema), matched as it is written: one
        character at a time, with no case folding and no culture. The regular expression engine folds the case beyond ASCII
        when it is asked to ignore it, so [a-z] would also accept the Kelvin sign (U+212A) and a capital I with a dot above
        (U+0130), which read as a k and an i and are not the letters of a tenant. The settings are checked with the rule
        when they are read, and the check right before the sign-in uses it again.

        .PARAMETER Name
        The text to check.

        .EXAMPLE
        Test-SPSLifecycleTenantName -Name 'contoso'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    $row = @(Get-SPSLifecycleSettingSchema | Where-Object { [System.String]::Equals($_.Name, 'TenantName', [System.StringComparison]::Ordinal) })[0]
    [System.Text.RegularExpressions.Regex]::IsMatch("$Name", $row.Pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}
