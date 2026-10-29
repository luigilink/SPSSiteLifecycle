# Prints what the runner is: PowerShell, .NET, CPU, memory, and the variables that change the runtime.
$ErrorActionPreference = 'Continue'

Write-Host '--- PowerShell'
$PSVersionTable | Out-String | Write-Host
Write-Host ('pwsh path: ' + (Get-Process -Id $PID).Path)

Write-Host '--- Runtime'
Write-Host ('FrameworkDescription: ' + [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)
Write-Host ('OSDescription: ' + [System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
Write-Host ('ProcessArchitecture: ' + [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)
Write-Host ('OSArchitecture: ' + [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
Write-Host ('Is64BitProcess: ' + [Environment]::Is64BitProcess)
Write-Host ('ProcessorCount: ' + [Environment]::ProcessorCount)
Write-Host ('IsServerGC: ' + [System.Runtime.GCSettings]::IsServerGC)
Write-Host ('GCLatencyMode: ' + [System.Runtime.GCSettings]::LatencyMode)
Write-Host ('TotalAvailableMemoryMB: ' + [int]([GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes / 1MB))
Write-Host ('Culture: ' + [System.Globalization.CultureInfo]::CurrentCulture.Name + ' / UI ' + [System.Globalization.CultureInfo]::CurrentUICulture.Name)
Write-Host ('UseNls: ' + [System.AppContext]::GetData('System.Globalization.UseNls'))
Write-Host ('Invariant: ' + [System.AppContext]::GetData('System.Globalization.Invariant'))

Write-Host '--- CPU features'
foreach ($name in 'Vector128', 'Vector256', 'Vector512') {
    $type = [System.Type]::GetType("System.Runtime.Intrinsics.$name")
    Write-Host ("$name.IsHardwareAccelerated: " + $type.GetProperty('IsHardwareAccelerated').GetValue($null))
}

foreach ($name in 'Sse42', 'Avx', 'Avx2', 'Avx512F', 'Avx512BW', 'Bmi1', 'Bmi2', 'Lzcnt', 'Popcnt') {
    $type = [System.Type]::GetType("System.Runtime.Intrinsics.X86.$name")
    if ($type) {
        Write-Host ("X86.$name.IsSupported: " + $type.GetProperty('IsSupported').GetValue($null))
    }
}

Write-Host '--- Machine'
if ($IsWindows) {
    Get-CimInstance Win32_Processor | Format-List Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Out-String | Write-Host
    Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, OSArchitecture, TotalVisibleMemorySize, FreePhysicalMemory | Out-String | Write-Host
}
else {
    Get-Content /proc/cpuinfo -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(model name|flags)' } | Select-Object -First 2 | ForEach-Object { $_.Substring(0, [Math]::Min(300, $_.Length)) } | Write-Host
}

Write-Host '--- Variables'
Get-ChildItem Env: | Where-Object { $_.Name -match '^(DOTNET|COMPlus|PS|POWERSHELL|PROCESSOR|NUMBER_OF)' } | Format-Table -AutoSize | Out-String | Write-Host

Write-Host '--- dotnet'
dotnet --list-runtimes
dotnet --list-sdks

Write-Host '--- What PowerShell reports for a .NET method call (AMSI member invocation logging)'
$demo = '$r = [System.Text.RegularExpressions.Regex]::new(''a''); $null = $r.Match((''abcdef'' * 3), 4)'
$env:__PSDumpAMSILogContent = '1'
& (Get-Process -Id $PID).Path -NoProfile -Command $demo
Remove-Item Env:__PSDumpAMSILogContent
