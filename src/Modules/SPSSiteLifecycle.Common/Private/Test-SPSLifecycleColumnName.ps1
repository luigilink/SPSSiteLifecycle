function Test-SPSLifecycleColumnName {
    <#
        .SYNOPSIS
        Tells whether a list of column names holds a column, comparing the names the way a row finds its properties.

        .DESCRIPTION
        PowerShell compares text with the rules of a culture: -contains and Group-Object ignore the characters
        that a culture treats as ignorable (a soft hyphen, a zero-width space), so a header named Site<U+00AD>Id
        is "the same" as SiteId, but the row that ConvertFrom-Csv builds has no SiteId property, and the value
        is silently empty. A lock date that loses its site ID is attributed to an address instead of a site.

        This function compares the names one character at a time, with no regard for the case and no regard
        for the culture: the way a hashtable or a row finds a name. Use it for every question of the kind "does
        this file have this column".

        .PARAMETER Name
        The names of the columns of the file.

        .PARAMETER Column
        The name that is wanted.

        .EXAMPLE
        Test-SPSLifecycleColumnName -Name $rows[0].PSObject.Properties.Name -Column 'SiteId'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.String[]]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Column
    )

    foreach ($candidate in @($Name)) {
        if ([System.String]::Equals($candidate, $Column, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $false
}
