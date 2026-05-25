[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]
    $Filter,

    [Parameter(Mandatory=$false)]
    [ValidateSet('packer','libvirt')]
    [string]
    $Method
)

Push-Location $PSScriptRoot
$ErrorActionPreference = 'Stop'

# build.json is grouped by build method, then by OS type, e.g.:
#   { "packer":  { "windows": [...] },
#     "libvirt": { "ubuntu": [...], "rhel-compatible": [...] } }
# packer  → existing two-stage flow (templates/<osType>/build.ps1 + catletlify).
# libvirt → cloud-image-customize flow (templates/linux/build-cloud.ps1).
$buildJson = Get-Content -Raw -Path "build.json" | ConvertFrom-Json

$results = @()

foreach ($methodProp in $buildJson.PSObject.Properties) {
    $methodName = $methodProp.Name
    if ($Method -and $methodName -ne $Method) { continue }

    $osGroups = $methodProp.Value
    foreach ($osTypeProp in $osGroups.PSObject.Properties) {
        $osType    = $osTypeProp.Name
        $templates = $osTypeProp.Value

        foreach ($template in $templates) {
            if ($Filter -and $template -notlike $Filter) { continue }

            Write-Host ""
            Write-Host "================================================================"
            Write-Host "  [$methodName/$osType] $template"
            Write-Host "================================================================"
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $status = 'OK'
            $errMsg = ''

            try {
                switch ($methodName) {
                    'packer' {
                        Join-Path ./templates $osType | Push-Location
                        try {
                            ./build.ps1 -Template_name $template
                        } finally {
                            Pop-Location
                        }
                        .\tools\catletlify.ps1 -BasePath .\builds -TemplateName $template

                        # Emit qcow2 alongside each vhdx — one build, two formats.
                        # The kernel inside the disk works on both Hyper-V and KVM
                        # (linux-azure / RHEL-default include the hv_* drivers but
                        # are not Hyper-V-exclusive). No re-build needed.
                        $stage1 = ".\builds\$template-stage1"
                        if (Test-Path $stage1) {
                            Get-ChildItem -Path $stage1 -Filter '*.vhdx' -Recurse | ForEach-Object {
                                $qcowPath = $_.FullName -replace '\.vhdx$', '.qcow2'
                                if (-not (Test-Path $qcowPath)) {
                                    Write-Host "  Converting $($_.Name) -> $(Split-Path $qcowPath -Leaf) ..."
                                    & qemu-img convert -O qcow2 $_.FullName $qcowPath
                                }
                            }
                        }
                    }
                    'libvirt' {
                        & .\templates\linux\build-cloud.ps1 -Template_name $template -ConvertVhdx
                    }
                    default { throw "unknown method: $methodName" }
                }
            } catch {
                $status = 'FAIL'
                $errMsg = $_.Exception.Message
                Write-Warning "[$methodName/$osType] $template FAILED: $errMsg"
            }

            $sw.Stop()
            $results += [PSCustomObject]@{
                Method   = $methodName
                OsType   = $osType
                Template = $template
                Status   = $status
                Seconds  = [math]::Round($sw.Elapsed.TotalSeconds, 1)
                Error    = $errMsg
            }
        }
    }
}

Pop-Location

Write-Host ""
Write-Host "================================================================"
Write-Host "  Build summary"
Write-Host "================================================================"
$results | Format-Table -AutoSize
$failCount = ($results | Where-Object Status -eq 'FAIL').Count
if ($failCount -gt 0) {
    Write-Warning "$failCount build(s) failed."
    exit 1
}
