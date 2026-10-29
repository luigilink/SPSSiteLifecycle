function ConvertFrom-SPSLifecycleCsvByte {
    <#
        .SYNOPSIS
        Decodes the bytes of a CSV file to text, whatever the program that saved it.

        .DESCRIPTION
        A byte order mark decides: UTF-8 (EF BB BF), UTF-16 little endian (FF FE) or big endian
        (FE FF). Without a mark, the bytes are read as UTF-8 when they are valid UTF-8, and as
        Windows-1252 otherwise: that is what French Excel writes for its first CSV format ("CSV
        (separated by semicolons)"), where an accented letter is one byte.

        .PARAMETER Bytes
        The content of the file.

        .EXAMPLE
        ConvertFrom-SPSLifecycleCsvByte -Bytes ([System.IO.File]::ReadAllBytes($path))
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Byte[]]
        $Bytes
    )

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    try {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        try {
            [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        }
        catch {
            Write-Verbose -Message "The code pages provider was already registered: $($_.Exception.Message)"
        }

        return [System.Text.Encoding]::GetEncoding(1252).GetString($Bytes)
    }
}
