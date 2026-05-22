
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Write-Host
    Exit 1
}

Start-Transcript -Path C:\Windows\Temp\sysprep.log -Append


Write-Host "Cleaning Temp Files..."
try {
  Takeown /d Y /R /f "C:\Windows\Temp\*"
  Icacls "C:\Windows\Temp\*" /GRANT:r administrators:F /T /c /q  2>&1
  # Preserve post-sysprep.ps1 (the SYSTEM task script) and sysprep.log
  # (transcript both scripts append to); everything else goes.
  Get-ChildItem "C:\Windows\Temp" -Force -ErrorAction SilentlyContinue `
      -Exclude "post-sysprep.ps1","sysprep.log" |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

Write-Host "CHECKPOINT_01 Preparing sysprep"

# Everything that sysprep itself undoes or rewrites (Administrator
# re-enabled by /generalize, KVP guest exchange data refreshed by the
# Integration Services, Azure logs regenerated, NewNetworkWindowOff reg
# key reset) lives in post-sysprep.ps1, which runs as SYSTEM via a
# Scheduled Task and is therefore immune to the WinRM logon teardown
# that sysprep performs.

# remove page file - disabled for now as there is currently no automatic re-enable on first boot

#$privileges = Get-WmiObject -Class Win32_computersystem -EnableAllPrivileges
#$privileges.AutomaticManagedPagefile = $false
#$privileges.Put()

#$pagefile = Get-WmiObject -Query "select * from Win32_PageFileSetting where name='c:\\pagefile.sys'"
#$pagefile.Delete()

# --- register post-sysprep SYSTEM task -----------------------------------
# A one-shot Scheduled Task running as NT AUTHORITY\SYSTEM picks up after
# sysprep finishes. SYSTEM survives the logon teardown sysprep /generalize
# performs on the WinRM session, so the cleanup and shutdown reliably run
# even when this foreground pipeline is killed mid-sysprep.
#
# The trigger fires ~1 minute after registration; post-sysprep.ps1 itself
# waits for Sysprep_succeeded.tag before doing anything destructive, so
# the task tolerates sysprep still being in flight when it starts.
Write-Host "Registering post-sysprep scheduled task (runs as SYSTEM)..."
$postSysprepScript = "C:\Windows\Temp\post-sysprep.ps1"
if (-not (Test-Path $postSysprepScript)) {
    Write-Error "post-sysprep.ps1 not found at $postSysprepScript" -ErrorAction Stop
}

$taskAction    = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$postSysprepScript`""
$taskTrigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
                    -LogonType ServiceAccount -RunLevel Highest
$taskSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 18) `
                    -StartWhenAvailable

Register-ScheduledTask -TaskName "EryphPostSysprep" `
                       -Action $taskAction -Trigger $taskTrigger `
                       -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

Write-Host "Starting sysprep"

# Stop the Windows Search service so the MSSrch_SysPrep_Cleanup provider can
# create HKLM\SOFTWARE\Microsoft\Windows Search\PreventFromStart without
# losing a race against SearchIndexer.exe (intermittent 0x5 / 0x7a failures).
Stop-Service WSearch -Force -ErrorAction SilentlyContinue

if (Test-Path "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml") {
    & c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet /unattend:"C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
}
else {
    & c:\windows\system32\sysprep\sysprep.exe /oobe /generalize /quit /mode:vm /quiet
}

# Poll for sysprep completion so Packer's build log shows sysprep errors
# directly. The historic "pipeline has been stopped" failures hit the
# *post-sysprep* work that used to follow this loop -- the poll itself
# usually survives, and on success we now just hand off to the SYSTEM
# task instead of doing more work in this fragile session.
$sysprep_succeded = Test-Path c:\Windows\System32\Sysprep\Sysprep_succeeded.tag
$timeLeft = 900
$waits = 0
while ($sysprep_succeded -ne $true) {
    Write-Host "Waiting for sysprep... ($timeLeft seconds left)"
    $waits++
    Start-Sleep -Seconds 10
    $timeLeft -= 10
    $sysprep_succeded = Test-Path c:\Windows\System32\Sysprep\Sysprep_succeeded.tag
    if ($waits -ge 90) {
        break
    }
}

if ($sysprep_succeded -ne $true) {
    Write-Host "Sysprep error log content:"
    Get-Content "c:\Windows\System32\Sysprep\Panther\setuperr.log" -ErrorAction Continue

    Write-Host "Sysprep log content:"
    Get-Content "c:\Windows\System32\Sysprep\Panther\setupact.log" -ErrorAction Continue

    # Drop the scheduled task so a doomed build doesn't accidentally shut
    # the VM down later and obscure the failure for debugging.
    Unregister-ScheduledTask -TaskName "EryphPostSysprep" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    Write-Error "Sysprep failed" -ErrorAction Stop
    return -1
}

Write-Host "Sysprep completed in WinRM session; handing off to SYSTEM task for cleanup and shutdown"
# Note: CHECKPOINT_02 is emitted by post-sysprep.ps1 (SYSTEM context) so it
# is reliably written even if this WinRM pipeline is torn down mid-poll.
Stop-Transcript -ErrorAction SilentlyContinue
