# Specialize-pass Azure orchestration.
#
# Built images keep WindowsAzureGuestAgent + RdAgent Disabled so they don't
# waste CPU/network probing WireServer on Hyper-V/eryph deployments. On Azure
# we enable them here. We ALSO defer the cloudbase-init service: on Azure it
# must not auto-start on the post-specialize-reboot boot, because then it
# would race with Microsoft's PA SetupComplete.cmd chain and request its own
# reboot, killing the PA mid-flight. Instead we set cloudbase-init to
# Disabled here, and drop C:\Windows\OEM\SetupComplete2.cmd -- a hook
# Microsoft's own OEM\SetupComplete.cmd tail-calls *after* the PA's
# /ConfigurationPass:oobeSystem invocation has called ReportReady.
# On non-Azure deploys (eryph/Hyper-V) cloudbase-init is left at its default
# Automatic start so behaviour is unchanged.
#
# Invoked once from Unattend.xml during the specialize pass on first boot.

$ErrorActionPreference = 'Continue'
$logPath = 'C:\Windows\Setup\Scripts\azure-detect.log'
$azureAssetTag = '7783-7084-3265-9085-8269-3286-77'

function Write-Log {
    param([string]$Message)
    "$((Get-Date).ToString('o')) $Message" | Out-File -FilePath $logPath -Append -Encoding utf8
}

try {
    Write-Log "starting"

    $assetTag = $null
    try {
        $assetTag = (Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue).SMBIOSAssetTag
    } catch {
        Write-Log "failed to read SMBIOSAssetTag: $_"
    }
    Write-Log "SMBIOSAssetTag='$assetTag'"

    if ($assetTag -eq $azureAssetTag) {
        Write-Log "Azure environment detected, enabling agent services"
        foreach ($svc in @('WindowsAzureGuestAgent', 'RdAgent', 'WindowsAzureTelemetryService')) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $svc -ErrorAction SilentlyContinue
                Write-Log "$svc set to Automatic and started"
            } else {
                Write-Log "$svc not present, skipping"
            }
        }

        # On Azure, defer cloudbase-init service start until Microsoft's PA
        # (delivered via the ConfigDrive ISO) has finished its oobeSystem pass
        # and reported OS-provisioning-complete back to ARM. Otherwise
        # cloudbase-init's auto-start on the post-specialize-reboot boot
        # competes with windeploy.exe running C:\Windows\OEM\SetupComplete.cmd,
        # the PA's WaGuest.exe hits ERROR_SHUTDOWN_IN_PROGRESS, and OS
        # provisioning never signals -> ARM times out at 40 min.
        $cbi = Get-Service -Name 'cloudbase-init' -ErrorAction SilentlyContinue
        if ($cbi) {
            Set-Service -Name 'cloudbase-init' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "cloudbase-init set to Disabled (will be re-enabled by OEM\SetupComplete2.cmd after PA finishes)"
        } else {
            Write-Log "cloudbase-init service not present, skipping defer"
        }

        # Microsoft's OEM\SetupComplete.cmd (copied to C:\Windows\OEM\ by
        # ConfigDrive Install.cmd in specialize Order 3) tail-calls
        # OEM\SetupComplete2.cmd if it exists -- *after* cscript Unattend.wsf
        # /ConfigurationPass:oobeSystem has reported ReportReady. This is our
        # post-PA insertion point: re-enable cloudbase-init and start it.
        # cloudbase-init can then process customData / set hostname / reboot
        # freely without colliding with the PA chain.
        $oemDir = 'C:\Windows\OEM'
        if (Test-Path $oemDir) {
            $sc2 = Join-Path $oemDir 'SetupComplete2.cmd'
            $sc2Body = @'
@ECHO OFF
ECHO [eryph] Re-enabling cloudbase-init service after PA oobeSystem completed >> %windir%\Panther\WaSetup.log
sc config cloudbase-init start= auto >> %windir%\Panther\WaSetup.log
sc start cloudbase-init >> %windir%\Panther\WaSetup.log
'@
            [System.IO.File]::WriteAllText($sc2, $sc2Body, [System.Text.Encoding]::ASCII)
            Write-Log "wrote $sc2"
        } else {
            Write-Log "WARNING: $oemDir does not exist; SetupComplete2.cmd not written. PA chain may not have run."
        }
    } else {
        Write-Log "non-Azure environment, services remain Disabled, cloudbase-init untouched"
    }
} catch {
    Write-Log "unhandled error: $_"
}
