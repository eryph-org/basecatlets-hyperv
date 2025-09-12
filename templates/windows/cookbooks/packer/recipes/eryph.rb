powershell_script 'install eryph guest services' do
  code <<-EOH
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 3.0
    # Expand-Archive is a script module and will take its preferences from the global scope.
    # See https://github.com/PowerShell/Microsoft.PowerShell.Archive/issues/77#issuecomment-601947496
    $global:ProgressPreference = 'SilentlyContinue'

    if ([System.Net.ServicePointManager]::SecurityProtocol -ne 0) {
      [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    }

    $productInfo = Invoke-RestMethod -Uri 'https://releases.dbosoft.eu/eryph/guest-services/index.json' -UseBasicParsing
    $version = & { Set-StrictMode -Off; $productInfo.stableVersion }
    if (-not $version) {
      $version = $productInfo.latestVersion
    }
 
    $versionInfo = & { Set-StrictMode -Off; $productInfo.versions.$version }
    if (-not $versionInfo) {
      throw "Version '$requestedVersion' does not exist"
    }

    $fileInfo = $versionInfo.files | Where-Object { `
      $_.filename -like 'egs_*' `
      -and $_.PSObject.Properties.Name -contains 'os' `
      -and $_.PSObject.Properties.Name -contains 'arch' `
      -and $_.os -eq 'windows' `
      -and $_.arch -eq 'amd64' } | Select-Object -First 1
      
    $downloadUrl = $fileInfo.url

    Invoke-WebRequest -Uri $downloadUrl -OutFile C:\\egs-windows.zip -UseBasicParsing

    Expand-Archive -Path C:\\egs-windows.zip -DestinationPath "C:\\Program Files\\eryph\\guest-services"
    Remove-Item -Path C:\\egs-windows.zip

    sc.exe create eryph-guest-services start=auto binpath="C:\\Program Files\\eryph\\guest-services\\bin\\egs-service.exe"
    sc.exe failure eryph-guest-services reset=60 actions=restart/10000
    sc.exe start eryph-guest-services
    EOH
end