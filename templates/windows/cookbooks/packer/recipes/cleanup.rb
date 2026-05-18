
if windows_workstation? && !node['platform_version'].to_i == 10 # cleanmgr isn't on servers
  # registry key locations pulled from https://github.com/spjeff/spadmin/blob/master/Cleanmgr.ps1
  # thanks @spjeff!
  registry_key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Update Cleanup' do
    values [{
      name: 'StateFlags0001',
      type: :dword,
      data: 2,
    }]
  end

  registry_key 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Files' do
    values [{
      name: 'StateFlags0001',
      type: :dword,
      data: 2,
    }]
  end

  execute 'run cleanmgr' do
    command 'C:\Windows\System32\cleanmgr.exe /sagerun:1'
    ignore_failure true
    live_stream true
  end
end

execute 'clean SxS' do
  command 'Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase'
  ignore_failure true
  live_stream true
end

# Stop Azure services for cleanup
%w(WindowsAzureGuestAgent WindowsAzureTelemetryService RdAgent).each do |azure_service|
  service azure_service do
    action :stop
    ignore_failure true
  end
end

powershell_script 'remove unnecesary directories' do
  code <<-EOH
  @(
      "C:\\Recovery",
      "$env:localappdata\\temp\\*",
      "$env:windir\\logs",
      "$env:windir\\winsxs\\manifestcache",
      "C:\\WindowsAzure\\Logs",
      "C:\\Packages\\Plugins",
      "C:\\Windows\\Panther\\FastCleanup"
  ) | % {
          if(Test-Path $_) {
              Write-Host "Removing $_"
              try {
                Takeown /d Y /R /f $_
                Icacls $_ /GRANT:r administrators:F /T /c /q  2>&1 | Out-Null
                Remove-Item $_ -Recurse -Force | Out-Null
              } catch { $global:error.RemoveAt(0) }
          }
      }

  # Clean Windows Temp but exclude packer* files (those are handled by prepare_sysprep.ps1)
  Write-Host "Cleaning Windows Temp (excluding packer files)..."
  Get-ChildItem -Path "$env:windir\\temp" -Exclude "packer*" -ErrorAction SilentlyContinue | % {
      try {
        Takeown /d Y /R /f $_.FullName
        Icacls $_.FullName /GRANT:r administrators:F /T /c /q  2>&1 | Out-Null
        Remove-Item $_.FullName -Recurse -Force | Out-Null
      } catch { $global:error.RemoveAt(0) }
  }
  EOH
end

# Uninstall Git for Windows (installed for patching)
windows_package 'git' do
  action :remove
  ignore_failure true
end

# clean all of the event logs
%w(Application Security Setup System).each do |log|
  execute "Cleaning the #{log} event log" do
    command "wevtutil clear-log #{log}"
  end
end

# Copy sysprep script to temp directory after cleanup
cookbook_file 'C:\Windows\Temp\sysprep.ps1' do
  source 'sysprep.ps1'
  action :create
end
