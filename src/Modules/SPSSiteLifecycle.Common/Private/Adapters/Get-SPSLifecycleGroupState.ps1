function Get-SPSLifecycleGroupState {
    <#
        .SYNOPSIS
        Reads the state of the Microsoft 365 group of a site, as it is now, for the Act phase.

        .DESCRIPTION
        This is a read, through the cmdlets of PnP.PowerShell for the groups (Microsoft Graph, Group.Read.All). It gives:

        - None, without asking anyone, for a site that has no group (an empty ID, or the all-zero ID that the tenant gives);
        - Active, when the group is there (Get-PnPMicrosoft365Group, which gives nothing for a group that is not there);
        - SoftDeleted, when it is not there but is in the recycle bin of the groups (Get-PnPDeletedMicrosoft365Group);
        - NotFound, when it is in neither.

        The group is asked for by its ID as a GUID, never by a name, and the group that the tenant gives must be the one that was
        asked for (its ID is checked): another group, no ID, or several groups stop the function, because the state of the group
        of the site could not be told. So does any failure to read, except the answer that a group is not there (see
        Test-SPSLifecycleNotFoundMessage): a state that was not read is never a state.

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER GroupId
        The ID of the group, as the tenant gives it for the site.

        .EXAMPLE
        Get-SPSLifecycleGroupState -Session $session -GroupId $site.GroupId
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $GroupId
    )

    $id = ConvertTo-SPSLifecycleId -Value $GroupId
    if (-not $id) {
        return 'None'
    }

    $guid = [System.Guid]::Parse($id)

    try {
        $active = @(Get-PnPMicrosoft365Group -Identity $guid -Connection $Session.Connection -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
    catch {
        throw "The Microsoft 365 group $id could not be read: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }

    if ($active.Count -gt 0) {
        Assert-SPSLifecycleGroupAnswer -Answer $active -GroupId $id
        return 'Active'
    }

    try {
        $deleted = @(Get-PnPDeletedMicrosoft365Group -Identity $guid -Connection $Session.Connection -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
    catch {
        if (Test-SPSLifecycleNotFoundMessage -Message $_.Exception.Message) {
            return 'NotFound'
        }

        throw "The recycle bin of the Microsoft 365 groups could not be read for the group $id`: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }

    if ($deleted.Count -gt 0) {
        Assert-SPSLifecycleGroupAnswer -Answer $deleted -GroupId $id
        return 'SoftDeleted'
    }

    'NotFound'
}
