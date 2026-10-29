function ConvertTo-SPSLifecycleUrlKey {
    <#
        .SYNOPSIS
        Normalizes a site URL so that two spellings of the same URL compare equal.

        .DESCRIPTION
        Trims the text, removes the trailing slashes and lowercases it. The result is used as a
        hashtable key to match the sites of a list, a report and the tenant listing. A null or
        empty value gives an empty string.

        .PARAMETER Url
        The URL to normalize.

        .EXAMPLE
        ConvertTo-SPSLifecycleUrlKey -Url 'https://Contoso.sharepoint.com/sites/Sales/'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Url
    )

    process {
        "$Url".Trim().TrimEnd('/').ToLowerInvariant()
    }
}
