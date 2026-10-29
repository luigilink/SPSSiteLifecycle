function Get-SPSLifecycleCsvDelimiter {
    <#
        .SYNOPSIS
        Finds the separator of a CSV text and removes the "sep=" line that Excel may add.

        .DESCRIPTION
        A first line such as sep=; names the separator and is dropped from the text (FirstLine is then 2, the
        number of the line where the text starts). Otherwise the
        header line decides: the separator among comma, semicolon and tab that gives the most
        fields wins (the comma on a tie, and when the header has a single column).

        .PARAMETER Text
        The decoded content of the file.

        .EXAMPLE
        Get-SPSLifecycleCsvDelimiter -Text "Url;LockedOn`r`nhttps://contoso.sharepoint.com/sites/a;2025-09-18"
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Text
    )

    $content = $Text.TrimStart([System.Char]0xFEFF)

    $explicit = [System.Text.RegularExpressions.Regex]::Match($content, '^sep=([^\r\n])\r?\n')
    if ($explicit.Success) {
        return [PSCustomObject]@{
            Delimiter = [System.Char]$explicit.Groups[1].Value
            Text      = $content.Substring($explicit.Length)
            FirstLine = 2
        }
    }

    $head = $content.Substring(0, [System.Math]::Min(65536, $content.Length))
    $firstLine = $head -split "\r\n|\n|\r" | Where-Object { $_.Trim() } | Select-Object -First 1

    $best = [System.Char]','
    if ($firstLine) {
        $bestCount = 1
        foreach ($candidate in @([System.Char]',', [System.Char]';', [System.Char]"`t")) {
            $count = @(Split-SPSLifecycleCsvLine -Line $firstLine -Delimiter $candidate).Count
            if ($count -gt $bestCount) {
                $best = $candidate
                $bestCount = $count
            }
        }
    }

    [PSCustomObject]@{
        Delimiter = $best
        Text      = $content
        FirstLine = 1
    }
}
