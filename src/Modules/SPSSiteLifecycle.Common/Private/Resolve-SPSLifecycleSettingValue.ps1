function Resolve-SPSLifecycleSettingValue {
    <#
        .SYNOPSIS
        Checks one value of the settings file against its row of the schema.

        .DESCRIPTION
        Types are strict: a number must be a number (not the text '25'), a boolean must be $true or
        $false (not the text 'false', which would otherwise be a true value), and a list must hold
        text. A single text is accepted where a list is expected.

        Returns an object with Value (the checked value: a full path for a path, the canonical
        spelling for a choice, a lowercase text for a GUID) and Error (empty when the value is
        valid, otherwise a sentence that says what is wrong).

        .PARAMETER Row
        The row of Get-SPSLifecycleSettingSchema.

        .PARAMETER Value
        The value found in the settings file.

        .PARAMETER BaseFolder
        The folder of the settings file, for the relative paths.

        .PARAMETER CheckExistence
        Also checks that a file or a folder exists, when the row asks for it.

        .EXAMPLE
        Resolve-SPSLifecycleSettingValue -Row $row -Value 25 -BaseFolder $PSScriptRoot
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Row,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [System.Object]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BaseFolder,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $CheckExistence
    )

    $result = {
        param($Checked, $Problem)
        [PSCustomObject]@{ Value = $Checked; Error = $Problem }
    }

    $isList = $Row.Type -in 'PathList', 'StringList', 'ChoiceList'
    $items = @()
    if ($isList) {
        if ($null -eq $Value) {
            return & $result @() 'must be a list of text values, not empty.'
        }

        if ($Value -is [System.String]) {
            $items = @($Value)
        }
        elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
            $items = @($Value)
        }
        else {
            return & $result @() 'must be a list of text values, for example @(''a'', ''b'').'
        }

        foreach ($item in $items) {
            if ($item -isnot [System.String] -or -not $item.Trim()) {
                return & $result @() 'must hold text values only, none of them empty.'
            }
        }

        if ($items.Count -eq 0 -and -not $Row.AllowEmpty) {
            return & $result @() 'must hold at least one value.'
        }
    }

    switch ($Row.Type) {
        'String' {
            if ($Value -isnot [System.String] -or -not $Value.Trim()) {
                return & $result $null 'must be a text that is not empty.'
            }

            $text = $Value.Trim()
            if ($Row.Pattern -and -not [System.Text.RegularExpressions.Regex]::IsMatch($text, $Row.Pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
                return & $result $null "must be $($Row.PatternHint) (now: '$(ConvertTo-SPSLifecycleVisibleText -Text $text -AsciiOnly)')."
            }

            return & $result $text ''
        }

        'Guid' {
            $guid = [System.Guid]::Empty
            if (($Value -isnot [System.String] -and $Value -isnot [System.Guid]) -or -not [System.Guid]::TryParse("$Value".Trim(), [ref]$guid) -or $guid -eq [System.Guid]::Empty) {
                return & $result $null "must be a GUID (now: '$Value')."
            }

            return & $result $guid.ToString() ''
        }

        'Path' {
            if ($Value -isnot [System.String]) {
                return & $result '' 'must be text (a path).'
            }

            if (-not $Value.Trim()) {
                return & $result '' ''
            }

            $full = ConvertTo-SPSLifecyclePath -Path $Value -BaseFolder $BaseFolder
            if ($CheckExistence -and $Row.MustExist) {
                $type = if ($Row.Kind -eq 'Folder') { 'Container' } else { 'Leaf' }
                if (-not (Test-Path -LiteralPath $full -PathType $type)) {
                    return & $result $full "was not found: '$full'."
                }
            }

            return & $result $full ''
        }

        'PathList' {
            $full = @($items | ForEach-Object { ConvertTo-SPSLifecyclePath -Path $_ -BaseFolder $BaseFolder })
            if ($CheckExistence -and $Row.MustExist) {
                $type = if ($Row.Kind -eq 'Folder') { 'Container' } else { 'Leaf' }
                $missing = @($full | Where-Object { -not (Test-Path -LiteralPath $_ -PathType $type) })
                if ($missing.Count -gt 0) {
                    return & $result $full "was not found: $(($missing | ForEach-Object { "'$_'" }) -join ', ')."
                }
            }

            return & $result $full ''
        }

        'StringList' {
            $trimmed = @($items | ForEach-Object { $_.Trim() })
            if ($Row.Pattern) {
                foreach ($item in $trimmed) {
                    if (-not [System.Text.RegularExpressions.Regex]::IsMatch($item, $Row.Pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
                        return & $result @() "has an entry that must be $($Row.PatternHint) (now: '$(ConvertTo-SPSLifecycleVisibleText -Text $item -AsciiOnly)')."
                    }
                }
            }

            return & $result $trimmed ''
        }

        'Choice' {
            # A choice is compared one character at a time: the comparison operators of PowerShell ignore a soft hyphen and a
            # zero-width space, so a value that has one would be read as the choice that it looks like.
            $match = @($Row.Values | Where-Object { [System.String]::Equals($_, "$Value".Trim(), [System.StringComparison]::OrdinalIgnoreCase) })
            if ($Value -isnot [System.String] -or $match.Count -eq 0) {
                return & $result $null "must be one of: $($Row.Values -join ', ') (now: '$(ConvertTo-SPSLifecycleVisibleText -Text "$Value" -AsciiOnly)')."
            }

            return & $result $match[0] ''
        }

        'ChoiceList' {
            $checked = [System.Collections.Generic.List[System.String]]::new()
            foreach ($item in $items) {
                $match = @($Row.Values | Where-Object { [System.String]::Equals($_, $item.Trim(), [System.StringComparison]::OrdinalIgnoreCase) })
                if ($match.Count -eq 0) {
                    return & $result @() "must hold values among: $($Row.Values -join ', ') (now: '$(ConvertTo-SPSLifecycleVisibleText -Text $item -AsciiOnly)')."
                }

                if (-not $checked.Contains($match[0])) {
                    $checked.Add($match[0])
                }
            }

            return & $result $checked.ToArray() ''
        }

        'Int' {
            if ($Value -isnot [System.Int32] -and $Value -isnot [System.Int64]) {
                return & $result $null "must be a whole number written without quotes (now: '$Value')."
            }

            if (($null -ne $Row.Min -and $Value -lt $Row.Min) -or ($null -ne $Row.Max -and $Value -gt $Row.Max)) {
                return & $result $null "must be between $($Row.Min) and $($Row.Max) (now: $Value)."
            }

            return & $result ([System.Int32]$Value) ''
        }

        'Double' {
            if ($Value -isnot [System.Int32] -and $Value -isnot [System.Int64] -and $Value -isnot [System.Double] -and $Value -isnot [System.Decimal]) {
                return & $result $null "must be a number written without quotes (now: '$Value')."
            }

            if (($null -ne $Row.Min -and $Value -lt $Row.Min) -or ($null -ne $Row.Max -and $Value -gt $Row.Max)) {
                return & $result $null "must be between $($Row.Min) and $($Row.Max) (now: $Value)."
            }

            return & $result ([System.Double]$Value) ''
        }

        'Bool' {
            if ($Value -isnot [System.Boolean]) {
                return & $result $null "must be `$true or `$false, without quotes (now: '$Value')."
            }

            return & $result $Value ''
        }

        default {
            return & $result $null "has a type the tool does not know: '$($Row.Type)'."
        }
    }
}
