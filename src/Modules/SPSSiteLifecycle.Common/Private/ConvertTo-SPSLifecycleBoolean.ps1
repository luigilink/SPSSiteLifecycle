function ConvertTo-SPSLifecycleBoolean {
    <#
        .SYNOPSIS
        Reads a true or false value from a CSV cell, as a spreadsheet may have rewritten it.

        .DESCRIPTION
        The Microsoft 365 reports write True and False. A spreadsheet that opens and saves the file
        writes the words of its own language instead: VRAI and FAUX in French, WAHR and FALSCH in
        German, VERDADERO and FALSO in Spanish, VERO and FALSO in Italian, VERDADEIRO and FALSO in
        Portuguese, WAAR and ONWAAR in Dutch. These, the English yes and no, oui and non, ja and nein,
        and 1 and 0 are read. The case and the spaces around the value are ignored.

        An empty value gives $null. Any other value throws, with a message that says what to do: a
        value that is read the wrong way could keep a deleted site in a report, or drop a live one.

        .PARAMETER Text
        The cell text.

        .EXAMPLE
        ConvertTo-SPSLifecycleBoolean -Text 'WAHR'
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [System.Object]
        $Text
    )

    $value = "$Text".Trim()
    if (-not $value) {
        return $null
    }

    $trueValues = @('true', '1', 'yes', 'vrai', 'oui', 'wahr', 'ja', 'verdadero', 'verdadeiro', 'vero', 'waar')
    $falseValues = @('false', '0', 'no', 'faux', 'non', 'falsch', 'nein', 'falso', 'onwaar')

    $key = $value.ToLowerInvariant()
    if ($trueValues -contains $key) {
        return $true
    }

    if ($falseValues -contains $key) {
        return $false
    }

    throw "'$value' is not a value the tool can read as true or false. The reports write True and False. A spreadsheet may write them in its own language (VRAI and FAUX, WAHR and FALSCH, VERDADERO and FALSO...): put True or False back."
}
