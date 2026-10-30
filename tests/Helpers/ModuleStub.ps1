# Stubs for the tests that go through the adapters, shared by the test files that need them. A test file dot-sources this
# file in its BeforeAll, after setting $script:Module (the module under test), calls Install-Tripwire, and calls Remove-Tripwire
# in its AfterAll. Nothing in here reaches a tenant, and what it replaces is put back.

# The commands that reach a tenant. Whatever a test does, inside the module they are never the real ones: Connect-PnPOnline
# is interactive and opens a sign-in window, and the others call the tenant. Each is a function that stops the test, and a
# test that needs one replaces it with Set-ModuleStub. A stub is defined with the scope modifier script: and is checked
# before the test goes on, because a function that is defined without it lives in a scope that ends with the script block
# that defined it, and the real command is then called.
$script:TenantReadCommand = @('Invoke-RestMethod', 'Connect-PnPOnline', 'Get-PnPContext', 'Invoke-PnPQuery', 'Get-PnPTenantSite', 'Get-PnPHomeSite', 'Get-PnPMicrosoft365Group', 'Get-PnPDeletedMicrosoft365Group', 'Get-PnPTenant', 'Get-PnPAccessToken', 'Disconnect-PnPOnline')

# The commands that change a tenant. The Scan reads and never writes, and a test of the Scan stops when one of these is called.
$script:TenantWriteCommand = @('Set-PnPTenantSite', 'Remove-PnPTenantSite', 'Remove-PnPMicrosoft365Group', 'Set-PnPSiteArchiveState', 'Add-PnPSiteCollectionAdmin', 'Register-PnPEntraIDApp', 'Register-PnPEntraIDAppForInteractiveLogin')
$script:TenantCommand = @($script:TenantReadCommand) + @($script:TenantWriteCommand)

function script:Assert-ModuleStub {
    param([string[]]$Name)

    $problems = @(& $script:Module {
            param($names)
            foreach ($name in $names) {
                $command = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $command -or $command.CommandType -ne 'Function' -or $command.Definition -notlike '*SPSLIFECYCLE-TEST-STUB*') {
                    '{0} is {1}' -f $name, $(if ($null -eq $command) { 'nothing' } else { "a $($command.CommandType), not a stub" })
                }
            }
        } $Name)
    if ($problems.Count -gt 0) {
        throw "The stubs are not in place in the module, and the test is stopped before it can reach a tenant: $($problems -join '; ')."
    }
}

function script:Install-Tripwire {
    & $script:Module {
        param($names)
        foreach ($name in $names) {
            Invoke-Expression ("function script:{0} {{`n# SPSLIFECYCLE-TEST-STUB`nthrow 'A test called {0} for real, which would reach a tenant or open a sign-in window.'`n}}" -f $name)
        }
    } $script:TenantCommand

    Assert-ModuleStub -Name $script:TenantCommand
}

# Replaces functions of the module, or adds the ones that PnP.PowerShell would bring, for the length of a test. A stub is
# the text of the body of a function, and it runs in the scope of the module, where $script:StubLog is the list that it
# writes to and $script:StubData what the test gave.
function script:Set-ModuleStub {
    param([hashtable]$Stub, [hashtable]$Data = @{})

    & $script:Module {
        param($stub, $data)
        $script:StubLog = [System.Collections.Generic.List[System.Object]]::new()
        $script:StubData = $data
        if ($null -eq $script:StubSaved) {
            $script:StubSaved = @{}
        }

        foreach ($name in $stub.Keys) {
            if (-not $script:StubSaved.ContainsKey($name)) {
                $existing = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
                $script:StubSaved[$name] = if ($null -ne $existing -and $existing.Definition -notlike '*SPSLIFECYCLE-TEST-STUB*') { $existing.ScriptBlock } else { $null }
            }

            Invoke-Expression ("function script:{0} {{`n# SPSLIFECYCLE-TEST-STUB`n{1}`n}}" -f $name, $stub[$name])
        }
    } $Stub $Data

    Assert-ModuleStub -Name @($Stub.Keys)
}

function script:Clear-ModuleStub {
    & $script:Module {
        # Nothing was stubbed yet when a test that does not stub clears them (an AfterEach of a Describe).
        foreach ($name in $(if ($null -ne $script:StubSaved) { @($script:StubSaved.Keys) } else { @() })) {
            if ($null -ne $script:StubSaved[$name]) {
                Set-Item -Path "Function:\script:$name" -Value $script:StubSaved[$name]
            }
            else {
                Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
            }
        }

        $script:StubSaved = @{}
    }

    Install-Tripwire
}

function script:Get-StubLog {
    @(& $script:Module { $script:StubLog })
}

function script:Remove-Tripwire {
    & $script:Module {
        param($names)
        foreach ($name in $names) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    } $script:TenantCommand
}
