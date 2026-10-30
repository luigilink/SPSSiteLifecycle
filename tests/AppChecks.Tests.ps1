BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru

    function script:Test-AppName {
        param([AllowNull()][string]$Name)

        & $script:Module { param($n) Test-SPSLifecycleAppName -Name $n } $Name
    }

    function script:Invoke-AppFolder {
        param([string]$Folder, [string]$ApplicationName = 'SPSSiteLifecycle', [string]$ToolRoot = '')

        & $script:Module { param($f, $a, $t) Resolve-SPSLifecycleAppFolder -Folder $f -ApplicationName $a -ToolRoot $t } $Folder $ApplicationName $ToolRoot
    }

    function script:New-Folder {
        param([string]$Name)

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        $null = New-Item -Path $path -ItemType Directory -Force
        $path
    }
}

Describe 'Test-SPSLifecycleAppName' {
    It 'accepts a name that is made of letters, digits, dots, dashes and underscores: <Name>' -ForEach @(
        @{ Name = 'SPSSiteLifecycle' }
        @{ Name = 'a' }
        @{ Name = 'A1' }
        @{ Name = '0app' }
        @{ Name = 'my-app_2.0' }
        @{ Name = 'a..b' }
        @{ Name = 'app-' }
        @{ Name = 'app_' }
        @{ Name = ('a' * 64) }
    ) {
        Test-AppName -Name $Name | Should -BeTrue
    }

    It 'refuses a name that could be a path, a device, or another thing than a name: <Name>' -ForEach @(
        @{ Name = '' }
        @{ Name = $null }
        @{ Name = ' ' }
        @{ Name = 'my app' }
        @{ Name = 'a/b' }
        @{ Name = 'a\b' }
        @{ Name = '..' }
        @{ Name = '.a' }
        @{ Name = '-a' }
        @{ Name = '_a' }
        @{ Name = 'a.' }
        @{ Name = "a`n" }
        @{ Name = "a`r`n" }
        @{ Name = ('a' * 65) }
        @{ Name = 'caf' + [char]0x00E9 }
        @{ Name = 'a' + [char]0x212A }
        @{ Name = 'a' + [char]0x200B }
        @{ Name = 'a;b' }
        @{ Name = "a'b" }
        @{ Name = 'a$b' }
    ) {
        Test-AppName -Name $Name | Should -BeFalse
    }

    It 'refuses a name that Windows keeps for a device, with an extension or not, in any case: <Name>' -ForEach @(
        @{ Name = 'CON' }
        @{ Name = 'con' }
        @{ Name = 'Prn' }
        @{ Name = 'AUX' }
        @{ Name = 'nul' }
        @{ Name = 'COM1' }
        @{ Name = 'com9' }
        @{ Name = 'LPT1' }
        @{ Name = 'lpt9' }
        @{ Name = 'con.txt' }
        @{ Name = 'Nul.v2' }
    ) {
        Test-AppName -Name $Name | Should -BeFalse
    }

    It 'accepts a name that only starts like a device name: <Name>' -ForEach @(
        @{ Name = 'console' }
        @{ Name = 'COM10' }
        @{ Name = 'LPT0' }
        @{ Name = 'auxiliary' }
        @{ Name = 'nullable' }
    ) {
        Test-AppName -Name $Name | Should -BeTrue
    }
}

Describe 'Assert-SPSLifecycleAppTarget' {
    BeforeAll {
        function script:Assert-Target {
            param([string]$TenantName = 'contoso', [string]$ApplicationName = 'SPSSiteLifecycle')

            & $script:Module { param($t, $a) Assert-SPSLifecycleAppTarget -TenantName $t -ApplicationName $a } $TenantName $ApplicationName
        }
    }

    It 'lets a tenant and an app name through' {
        { Assert-Target } | Should -Not -Throw
        { Assert-Target -TenantName 'Contoso-2' -ApplicationName 'my-app_2.0' } | Should -Not -Throw
    }

    It 'refuses the Microsoft corporate tenants, in any case and with spaces around: <Tenant>' -ForEach @(
        @{ Tenant = 'microsoft' }
        @{ Tenant = 'MICROSOFT' }
        @{ Tenant = 'MicroSoft' }
        @{ Tenant = ' microsoft ' }
        @{ Tenant = 'microsoftonline' }
        @{ Tenant = 'MicrosoftOnline' }
    ) {
        { Assert-Target -TenantName $Tenant } | Should -Throw -ExpectedMessage '*refused*Microsoft corporate tenants*'
    }

    It 'refuses what is not the name of a tenant, and says what a tenant name is: <Tenant>' -ForEach @(
        @{ Tenant = '' }
        @{ Tenant = 'contoso.sharepoint.com' }
        @{ Tenant = 'contoso.onmicrosoft.com' }
        @{ Tenant = 'https://contoso.sharepoint.com' }
        @{ Tenant = 'con toso' }
        @{ Tenant = '-contoso' }
        @{ Tenant = ('a' * 64) }
        @{ Tenant = ('{0}ontoso' -f [char]0x212A) }
        @{ Tenant = ('micros{0}ft' -f [char]0x043E) }
    ) {
        { Assert-Target -TenantName $Tenant } | Should -Throw -ExpectedMessage '*TenantName*'
    }

    It 'refuses an application name that is not valid, and says which rule it breaks: <Name>' -ForEach @(
        @{ Name = '' }
        @{ Name = 'my app' }
        @{ Name = '../x' }
        @{ Name = 'CON' }
        @{ Name = ('a' * 65) }
    ) {
        { Assert-Target -ApplicationName $Name } | Should -Throw -ExpectedMessage '*ApplicationName*letters, digits*'
    }
}

