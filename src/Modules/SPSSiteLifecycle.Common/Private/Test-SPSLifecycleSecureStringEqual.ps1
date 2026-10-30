function Test-SPSLifecycleSecureStringEqual {
    <#
        .SYNOPSIS
        Tells whether two SecureStrings hold the same text, without making a managed string of either.

        .DESCRIPTION
        NetworkCredential.Password would make a plain string of each, which cannot be zeroed and stays in memory until the garbage collector
        takes it. The two are read into unmanaged buffers, compared character by character (the whole length, whatever the first difference,
        so that the time does not tell where it is), and the buffers are zeroed and freed.

        .PARAMETER First
        The first SecureString.

        .PARAMETER Second
        The second SecureString.

        .EXAMPLE
        Test-SPSLifecycleSecureStringEqual -First $a -Second $b
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $First,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $Second
    )

    if ($First.Length -ne $Second.Length) {
        return $false
    }

    $a = [System.IntPtr]::Zero
    $b = [System.IntPtr]::Zero
    try {
        $a = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($First)
        $b = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
        $difference = 0
        for ($index = 0; $index -lt $First.Length; $index++) {
            $difference = $difference -bor ([System.Runtime.InteropServices.Marshal]::ReadInt16($a, 2 * $index) -bxor [System.Runtime.InteropServices.Marshal]::ReadInt16($b, 2 * $index))
        }

        $difference -eq 0
    }
    finally {
        if ($a -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($a)
        }

        if ($b -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
        }
    }
}
