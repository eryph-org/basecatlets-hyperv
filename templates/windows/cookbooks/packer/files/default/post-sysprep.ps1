
# Runs as NT AUTHORITY\SYSTEM via the one-shot "EryphPostSysprep" Scheduled
# Task registered by sysprep.ps1. SYSTEM is not affected by the user-session
# teardown that sysprep /generalize performs, so this script can reliably
# finish image cleanup and power the VM off even after the foreground WinRM
# pipeline has died.

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
# Use Continue (not Stop) so we always reach Stop-Computer even if a step fails.
$ErrorActionPreference = 'Continue'

# Append into sysprep.log (not a separate file) so all four CHECKPOINT_*
# markers tests grep for are written to the same place.
Start-Transcript -Path C:\Windows\Temp\sysprep.log -Append | Out-Null

Write-Host "POST-SYSPREP: starting as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# The task trigger fires shortly after registration, so sysprep is usually
# still in progress when we start. Wait for the success tag before doing
# anything destructive.
$tag = "C:\Windows\System32\Sysprep\Sysprep_succeeded.tag"
$timeoutSeconds = 900
$waited = 0
while (-not (Test-Path $tag)) {
    if ($waited -ge $timeoutSeconds) {
        Write-Host "POST-SYSPREP: timed out waiting for $tag after $timeoutSeconds seconds"
        Write-Host "POST-SYSPREP: dumping sysprep setuperr.log"
        Get-Content "C:\Windows\System32\Sysprep\Panther\setuperr.log" -ErrorAction SilentlyContinue
        Write-Host "POST-SYSPREP: dumping sysprep setupact.log (tail)"
        Get-Content "C:\Windows\System32\Sysprep\Panther\setupact.log" -Tail 200 -ErrorAction SilentlyContinue
        Write-Host "POST-SYSPREP: NOT shutting down so Packer's shutdown_timeout fires and the build fails visibly"
        Stop-Transcript | Out-Null
        return
    }
    Start-Sleep -Seconds 10
    $waited += 10
}
Write-Host "POST-SYSPREP: sysprep succeeded (waited ${waited}s)"
# Emitted here (not in sysprep.ps1) so the marker is reliably written even
# when the WinRM-driven poll is torn down by sysprep's logon teardown.
Write-Host "CHECKPOINT_02: Sysprep completed"

# Reset Hyper-V KVP guest-to-host exchange values. The Integration
# Services refresh these while sysprep is running, so the reset must
# happen after sysprep -- doing it earlier just gets repopulated.
Write-Host "POST-SYSPREP: resetting Hyper-V KVP guest exchange data"
try {
    $kvpGuestKey = "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest"
    if (Test-Path $kvpGuestKey) {
        $kvpValues = @(Get-Item -Path $kvpGuestKey | Select-Object -ExpandProperty Property)
        foreach ($valueName in $kvpValues) {
            Remove-ItemProperty -Path $kvpGuestKey -Name $valueName -ErrorAction SilentlyContinue
        }
        Write-Host "POST-SYSPREP: cleared $($kvpValues.Count) Hyper-V KVP guest exchange values"
    } else {
        Write-Host "POST-SYSPREP: Hyper-V KVP guest key not found, skipping"
    }
} catch {
    Write-Host "POST-SYSPREP: WARNING failed to reset Hyper-V KVP data: $_"
}

# Clean up Azure logs directory. The Azure agent writes here during the
# build; removing them earlier would just see new entries reappear.
Write-Host "POST-SYSPREP: cleaning up Azure logs"
try {
    if (Test-Path "C:\WindowsAzure\Logs") {
        Remove-Item "C:\WindowsAzure\Logs" -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch { }

# Disable the "New Network" location prompt. sysprep resets this reg
# tree, so the key has to be (re)created after sysprep.
Write-Host "POST-SYSPREP: disabling network discovery prompt"
New-Item -Path "HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff\" -Force -ErrorAction SilentlyContinue | Out-Null

# Randomize the built-in Administrator password but leave the account
# enabled so OOBE has a usable local account on the catlet's first boot
# (otherwise modern Windows OOBE pauses to demand one). sysprep
# /generalize re-enables Administrator as part of OOBE prep and resets
# the password, so this MUST run after sysprep.
Write-Host "POST-SYSPREP: randomizing Administrator password (account left enabled for OOBE)"
try {
    Add-Type -AssemblyName System.Web
    $adminPasswordPlain = [System.Web.Security.Membership]::GeneratePassword(30, 4)
    $adminPassword = ConvertTo-SecureString $adminPasswordPlain -AsPlainText -Force
    Get-LocalUser Administrator | Set-LocalUser -Password $adminPassword
} catch {
    Write-Host "POST-SYSPREP: WARNING failed to randomize Administrator password: $_"
}

# Disable the packer build account so it isn't usable in the captured image.
Write-Host "POST-SYSPREP: disabling packer account"
try {
    $packerAccount = Get-LocalUser packer -ErrorAction Stop
    $packerAccount | Disable-LocalUser
} catch {
    Write-Host "POST-SYSPREP: packer account not present or disable failed: $_"
}

# Zero-fill free space so the resulting VHDX compresses well.
Write-Host "POST-SYSPREP: wiping empty space on C:"
$FilePath = "C:\zero.tmp"
try {
    $Volume = Get-WmiObject win32_logicaldisk -filter "DeviceID='C:'"
    $ArraySize = 64kb
    $SpaceToLeave = $Volume.Size * 0.05
    $FileSize = $Volume.FreeSpace - $SpaceToLeave
    $ZeroArray = New-Object byte[]($ArraySize)

    $Stream = [IO.File]::OpenWrite($FilePath)
    try {
        $CurFileSize = 0
        while ($CurFileSize -lt $FileSize) {
            $Stream.Write($ZeroArray, 0, $ZeroArray.Length)
            $CurFileSize += $ZeroArray.Length
        }
    } finally {
        if ($Stream) { $Stream.Close() }
    }
} catch {
    Write-Host "POST-SYSPREP: zero-fill failed: $_"
} finally {
    if (Test-Path $FilePath) { Remove-Item $FilePath -Force -ErrorAction SilentlyContinue }
}

Write-Host "CHECKPOINT_03: Cleanup completed"

# Remove the one-shot Scheduled Task so it isn't part of the captured image.
Write-Host "POST-SYSPREP: unregistering EryphPostSysprep scheduled task"
try {
    Unregister-ScheduledTask -TaskName "EryphPostSysprep" -Confirm:$false -ErrorAction Stop
} catch {
    Write-Host "POST-SYSPREP: failed to unregister task: $_"
}

Write-Host "CHECKPOINT_04: Shutdown"
Stop-Transcript | Out-Null

Stop-Computer -Force
