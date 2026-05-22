#Requires -Version 7.4
<#
.SYNOPSIS
  Build a Linux catlet image from an upstream cloud image (cloud-image-customize flow).

.DESCRIPTION
  Two execution modes, picked automatically:
    - Linux host: runs templates/linux/build.sh directly.
    - Windows host: drives a Linux build catlet via egs-tool + ssh.
      Uploads templates/linux/ in one shot, runs build.sh, downloads the
      artifact directory back.

  Replaces installer-based Packer flows for Linux templates. Per-template
  support gated inside build.sh — currently: ubuntu-* and almalinux-*;
  oracle-* not yet supported.

.PARAMETER Template_name
  ubuntu-XX.XX | almalinux-N | oracle-N.

.PARAMETER BuildCatlet
  Name of the build-host catlet (Windows mode). Defaults to 'hyperv-boxes-build'
  in 'default' project; see templates/build-host/catlet.yaml.

.PARAMETER ConvertVhdx
  Emit sda.vhdx alongside sda.qcow2 (Hyper-V variant).
#>
param(
  [Parameter(Mandatory=$true, Position=0)]
  [string]$Template_name,

  [string]$BuildCatlet  = 'hyperv-boxes-build',
  [string]$BuildProject = 'default',
  [ValidateSet('azure','generic','default')]
  [string]$Kernel = 'azure',
  [switch]$NoWalinuxAgent,
  [switch]$DistUpgrade,
  [switch]$ConvertVhdx
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repoRoot  = (Resolve-Path "$PSScriptRoot\..\..").Path
$buildsDir = Join-Path $repoRoot 'builds'
$cacheDir  = Join-Path $repoRoot 'packer_cache'
$linuxDir  = Join-Path $repoRoot 'templates/linux'
$buildSh   = Join-Path $linuxDir 'build.sh'

if (-not (Test-Path $buildSh)) { throw "missing $buildSh" }
New-Item -ItemType Directory -Path $buildsDir -Force | Out-Null
New-Item -ItemType Directory -Path $cacheDir  -Force | Out-Null

# Shared arg list — no quoting concerns since none of these contain shell metachars.
function Build-Args {
  param([string]$OutputDir, [string]$CacheDir)
  $a = @('--template', $Template_name, '--output-dir', $OutputDir, '--cache-dir', $CacheDir, '--kernel', $Kernel)
  if ($NoWalinuxAgent) { $a += '--no-walinuxagent' }
  if ($DistUpgrade)    { $a += '--dist-upgrade' }
  if ($ConvertVhdx)    { $a += '--convert-vhdx' }
  return $a
}

# ---------- Linux native path ----------
if ($IsLinux) {
  Write-Host "Linux host detected — running build.sh directly."
  foreach ($t in 'virt-customize','virt-sparsify','qemu-img','curl','sha256sum') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
      throw "$t not found in PATH (apt install libguestfs-tools qemu-utils curl)"
    }
  }
  & bash $buildSh @(Build-Args -OutputDir $buildsDir -CacheDir $cacheDir)
  if ($LASTEXITCODE -ne 0) { throw "build.sh exit $LASTEXITCODE" }
  Write-Host "Build complete: $buildsDir/$Template_name-stage1"
  return
}

# ---------- Windows host: drive via build catlet ----------
Write-Host "Windows host — driving build catlet '$BuildCatlet' in project '$BuildProject'."

if (-not (Get-Module -ListAvailable -Name Eryph.ComputeClient)) {
  throw "Eryph.ComputeClient PowerShell module required. Install-Module Eryph.ComputeClient -Scope CurrentUser"
}
Import-Module Eryph.ComputeClient
foreach ($t in 'egs-tool','ssh.exe') {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t not found in PATH" }
}

$catlet = Get-Catlet -ProjectName $BuildProject -ErrorAction SilentlyContinue |
            Where-Object Name -eq $BuildCatlet | Select-Object -First 1
if (-not $catlet) {
  throw @"
Build catlet '$BuildCatlet' not found in project '$BuildProject'. Create it with:
  New-Catlet -Name $BuildCatlet -ProjectName $BuildProject ``
    -Config (Get-Content -Raw $repoRoot\templates\build-host\catlet.yaml)
"@
}
Write-Host "Build catlet: $($catlet.Name) Id=$($catlet.Id) VmId=$($catlet.VmId)"

# Start + wait for cloud-init/egs.
$cutoff = (Get-Date).AddMinutes(10)
Write-Host "Starting catlet..."
while ($true) {
  try { Start-Catlet -Id $catlet.Id -Force; break }
  catch { if ((Get-Date) -gt $cutoff) { throw "Start-Catlet timed out: $_" }; Start-Sleep -Seconds 5 }
}
egs-tool update-ssh-config | Out-Null

