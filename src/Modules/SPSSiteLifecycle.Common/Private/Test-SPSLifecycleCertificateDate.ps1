function Test-SPSLifecycleCertificateDate {
    <#
        .SYNOPSIS
        Says whether a certificate can sign in now, from its two dates: valid, ending soon, expired or not valid yet.

        .DESCRIPTION
        A pure function. Expired: the certificate ends now or has ended (checked first: a certificate that ended is of no use whatever its
        start). NotYetValid: it starts later. Soon: it ends in less than WarningDays days (30 by default: exactly 30 is still valid), and the
        message says how many days are left, the date, and to add a new certificate to the app before then. Valid: anything else, with no
        message. The dates are read in UTC, whatever their kind.

        .PARAMETER NotBefore
        The start of the validity.

        .PARAMETER NotAfter
        The end of the validity.

        .PARAMETER Now
        The time, in UTC. Default: now.

        .PARAMETER WarningDays
        The number of days before the end from which the certificate is Soon. Default: 30.

        .EXAMPLE
        Test-SPSLifecycleCertificateDate -NotBefore $certificate.NotBefore -NotAfter $certificate.NotAfter
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $NotBefore,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $NotAfter,

        [Parameter()]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow,

        [Parameter()]
        [System.Int32]
        $WarningDays = 30
    )

    $start = ConvertTo-SPSLifecycleUtcDateTime -Value $NotBefore
    $end = ConvertTo-SPSLifecycleUtcDateTime -Value $NotAfter
    $current = ConvertTo-SPSLifecycleUtcDateTime -Value $Now
    $date = [System.Globalization.CultureInfo]::InvariantCulture
    $state = 'Valid'
    $message = ''
    $left = $end - $current

    if ($end -le $current) {
        $state = 'Expired'
        $message = "The certificate expired on $($end.ToString('yyyy-MM-dd', $date)): the sign-in would fail. Make a new one, add it to the app, and put it in the settings (see the App-Registration page of the wiki)."
    }
    elseif ($start -gt $current) {
        $state = 'NotYetValid'
        $message = "The certificate is not valid before $($start.ToString('yyyy-MM-dd HH:mm', $date)) (UTC): the sign-in would fail until then."
    }
    elseif ($left -lt [System.TimeSpan]::FromDays($WarningDays)) {
        $state = 'Soon'
        $days = [System.Int32][System.Math]::Floor($left.TotalDays)
        $unit = if ($days -eq 1) { 'day' } else { 'days' }
        $message = "The certificate ends in $days $unit (on $($end.ToString('yyyy-MM-dd', $date))): add a new one to the app before then (see the App-Registration page of the wiki)."
    }

    [PSCustomObject][ordered]@{
        State    = $state
        DaysLeft = [System.Int32][System.Math]::Floor($left.TotalDays)
        Message  = $message
    }
}
