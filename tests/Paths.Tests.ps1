BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
    $script:Tool = Join-Path -Path $PSScriptRoot -ChildPath '../tools/Update-Documentation.ps1'

    function script:New-TestFolder {
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $folder
    }

    function script:Write-TestCsv {
        param([string]$Path, [string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($true))
    }

    # What a user gets after Set-Location: the location of the PowerShell session moves, the working directory of
    # the process does not, and the .NET file methods only know the second one. Both are put back afterwards.
    function script:Invoke-InDivergedLocation {
        param([string]$Location, [string]$ProcessDirectory, [scriptblock]$Script)
        $previousLocation = (Get-Location).Path
        $previousDirectory = [System.IO.Directory]::GetCurrentDirectory()
        try {
            [System.IO.Directory]::SetCurrentDirectory($ProcessDirectory)
            Set-Location -LiteralPath $Location
            & $Script
        }
        finally {
            Set-Location -LiteralPath $previousLocation
            [System.IO.Directory]::SetCurrentDirectory($previousDirectory)
        }
    }

    function script:Get-FullPathOf {
        param([string]$Path)
        [System.IO.Path]::GetFullPath($Path)
    }
}

Describe 'Resolve-SPSLifecycleFileSystemPath' {
    BeforeAll {
        $script:Location = New-TestFolder
        $script:ProcessDirectory = New-TestFolder

        function script:Resolve-TestPath {
            param([string]$Path)
            & $script:Module { param($p) Resolve-SPSLifecycleFileSystemPath -Path $p } $Path
        }
    }

    It 'resolves a relative path against the location of the session, not the working directory of the process' {
        $full = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
            Resolve-TestPath -Path 'Reports/2026/lock.csv'
        }

        $full | Should -BeExactly (Get-FullPathOf (Join-Path -Path $script:Location -ChildPath 'Reports/2026/lock.csv'))
    }

    It 'follows the session when it moves to another folder' {
        $other = New-TestFolder
        $first = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script { Resolve-TestPath -Path 'a.csv' }
        $second = Invoke-InDivergedLocation -Location $other -ProcessDirectory $script:ProcessDirectory -Script { Resolve-TestPath -Path 'a.csv' }

        $first | Should -BeExactly (Get-FullPathOf (Join-Path -Path $script:Location -ChildPath 'a.csv'))
        $second | Should -BeExactly (Get-FullPathOf (Join-Path -Path $other -ChildPath 'a.csv'))
    }

    It 'normalizes the dots of <Path>' -ForEach @(
        @{ Path = './sub/../Reports/a.csv'; Expected = 'Reports/a.csv' }
        @{ Path = 'x/y/../../b.csv'; Expected = 'b.csv' }
    ) {
        $full = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script { Resolve-TestPath -Path $Path }

        $full | Should -BeExactly (Get-FullPathOf (Join-Path -Path $script:Location -ChildPath $Expected))
    }

    It 'gives a full path back, whatever the session location' {
        $target = Get-FullPathOf (Join-Path -Path (New-TestFolder) -ChildPath 'full.csv')
        $full = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script { Resolve-TestPath -Path $target }

        $full | Should -BeExactly $target
    }

    It 'expands the home folder' {
        Resolve-TestPath -Path '~/lock.csv' | Should -BeExactly (Get-FullPathOf (Join-Path -Path $HOME -ChildPath 'lock.csv'))
    }

    It 'takes brackets literally, because a folder can be named [Archive] 2026' {
        $full = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script { Resolve-TestPath -Path '[Archive] 2026/lock[1].csv' }

        $full | Should -BeExactly (Get-FullPathOf (Join-Path -Path $script:Location -ChildPath '[Archive] 2026/lock[1].csv'))
    }

    It 'does not need the file or the folder to exist' {
        { Resolve-TestPath -Path 'does/not/exist/yet.csv' } | Should -Not -Throw
    }

    It 'refuses a path of another provider: <Path>' -ForEach @(
        @{ Path = 'Env:/PATH' }
        @{ Path = 'Variable:/reports' }
    ) {
        { Resolve-TestPath -Path $Path } | Should -Throw -ExpectedMessage '*not a path of the file system*'
    }
}

