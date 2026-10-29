function ConvertTo-SPSLifecycleId {
    <#
        .SYNOPSIS
        Normalizes a site ID or a group ID to a lowercase GUID string.

        .DESCRIPTION
        Accepts a GUID object or text, with or without braces. Returns the lowercase GUID text, or
        an empty string when the value is empty, is not a GUID, or is the all-zero GUID that the
        usage reports show when names are concealed.

        .PARAMETER Value
        The value to normalize.

        .EXAMPLE
        ConvertTo-SPSLifecycleId -Value '{A6E20079-2D1A-4E9D-BC9F-94E3F2EFEB64}'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Value
    )

    process {
        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse("$Value".Trim(), [ref]$guid) -and $guid -ne [System.Guid]::Empty) {
            return $guid.ToString()
        }

        ''
    }
}
