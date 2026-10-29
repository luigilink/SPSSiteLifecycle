function Test-SPSLifecycleArchivableTemplate {
    <#
        .SYNOPSIS
        Tells whether Microsoft 365 Archive supports a site template.

        .PARAMETER Template
        The template of the site, for example GROUP#0 (the case is ignored).

        .EXAMPLE
        Test-SPSLifecycleArchivableTemplate -Template 'GROUP#0'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Template
    )

    $name = "$Template".Trim()
    if (-not $name) {
        return $false
    }

    @(Get-SPSLifecycleArchivableTemplate | Where-Object { $_.Template -ieq $name }).Count -gt 0
}
