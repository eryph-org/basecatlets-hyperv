param(
      [Parameter(Mandatory=$true, Position=0)]
      [string]$BasePath,

      [Parameter(Mandatory=$true, Position=1)]
      [string]$TemplateName)


$ErrorActionPreference = "Stop"

$importDir = [System.IO.Path]::Combine($BasePath,"$TemplateName-stage0")
$vmDir = [System.IO.Path]::Combine($importDir, "Virtual Machines")

$vmFile = (Get-ChildItem -Path $vmDir -Filter "*.vmcx" | Select-Object -First 1).FullName

Write-Host "Importing VM from $vmFile"
$vm = Import-VM -Path $vmFile

try{
    Write-Host "Setting processor compatibility to migration mode"
    $vm | Set-VMProcessor -CompatibilityForMigrationEnabled $true -ErrorAction Continue

    Write-Host "Renaming drives and network adapters to match catlet convention"
    $names = 'sda', 'sdb', 'sdc', 'sdd', 'sde', 'sdf', 'sdg', 'sdh', 'sdi', 'sdj', 'sdk', 'sdl', 'sdm', 'sdn', 
            'sdo', 'sdp', 'sdq', 'sdr', 'sds', 'sdt'

    $counter = -1
    Get-VMHardDiskDrive -VM $vm | ForEach-Object {
        $counter++
        if($counter -gt 19) {
            throw "Only up to 20 drives are supported"
        }

        $drive = $_
        $currentPath = $drive.Path
        $path = [System.IO.Path]::GetDirectoryName($currentPath)
        $name = $names[$counter]
        $newFileName = "$name.vhdx"
        
        $newPath = [System.IO.Path]::Combine($path, $newFileName)

        if($newPath -ne $currentPath) {
            Write-Host "Renaming disk $currentPath to $newPath"
            Move-Item $currentPath $newPath
            Set-VMHardDiskDrive -VMHardDiskDrive $drive -Path $newPath
        }
    }


    $counter = -1
    Get-VMNetworkAdapter -VM $vm  | ForEach-Object {
        $counter++

        if($_.Name -ne "eth$counter") {
            Write-Host "Renaming networkadapter to eth$counter"
            Rename-VMNetworkAdapter -VMNetworkAdapter $_ -NewName "eth$counter"
        }
    }

    $exportPath = [System.IO.Path]::Combine($BasePath,"$TemplateName-stage1")
    $vmJsonPath = [System.IO.Path]::Combine($exportPath,$TemplateName,"vm.json")
    $vmJsonOverridesPath = [System.IO.Path]::Combine($importDir,"vm-overrides.json")

    Write-Host "Exporting VM settings"
    $vmData = @{
        vm = $vm
        firmware  = $vm | Get-VMFirmware
        processor = $vm | Get-VMProcessor
        security = $vm | Get-VMSecurity -ErrorAction SilentlyContinue
    }

    $overrideData = @{}
    if((Test-Path $vmJsonOverridesPath) -eq $true){
        Write-Host "VM settings overrides found - using overrides from $vmJsonOverridesPath"
        $overrideData = Get-Content -Path $vmJsonOverridesPath | ConvertFrom-Json
    
        if($overrideData.security){
            if($overrideData.security."TpmEnabled"){
                Write-Host "Setting TpmEnabled to $($overrideData.security."TpmEnabled")"
                $overrideData.security."TpmEnabled" = $overrideData.security."TpmEnabled"
            }
        }
        if($overrideData.vm){
            if($overrideData.vm."MemoryStartup"){
                Write-Host "Setting MemoryStartup to $($overrideData.vm."MemoryStartup")"
                $overrideData.vm."MemoryStartup" = $overrideData.vm."MemoryStartup"
            }
            if($overrideData.vm."ProcessorCount"){
                Write-Host "Setting ProcessorCount to $($overrideData.vm."ProcessorCount")"
                $overrideData.vm."ProcessorCount" = $overrideData.vm."ProcessorCount"
            }
        }
    }

    Write-Host "Exporting VM..."
    $vm | Export-VM -Path $exportPath   
    $vmData | ConvertTo-Json -Depth 3 | Set-Content -Path $vmJsonPath
    
    
    if((Test-Path "$importDir\metadata.json") -eq $true){
        Write-Host "Exporting Metadata..."
        Copy-Item "$importDir\metadata.json" "$exportPath\metadata.json"
    }


}
finally{
    Write-Host "Cleaning up"
    $vm | Remove-VM -Force
    Remove-Item $importDir -Recurse -Force
    
    $snapshotPath = [System.IO.Path]::Combine($exportPath,$TemplateName,"Snapshots")
    Remove-Item $snapshotPath -Recurse -Force -ErrorAction SilentlyContinue
}

