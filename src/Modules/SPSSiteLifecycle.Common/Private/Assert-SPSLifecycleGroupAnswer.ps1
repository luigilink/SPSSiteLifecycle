function Assert-SPSLifecycleGroupAnswer {
    <#
        .SYNOPSIS
        Stops when what the tenant gave for a group is not the one group that was asked for.

        .DESCRIPTION
        The state of a group is read from the answer of a call that was meant for one group. An answer with several groups, a
        group without an ID, or the ID of another group could be a call that did not do what it was asked, and the state that
        it would give for the site would be the state of something else: the state of the group of the site cannot be told, and
        the function stops.

        .PARAMETER Answer
        What the call gave, without the empty values.

        .PARAMETER GroupId
        The ID that was asked for, as a lowercase GUID text.

        .EXAMPLE
        Assert-SPSLifecycleGroupAnswer -Answer $answer -GroupId $id
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Answer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $GroupId
    )

    if ($Answer.Count -ne 1) {
        throw "The tenant gave $($Answer.Count) groups for the group $GroupId, so the state of the group of the site cannot be told."
    }

    $given = ConvertTo-SPSLifecycleId -Value $Answer[0].Id
    if (-not $given) {
        throw "The tenant gave a group with no usable ID for the group $GroupId, so the state of the group of the site cannot be told."
    }

    if ($given -ne $GroupId) {
        throw "The tenant gave another group than the one that was asked for ($GroupId), so the state of the group of the site cannot be told."
    }
}
