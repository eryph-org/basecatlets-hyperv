param(
      [Parameter(Mandatory=$true, Position=0)]
      [string]$BasePath,

      [Parameter(Mandatory=$true, Position=1)]
      [string]$TemplateName)

$ErrorActionPreference = "Stop"

$importDir = [System.IO.Path]::Combine($BasePath,"$TemplateName-stage0")
$vmDir = [System.IO.Path]::Combine($importDir, "Virtual Machines")

$vmFile = (Get-ChildItem -Path $vmDir -Filter "*.vmcx" | Select-Object -First 1).FullName

$vm = Import-VM -Path $vmFile

$vm | Set-VMProcessor -CompatibilityForMigrationEnabled $true -ErrorAction Continue

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
$vm | Export-VM -Path $exportPath
$vm | Remove-VM -Force
Remove-Item $importDir -Recurse -Force

$snapshotPath = [System.IO.Path]::Combine($exportPath,$TemplateName,"Snapshots")
Remove-Item $snapshotPath -Recurse -Force


