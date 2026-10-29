function Split-SPSLifecycleCsvLine {
    <#
        .SYNOPSIS
        Splits one line of a CSV file into its fields, respecting the double quotes.

        .DESCRIPTION
        Used to detect the separator of a file and to read the header of a file that has no row.
        A delimiter inside double quotes does not split, and two double quotes inside a quoted
        field stand for one.

        .PARAMETER Line
        The line to split.

        .PARAMETER Delimiter
        The separator character.

        .EXAMPLE
        Split-SPSLifecycleCsvLine -Line 'Url;"A;B";LockedOn' -Delimiter ';'
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Line,

        [Parameter(Mandatory = $true)]
        [System.Char]
        $Delimiter
    )

    $fields = [System.Collections.Generic.List[System.String]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuotes = $false

    for ($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if ($inQuotes) {
            if ($character -eq '"') {
                if (($index + 1) -lt $Line.Length -and $Line[$index + 1] -eq '"') {
                    $null = $current.Append('"')
                    $index++
                }
                else {
                    $inQuotes = $false
                }
            }
            else {
                $null = $current.Append($character)
            }
        }
        elseif ($character -eq '"') {
            $inQuotes = $true
        }
        elseif ($character -eq $Delimiter) {
            $fields.Add($current.ToString())
            $null = $current.Clear()
        }
        else {
            $null = $current.Append($character)
        }
    }

    $fields.Add($current.ToString())
    $fields.ToArray()
}
