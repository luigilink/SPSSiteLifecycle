# Whether the signal that Ctrl+C sends reaches a child process of the tests. It does not when the tests were started in the background of a
# non-interactive shell: that shell makes the process ignore SIGINT, and every process that it starts inherits that. A test that sends the signal
# asks first, and skips when it does not reach the child (the tests that inject the stop instead of sending the signal still run). A test file
# dot-sources this file in its BeforeAll.

function script:Test-ChildHonorsSigint {
    param([string]$Pwsh)

    if ($null -ne $script:ChildHonorsSigint) {
        return $script:ChildHonorsSigint
    }

    $script:ChildHonorsSigint = $false
    if ($IsWindows) {
        return $false
    }

    $ready = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "sigint-probe-$([System.Guid]::NewGuid().ToString('N')).ready"
    $info = [System.Diagnostics.ProcessStartInfo]::new($Pwsh)
    foreach ($argument in '-NoProfile', '-NonInteractive', '-Command', "Set-Content -LiteralPath '$ready' -Value ready; Start-Sleep -Seconds 120") {
        $info.ArgumentList.Add($argument)
    }

    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $null = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        $deadline = [System.DateTime]::UtcNow.AddSeconds(90)
        while (-not (Test-Path -LiteralPath $ready) -and [System.DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
            Start-Sleep -Milliseconds 100
        }

        if (Test-Path -LiteralPath $ready) {
            $null = & /bin/kill -INT $process.Id
            $script:ChildHonorsSigint = $process.WaitForExit(15000)
        }
    }
    finally {
        if (-not $process.HasExited) {
            $process.Kill($true)
        }

        Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
    }

    $script:ChildHonorsSigint
}