Describe 'Read-SPSLifecycleCsv with a relative path' {
    BeforeEach {
        $script:Location = New-TestFolder
        $script:ProcessDirectory = New-TestFolder
    }

    It 'reads the file of the session location, not a file of the same name in the working directory of the process' {
        Write-TestCsv -Path (Join-Path -Path $script:Location -ChildPath 'lock.csv') -Text "Url`r`nhttps://contoso.sharepoint.com/sites/right`r`n"
        Write-TestCsv -Path (Join-Path -Path $script:ProcessDirectory -ChildPath 'lock.csv') -Text "Url`r`nhttps://contoso.sharepoint.com/sites/decoy`r`n"

        $rows = @(Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
                & $script:Module { Read-SPSLifecycleCsv -Path 'lock.csv' -RequiredColumn 'Url' }
            })

        $rows | Should -HaveCount 1
        $rows[0].Url | Should -BeExactly 'https://contoso.sharepoint.com/sites/right'
    }

    It 'reads a file that only the session location has' {
        Write-TestCsv -Path (Join-Path -Path $script:Location -ChildPath 'only-here.csv') -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n"

        $rows = @(Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
                & $script:Module { Read-SPSLifecycleCsv -Path 'only-here.csv' -RequiredColumn 'Url' }
            })

        $rows | Should -HaveCount 1
    }

    It 'does not find a file that only the working directory of the process has, and names the path it looked at' {
        Write-TestCsv -Path (Join-Path -Path $script:ProcessDirectory -ChildPath 'elsewhere.csv') -Text "Url`r`nhttps://contoso.sharepoint.com/sites/a`r`n"
        $expectedPath = Get-FullPathOf (Join-Path -Path $script:Location -ChildPath 'elsewhere.csv')

        {
            Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
                & $script:Module { Read-SPSLifecycleCsv -Path 'elsewhere.csv' -RequiredColumn 'Url' }
            }
        } | Should -Throw -ExpectedMessage "File not found: '$([System.Management.Automation.WildcardPattern]::Escape($expectedPath))'*"
    }

    It 'refuses a path of another provider' {
        { & $script:Module { Read-SPSLifecycleCsv -Path 'Variable:/lock.csv' } } | Should -Throw -ExpectedMessage '*not a path of the file system*'
    }
}

Describe 'Export-SPSLifecycleReport with a relative folder' {
    BeforeEach {
        $script:Location = New-TestFolder
        $script:ProcessDirectory = New-TestFolder
        $script:GeneratedOn = [System.DateTime]::new(2026, 10, 28, 16, 30, 0, [System.DateTimeKind]::Utc)
    }

    It 'writes in the folder of the session location, not in the working directory of the process' {
        $path = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
            & $script:Module { param($g) Export-SPSLifecycleReport -Row @() -OutputFolder 'Reports' -GeneratedOn $g } $script:GeneratedOn
        }

        $expected = Get-FullPathOf (Join-Path -Path $script:Location -ChildPath 'Reports/sites-20261028T163000Z.csv')
        $path | Should -BeExactly $expected
        Test-Path -LiteralPath $expected | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:ProcessDirectory -ChildPath 'Reports') | Should -BeFalse -Because 'nothing may be written where the process was started'
    }

    It 'never overwrites the report of the session location, whatever the working directory of the process' {
        $first = Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
            & $script:Module { param($g) Export-SPSLifecycleReport -Row @() -OutputFolder 'Reports' -GeneratedOn $g } $script:GeneratedOn
        }
        $before = [System.IO.File]::ReadAllBytes($first)

        {
            Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
                & $script:Module { param($g) Export-SPSLifecycleReport -Row @() -OutputFolder 'Reports' -GeneratedOn $g } $script:GeneratedOn
            }
        } | Should -Throw -ExpectedMessage '*already exists*'

        [System.IO.File]::ReadAllBytes($first) | Should -Be $before
    }

    It 'refuses a folder of another provider, and creates nothing' {
        {
            Invoke-InDivergedLocation -Location $script:Location -ProcessDirectory $script:ProcessDirectory -Script {
                & $script:Module { param($g) Export-SPSLifecycleReport -Row @() -OutputFolder 'Variable:/Reports' -GeneratedOn $g } $script:GeneratedOn
            }
        } | Should -Throw -ExpectedMessage '*not a path of the file system*'

        @(Get-ChildItem -LiteralPath $script:Location) | Should -HaveCount 0
        @(Get-ChildItem -LiteralPath $script:ProcessDirectory) | Should -HaveCount 0
    }
}

Describe 'ConvertTo-SPSLifecyclePath with a relative base folder' {
    It 'resolves the base folder against the location of the session' {
        $location = New-TestFolder
        $processDirectory = New-TestFolder

        $full = Invoke-InDivergedLocation -Location $location -ProcessDirectory $processDirectory -Script {
            & $script:Module { ConvertTo-SPSLifecyclePath -Path 'Reports\2026' -BaseFolder 'conf' }
        }

        $full | Should -BeExactly (Get-FullPathOf (Join-Path -Path $location -ChildPath 'conf/Reports/2026'))
    }
}

Describe 'tools/Update-Documentation.ps1 with a relative wiki folder' {
    It 'writes the pages in the folder of the session location' {
        $location = New-TestFolder
        $processDirectory = New-TestFolder
        $null = New-Item -Path (Join-Path -Path $location -ChildPath 'out') -ItemType Directory
        $tool = (Resolve-Path -LiteralPath $script:Tool).ProviderPath
        $command = "Set-Location -LiteralPath '$($location.Replace("'", "''"))'; & '$($tool.Replace("'", "''"))' -WikiFolder 'out' | Out-Null"

        $info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($argument in '-NoProfile', '-NonInteractive', '-Command', $command) {
            $info.ArgumentList.Add($argument)
        }

        $info.WorkingDirectory = $processDirectory
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($info)
        $null = $process.StandardOutput.ReadToEnd()
        $errors = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $process.ExitCode | Should -Be 0 -Because $errors
        foreach ($page in 'Configuration.md', 'Verdicts.md', 'Report.md') {
            Test-Path -LiteralPath (Join-Path -Path $location -ChildPath "out/$page") | Should -BeTrue
        }

        Test-Path -LiteralPath (Join-Path -Path $processDirectory -ChildPath 'out') | Should -BeFalse
    }
}
