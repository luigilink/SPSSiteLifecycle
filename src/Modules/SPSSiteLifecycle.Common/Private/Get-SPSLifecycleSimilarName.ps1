function Get-SPSLifecycleSimilarName {
    <#
        .SYNOPSIS
        Finds the name in a list that is closest to a mistyped one.

        .DESCRIPTION
        Used to help with a typo in a settings file ("did you mean ..."). The comparison ignores the
        case. A name is suggested only when it is at most two edits away, or when it is the same name
        with a different case. Returns an empty string when nothing is close enough.

        .PARAMETER Name
        The name that was written.

        .PARAMETER Candidate
        The valid names.

        .EXAMPLE
        Get-SPSLifecycleSimilarName -Name 'MaxAction' -Candidate 'MaxActions', 'Execute'
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Candidate
    )

    $source = $Name.ToLowerInvariant()
    $best = ''
    $bestDistance = 3

    foreach ($item in $Candidate) {
        $target = $item.ToLowerInvariant()
        $previous = 0..$target.Length
        for ($row = 1; $row -le $source.Length; $row++) {
            $current = [System.Int32[]]::new($target.Length + 1)
            $current[0] = $row
            for ($column = 1; $column -le $target.Length; $column++) {
                $cost = if ($source[$row - 1] -eq $target[$column - 1]) { 0 } else { 1 }
                $current[$column] = [System.Math]::Min([System.Math]::Min($current[$column - 1] + 1, $previous[$column] + 1), $previous[$column - 1] + $cost)
            }

            $previous = $current
        }

        $distance = $previous[$target.Length]
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $best = $item
        }
    }

    $best
}