Write-Host "Waiting for cloud-init + egs..."
while ($true) {
  try {
    $vmData = egs-tool get-data --json $catlet.VmId | ConvertFrom-Json -AsHashtable
    $done = $vmData.guest.Keys | Where-Object {
      $_ -like 'CLOUD_INIT|*|finish|modules-final|*' -or
      $_ -like 'CLOUDBASE_INIT|0|provisioning|completed|*'
    } | Where-Object {
      $e = $vmData.guest[$_]
      ($e -is [hashtable] -and $e.result -eq 'SUCCESS') -or ($e -eq 'completed')
    } | Select-Object -First 1
    if (-not $done) { throw 'cloud-init not finished' }
    if ((egs-tool get-status $catlet.VmId) -ne 'available') { throw 'egs not available' }
    egs-tool add-ssh-config $catlet.VmId | Out-Null
    $null = & ssh.exe -o BatchMode=yes "$($catlet.Id).eryph.alt" true
    if ($LASTEXITCODE -ne 0) { throw 'ssh probe failed' }
    break
  } catch {
    if ((Get-Date) -gt $cutoff) { throw "catlet not ready: $_" }
    Start-Sleep -Seconds 5
  }
}

$sshHost    = "$($catlet.Id).eryph.alt"
$runId      = Get-Date -Format 'yyyyMMddHHmmss'
$remoteRoot = "/var/tmp/hyperv-boxes-build/$runId"
$remoteLinux= "$remoteRoot/linux"
$remoteOut  = "$remoteRoot/output"
$remoteCache= "/var/tmp/hyperv-boxes-build/cache"   # persisted across runs

Write-Host "Remote root: $remoteRoot"
Write-Host "Uploading templates/linux/ ..."
egs-tool upload-directory --recursive --overwrite $catlet.VmId $linuxDir $remoteLinux
if ($LASTEXITCODE -ne 0) { throw "upload-directory failed" }

Write-Host "Running build.sh on catlet..."
$args = (Build-Args -OutputDir $remoteOut -CacheDir $remoteCache) -join ' '
& ssh $sshHost "sudo bash $remoteLinux/build.sh $args" 2>&1 | ForEach-Object { "[catlet] $_" }
$buildExit = $LASTEXITCODE

# Always fetch build.log (success or failure) so it's locally inspectable.
# build.sh writes its full output (including virt-customize -v -x trace) to
# $remoteOut/build.log via `exec > >(tee -a "$BUILD_LOG") 2>&1`.
$logName  = if ($buildExit -eq 0) { "build-$Template_name-$runId.log" } else { "build-failure-$Template_name-$runId.log" }
$localLog = Join-Path $buildsDir $logName
egs-tool download-file $catlet.VmId "$remoteOut/build.log" $localLog 2>&1 | Out-Null
if (Test-Path $localLog) {
  Write-Host "build.log: $localLog"
} else {
  Write-Warning "build.log NOT retrievable from $remoteOut/build.log — build.sh may have died before opening the log (early arg parse or family dispatch failure). Re-run with extra ssh diagnostics if reproducible."
}

if ($buildExit -ne 0) {
  if (Test-Path $localLog) {
    Write-Host "--- last 60 lines of build.log ---"
    Get-Content $localLog -Tail 60 | ForEach-Object { Write-Host "[catlet] $_" }
  }
  throw "build.sh failed on catlet (exit $buildExit)"
}

Write-Host "Downloading artifacts ..."
$localStage = Join-Path $buildsDir "$Template_name-stage1"
if (Test-Path $localStage) { Remove-Item -Recurse -Force $localStage }
New-Item -ItemType Directory -Path $localStage -Force | Out-Null
egs-tool download-directory --recursive --overwrite $catlet.VmId "$remoteOut/$Template_name-stage1" $localStage
if ($LASTEXITCODE -ne 0) { throw "download-directory failed" }

# Defensive: if the vhdx came across with the NTFS sparse attribute set, clear
# it so Hyper-V can attach it (avoids 0xC03A001A). The vhdx now lives under
# hyperv/amd64/ rather than directly in stage0.
$vhdxPath = Join-Path $localStage 'hyperv\amd64\sda.vhdx'
if (Test-Path $vhdxPath) {
  $flag = (& fsutil sparse queryflag $vhdxPath) 2>&1
  if ($flag -match 'festgelegt' -and $flag -notmatch 'NICHT') {
    Write-Host "Clearing NTFS sparse attribute on sda.vhdx..."
    & fsutil sparse setflag $vhdxPath 0 | Out-Null
  }
}

# Per-run workdir cleanup; keep persistent cache.
& ssh $sshHost "sudo rm -rf $remoteRoot" | Out-Null

Write-Host "Build complete: $localStage"
Get-ChildItem $localStage | Format-Table Name, Length -AutoSize
