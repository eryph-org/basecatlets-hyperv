# Specialize-pass Azure orchestration.
#
# Built images keep WindowsAzureGuestAgent + RdAgent Disabled so they don't
# waste CPU/network probing WireServer on Hyper-V/eryph deployments. On Azure
# we enable them here.
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
    } else {
        Write-Log "non-Azure environment, agent services remain Disabled"
    }
} catch {
    Write-Log "unhandled error: $_"
}
