# Watches another process from the outside, so that it keeps talking when that process is stuck:
# CPU time, memory, the threads that burn CPU, and (with dotnet-stack) the managed stacks.
param
(
    [Parameter(Mandatory = $true)]
    [int]
    $TargetPid,

    [string]
    $Label = 'monitor',

    [string]
    $LogPath,

    [int]
    $IntervalSeconds = 10,

    [int]
    $FirstStackSeconds = 75,

    [int]
    $StackEverySeconds = 120,

    [string]
    $StackToolPath
)

$ErrorActionPreference = 'Continue'
$env:DOTNET_ROLL_FORWARD = 'Major'
$toolFolder = Join-Path -Path ([System.Environment]::GetFolderPath('UserProfile')) -ChildPath '.dotnet/tools'
$stackTool = @($StackToolPath, (Join-Path -Path $toolFolder -ChildPath 'dotnet-stack.exe'), (Join-Path -Path $toolFolder -ChildPath 'dotnet-stack')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

function Write-Monitor {
    param([string]$Message)
    $line = '{0:HH:mm:ss.fff}Z [{1}] {2}' -f [System.DateTime]::UtcNow, $Label, $Message
    [System.Console]::Out.WriteLine($line)
    [System.Console]::Out.Flush()
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line
    }
}

Write-Monitor "watching pid $TargetPid, dotnet-stack: $(if ($stackTool) { $stackTool } else { 'not installed' })"
$started = [System.DateTime]::UtcNow
$nextStack = $FirstStackSeconds
$previous = @{}

while ($true) {
    $process = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Monitor "pid $TargetPid has exited"
        break
    }

    $elapsed = ([System.DateTime]::UtcNow - $started).TotalSeconds
    try {
        $threads = foreach ($thread in $process.Threads) {
            try {
                $cpu = $thread.TotalProcessorTime.TotalSeconds
                $delta = $cpu - [double]($previous[$thread.Id] ?? 0)
                $previous[$thread.Id] = $cpu
                $wait = if ($thread.ThreadState -eq 'Wait') { [string]$thread.WaitReason } else { '' }
                [PSCustomObject]@{ Id = $thread.Id; Delta = $delta; State = [string]$thread.ThreadState; Wait = $wait }
            }
            catch {
                continue
            }
        }

        $top = @($threads | Sort-Object -Property Delta -Descending | Select-Object -First 3 | ForEach-Object { '#{0} +{1:N1}s {2}/{3}' -f $_.Id, $_.Delta, $_.State, $_.Wait }) -join '; '
        Write-Monitor ('t={0:N0}s cpu={1:N1}s ws={2:N0}MB private={3:N0}MB threads={4} top: {5}' -f $elapsed, $process.TotalProcessorTime.TotalSeconds, ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB), @($threads).Count, $top)
    }
    catch {
        Write-Monitor "sample failed: $($_.Exception.Message)"
    }

    if ($stackTool -and $elapsed -ge $nextStack) {
        $nextStack += $StackEverySeconds
        $out = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "stack-$TargetPid.txt"
        $err = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "stack-$TargetPid.err"
        Write-Monitor 'asking dotnet-stack for the managed stacks'
        $tool = Start-Process -FilePath $stackTool -ArgumentList @('report', '-p', $TargetPid) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $tool.WaitForExit(60000)) {
            Write-Monitor 'dotnet-stack did not answer in 60 s: the runtime of the target does not respond'
            $tool.Kill()
        }

        if (Test-Path -LiteralPath $err) {
            Get-Content -LiteralPath $err -TotalCount 40 | ForEach-Object { Write-Monitor "stack-error| $_" }
        }

        if (Test-Path -LiteralPath $out) {
            $lines = @(Get-Content -LiteralPath $out)
            if ($LogPath) {
                Add-Content -LiteralPath $LogPath -Value ('--- full dotnet-stack dump at t={0:N0}s' -f $elapsed)
                Add-Content -LiteralPath $LogPath -Value $lines
            }

            # The threads that only wait for work are left out of the console.
            $idle = 'WaitForSignal|TimerThread|GateThreadStart|SocketAsyncEngine|WaitForConnection|InMemoryTransmitter|PipelineFinishedWaitHandle|ProcessListeningThread'
            $blocks = [System.Collections.Generic.List[object]]::new()
            foreach ($line in $lines) {
                if ($line -like 'Thread (*') {
                    $blocks.Add([System.Collections.Generic.List[string]]::new())
                }

                if ($blocks.Count -gt 0) {
                    $blocks[$blocks.Count - 1].Add($line)
                }
            }

            foreach ($block in $blocks) {
                if (($block -join "`n") -notmatch $idle) {
                    $block | Select-Object -First 70 | ForEach-Object { Write-Monitor "stack| $_" }
                }
            }
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}
