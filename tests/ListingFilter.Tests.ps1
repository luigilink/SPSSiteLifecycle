BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru

    function script:Get-TestFilter {
        param([string[]]$LockState)
        & $script:Module { param($l) Get-SPSLifecycleListingFilter -LockState $l } $LockState
    }
}

Describe 'Get-SPSLifecycleListingFilter' {
    It 'asks the server for the lock state when a single one is asked: <Name>' -ForEach @(
        @{ Name = 'ReadOnly'; LockState = @('ReadOnly'); Expected = "LockState -eq 'ReadOnly'" }
        @{ Name = 'Unlock'; LockState = @('Unlock'); Expected = "LockState -eq 'Unlock'" }
        @{ Name = 'NoAccess'; LockState = @('NoAccess'); Expected = "LockState -eq 'NoAccess'" }
        @{ Name = 'a state in lowercase, written as the server knows it'; LockState = @('readonly'); Expected = "LockState -eq 'ReadOnly'" }
        @{ Name = 'a state in capitals'; LockState = @('UNLOCK'); Expected = "LockState -eq 'Unlock'" }
        @{ Name = 'the same state twice'; LockState = @('ReadOnly', 'readonly'); Expected = "LockState -eq 'ReadOnly'" }
    ) {
        Get-TestFilter -LockState $LockState | Should -BeExactly $Expected
    }

    It 'gives no filter when several states are asked, because the server filters on one: <Name>' -ForEach @(
        @{ Name = 'ReadOnly and Unlock'; LockState = @('ReadOnly', 'Unlock') }
        @{ Name = 'the three states'; LockState = @('ReadOnly', 'Unlock', 'NoAccess') }
    ) {
        Get-TestFilter -LockState $LockState | Should -BeExactly ''
    }

    It 'refuses a state that the server does not know, so that nothing but a lock state reaches its filter: <Name>' -ForEach @(
        @{ Name = 'a word'; Value = 'Locked' }
        @{ Name = 'a quote'; Value = "ReadOnly' -or LockState -ne 'ReadOnly" }
        @{ Name = 'a space'; Value = 'Read Only' }
        @{ Name = 'an empty text'; Value = '' }
    ) {
        { Get-TestFilter -LockState @($Value) } | Should -Throw -ExpectedMessage '*lock state*'
    }

    It 'refuses an empty list: a Scan that asks for no state lists nothing' {
        { Get-TestFilter -LockState @() } | Should -Throw -ExpectedMessage '*at least one*'
    }

    It 'does not depend on the culture of the machine: <Culture>' -ForEach @(
        @{ Culture = 'en-US' }
        @{ Culture = 'tr-TR' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            Get-TestFilter -LockState @('READONLY') | Should -BeExactly "LockState -eq 'ReadOnly'"
            Get-TestFilter -LockState @('unlock') | Should -BeExactly "LockState -eq 'Unlock'"
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }

    It 'gives the filter that the settings default asks for' {
        $setting = & $script:Module { (Get-SPSLifecycleSettingSchema | Where-Object { $_.Name -eq 'LockStates' }).Default }

        Get-TestFilter -LockState $setting | Should -BeExactly "LockState -eq 'ReadOnly'"
    }
}
