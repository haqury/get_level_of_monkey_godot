
param(
    [string]$StatusPath,
    [string]$MemoryName = "brainlink_data"
)
$ErrorActionPreference = "SilentlyContinue"
Add-Type -TypeDefinition @"
using System;
using System.IO.MemoryMappedFiles;
public class BlShm {
    static MemoryMappedFile map;
    static MemoryMappedViewAccessor view;
    public static bool Open(string name) {
        Close();
        string[] names = new string[] { name, "Local\\" + name, "Global\\" + name };
        foreach (string n in names) {
            try {
                map = MemoryMappedFile.OpenExisting(n);
                view = map.CreateViewAccessor();
                return true;
            } catch {}
        }
        return false;
    }
    public static void Close() {
        try { if (view != null) view.Dispose(); } catch {}
        try { if (map != null) map.Dispose(); } catch {}
        view = null;
        map = null;
    }
    public static bool Ok() { return view != null; }
    public static int R(int i) { return view.ReadInt32(i * 4); }
    public static void W(int i, int v) {
        if (v > 2147483647) v = 2147483647;
        if (v < -2147483648) v = -2147483648;
        view.Write(i * 4, v);
    }
}
"@

$dir = Split-Path -Parent $StatusPath
$queuePath = Join-Path $dir "brainlink_cmd_queue.json"
$pidPath = Join-Path $dir "brainlink_shim.pid"
Set-Content -Path $pidPath -Value $PID -Encoding ascii

$codes = @{ 0 = ""; 1 = "ml"; 2 = "mr"; 3 = "mu"; 4 = "md"; 5 = "stop"; 6 = "ne" }
$eventToCode = @{ "ml" = 1; "mr" = 2; "mu" = 3; "md" = 4; "stop" = 5; "ne" = 6 }
$start = Get-Date
$lastSig = ""
$lastChange = Get-Date
$mem = $MemoryName

function Send-Cmd([int]$type, [int]$eventCode) {
    $deadline = (Get-Date).AddMilliseconds(250)
    while ([BlShm]::R(21) -eq 1) {
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Milliseconds 2
    }
    $ms = [int]((Get-Date) - $start).TotalMilliseconds
    [BlShm]::W(22, $type)
    [BlShm]::W(23, $eventCode)
    [BlShm]::W(24, $ms)
    [BlShm]::W(21, 1)
    return $true
}

function Read-Queue {
    if (-not (Test-Path $queuePath)) { return @() }
    try {
        $raw = Get-Content -Raw -Path $queuePath
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $parsed = $raw | ConvertFrom-Json
        if ($null -eq $parsed) { return @() }
        if ($parsed -isnot [System.Array]) { return @($parsed) }
        return $parsed
    } catch { return @() }
}

while ($true) {
    $queue = @(Read-Queue)
    $remaining = @()
    $gt = 0
    foreach ($cmd in $queue) {
        $name = [string]$cmd.cmd
        $isGt = ($name -eq "send_ground_truth" -or $name -eq "minigame_event" -or ($name -eq "send_event" -and [int]$cmd.command_type -eq 2))
        if ($isGt -and $gt -ge 1) { $remaining += $cmd; continue }
        if ($name -eq "connect") {
            $mem = [string]$cmd.memory_name
            if (-not $mem) { $mem = $MemoryName }
            $opened = [BlShm]::Open($mem)
            if (-not $opened) { $remaining += $cmd }
            continue
        }
        if (-not [BlShm]::Ok()) {
            if ($isGt -or $name -eq "send_event" -or $name -eq "config_command" -or $name -eq "disconnect") { $remaining += $cmd }
            continue
        }
        if ($name -eq "disconnect") { [BlShm]::Close(); continue }
        if ($name -eq "send_ground_truth" -or $name -eq "minigame_event") {
            $code = [int]$eventToCode[[string]$cmd.event_code]
            if ($code -eq 0 -and $name -eq "minigame_event") { $code = [int]$eventToCode[[string]$cmd.keyboard_event] }
            if ($code -ne 0) { [void](Send-Cmd 2 $code); $gt++ }
            continue
        }
        if ($name -eq "send_event") {
            $ctype = [int]$cmd.command_type
            if ($ctype -eq 2) {
                $code = [int]$eventToCode[[string]$cmd.event_code]
                if ($code -ne 0) { [void](Send-Cmd 2 $code); $gt++ }
            } elseif ($ctype -ge 3 -and $ctype -le 9) {
                [void](Send-Cmd $ctype 0)
            }
            continue
        }
        if ($name -eq "config_command") {
            $ctype = [int]$cmd.command_type
            if ($ctype -ge 3 -and $ctype -le 9) { [void](Send-Cmd $ctype 0) }
        }
    }
    if ($queue.Count -gt 0) {
        if ($remaining.Count -eq 0) {
            Set-Content -Path $queuePath -Value "[]" -Encoding ascii
        } else {
            $parts = @($remaining | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 })
            Set-Content -Path $queuePath -Value ("[" + ($parts -join ",") + "]") -Encoding ascii
        }
    }

    if (-not [BlShm]::Ok()) { [void][BlShm]::Open($mem) }

    $attached = [BlShm]::Ok()
    $active = $false
    $event = ""
    $conf = 0.0
    $pml = 0; $pmr = 0; $pmu = 0; $pmd = 0; $pstop = 0
    if ($attached) {
        try {
            $ev = [BlShm]::R(13)
            $conf = [Math]::Max(0, [Math]::Min(1, [BlShm]::R(25) / 1000.0))
            $pml = [BlShm]::R(26) / 1000.0
            $pmr = [BlShm]::R(27) / 1000.0
            $pmu = [BlShm]::R(28) / 1000.0
            $pmd = [BlShm]::R(29) / 1000.0
            $pstop = [BlShm]::R(30) / 1000.0
            $sig = "$ev|$([int]($conf*1000))|$([int]($pml*1000))|$([int]($pmr*1000))|$([int]($pmu*1000))|$([int]($pmd*1000))|$([int]($pstop*1000))"
            if ($sig -ne $lastSig) { $lastSig = $sig; $lastChange = Get-Date }
            $age = ((Get-Date) - $lastChange).TotalSeconds
            $stuck = ($ev -ne 0 -and $age -gt 2.5)
            $active = ($age -lt 22.0 -and -not $stuck)
            if ($active -and $codes.ContainsKey($ev)) { $event = [string]$codes[$ev] }
            if (-not $active) { $conf = 0; $event = "" }
        } catch {
            [BlShm]::Close()
            $attached = $false
            $active = $false
            $event = ""
            $conf = 0
        }
    }
    $hb = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    $at = $(if ($attached) { "true" } else { "false" })
    $ac = $(if ($active) { "true" } else { "false" })
    $json = "{`"shm_attached`":$at,`"client_active`":$ac,`"connected`":$ac,`"event`":`"$event`",`"confidence`":$conf,`"probs`":{`"ml`":$pml,`"mr`":$pmr,`"mu`":$pmu,`"md`":$pmd,`"stop`":$pstop},`"heartbeat_ms`":$hb}"
    Set-Content -Path $StatusPath -Value $json -Encoding ascii
    Start-Sleep -Milliseconds 16
}