Describe 'Resolve-SPSLifecycleAppFolder' {
    It 'gives the full path of a folder that does not exist yet, outside any repository' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'keys/spslc'

        Invoke-AppFolder -Folder $folder | Should -BeExactly $folder
        Test-Path -LiteralPath $folder | Should -BeFalse -Because 'resolving a folder creates nothing'
    }

    It 'accepts a folder that exists and is empty, and one that has other files' {
        $folder = New-Folder -Name 'existing'
        Invoke-AppFolder -Folder $folder | Should -BeExactly $folder

        $null = New-Item -Path (Join-Path -Path $folder -ChildPath 'other.txt') -ItemType File
        Invoke-AppFolder -Folder $folder | Should -BeExactly $folder
    }

    It 'resolves a relative folder against the location of the session, as a cmdlet does' {
        $base = New-Folder -Name 'here'
        Push-Location -LiteralPath $base
        try {
            Invoke-AppFolder -Folder './keys' | Should -BeExactly (Join-Path -Path $base -ChildPath 'keys')
        }
        finally {
            Pop-Location
        }
    }

    It 'refuses a folder that is inside a repository, whatever its depth: a key must never be next to the code' {
        $repository = New-Folder -Name 'repo'
        $null = New-Item -Path (Join-Path -Path $repository -ChildPath '.git') -ItemType Directory

        foreach ($relative in 'keys', 'a/b/c', '.') {
            $folder = if ($relative -eq '.') { $repository } else { Join-Path -Path $repository -ChildPath $relative }
            { Invoke-AppFolder -Folder $folder } | Should -Throw -ExpectedMessage '*inside a repository*outside*'
        }
    }

    It 'refuses a folder inside a worktree or a submodule, where .git is a file' {
        $repository = New-Folder -Name 'worktree'
        Set-Content -LiteralPath (Join-Path -Path $repository -ChildPath '.git') -Value 'gitdir: ../elsewhere'

        { Invoke-AppFolder -Folder (Join-Path -Path $repository -ChildPath 'keys') } | Should -Throw -ExpectedMessage '*inside a repository*'
    }

    It 'refuses a folder inside the folder of the tool, even when it is not a repository, and not a folder that only starts like it' {
        $tool = New-Folder -Name 'tool'
        $neighbour = New-Folder -Name 'toolbox'

        { Invoke-AppFolder -Folder (Join-Path -Path $tool -ChildPath 'keys') -ToolRoot $tool } | Should -Throw -ExpectedMessage '*folder of the tool*outside*'
        { Invoke-AppFolder -Folder $tool -ToolRoot $tool } | Should -Throw -ExpectedMessage '*folder of the tool*'
        { Invoke-AppFolder -Folder (Join-Path -Path $neighbour -ChildPath 'keys') -ToolRoot $tool } | Should -Not -Throw
    }

    It 'refuses the root of a drive, and does not read it as the current folder of a drive' {
        $root = [System.IO.Path]::GetPathRoot($TestDrive)

        { Invoke-AppFolder -Folder $root } | Should -Throw -ExpectedMessage '*root of a drive*'
    }

    It 'compares the folder of the tool without regard to the case, because a file system may not: the folder itself, and what is below it' {
        $tool = New-Folder -Name 'ToolCase'

        { Invoke-AppFolder -Folder $tool.ToUpperInvariant() -ToolRoot $tool } | Should -Throw -ExpectedMessage '*folder of the tool*'
        { Invoke-AppFolder -Folder (Join-Path -Path $tool.ToUpperInvariant() -ChildPath 'keys') -ToolRoot $tool } | Should -Throw -ExpectedMessage '*folder of the tool*'
    }

    It 'refuses a folder that is a file' {
        $file = Join-Path -Path $TestDrive -ChildPath 'afile'
        Set-Content -LiteralPath $file -Value 'x'

        { Invoke-AppFolder -Folder $file } | Should -Throw -ExpectedMessage '*is a file*'
    }

    It 'refuses to go on when a key or a certificate of that name is already there: <File>' -ForEach @(
        @{ File = 'SPSSiteLifecycle.pfx' }
        @{ File = 'SPSSiteLifecycle.cer' }
    ) {
        $folder = New-Folder -Name "taken-$($File.Substring($File.Length - 3))"
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath $File) -Value 'x'

        { Invoke-AppFolder -Folder $folder } | Should -Throw -ExpectedMessage "*$File*already*"
    }

    It 'does not mind a file of another name' {
        $folder = New-Folder -Name 'other-name'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'Other.pfx') -Value 'x'

        { Invoke-AppFolder -Folder $folder } | Should -Not -Throw
    }

    It 'refuses a folder that is not given' {
        { Invoke-AppFolder -Folder '' } | Should -Throw
    }
}
