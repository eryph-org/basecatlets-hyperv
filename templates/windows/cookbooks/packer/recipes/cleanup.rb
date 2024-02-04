
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

powershell_script 'remove unnecesary directories' do
  code <<-EOH
  @(
      "C:\\Recovery",
      "$env:localappdata\\temp\\*",
      "$env:windir\\logs",
      "$env:windir\\temp",
      "$env:windir\\winsxs\\manifestcache"
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
  EOH
end

# clean all of the event logs
%w(Application Security Setup System).each do |log|
  execute "Cleaning the #{log} event log" do
    command "wevtutil clear-log #{log}"
  end
end
