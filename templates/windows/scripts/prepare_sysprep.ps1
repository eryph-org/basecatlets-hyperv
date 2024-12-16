Write-Host "Uninstalling Chef..."
$app = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -match "Chef"
}

if($app){ $app.Uninstall() }

Write-Host "Removing leftover Chef files..."
Remove-Item "C:\Opscode\" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Chef\" -Recurse -Force -ErrorAction SilentlyContinue

# disable autologon for packer user
set-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon' -Value 0

Write-Host "Removing appx packages for current user"

# prevent appx issue: https://learn.microsoft.com/de-de/troubleshoot/windows-client/deployment/sysprep-fails-remove-or-update-store-apps
$packages = Get-AppxPackage
$packages | Remove-AppxPackage -ErrorAction SilentlyContinue | Out-Null

Get-AppXProvisionedPackage -Online | ForEach-Object {
    Write-Host "Removing the $($_.PackageName) provisioned appx package..."
    try {
        $_ | Remove-AppxProvisionedPackage -Online | Out-Null
    } catch {
        Write-Output "WARN Failed to remove appx: $_"
    }
}

Write-Host "Optimizing Drive"
Optimize-Volume -DriveLetter C

# embedded shutdown script, encoded in base64 to avoid issues with script interpretation
$script = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(
@"
ClNldC1TdHJpY3RNb2RlIC1WZXJzaW9uIExhdGVzdAokUHJvZ3Jlc3NQcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcKdHJhcCB7CiAgICBXcml0ZS1Ib3N0CiAgICBXcml0ZS1Ib3N0ICJFUlJPUjogJF8iCiAgICAoJF8uU2NyaXB0U3RhY2tUcmFjZSAtc3BsaXQgJ1xyP1xuJykgLXJlcGxhY2UgJ14oLiopJCcsJ0VSUk9SOiAkMScgfCBXcml0ZS1Ib3N0CiAgICAoJF8uRXhjZXB0aW9uLlRvU3RyaW5nKCkgLXNwbGl0ICdccj9cbicpIC1yZXBsYWNlICdeKC4qKSQnLCdFUlJPUiBFWENFUFRJT046ICQxJyB8IFdyaXRlLUhvc3QKICAgIFdyaXRlLUhvc3QKICAgIEV4aXQgMQp9CgpTdGFydC1UcmFuc2NyaXB0IC1QYXRoIEM6XFdpbmRvd3NcVGVtcFxzeXNwcmVwLmxvZyAtQXBwZW5kCgoKV3JpdGUtSG9zdCAiQ2xlYW5pbmcgVGVtcCBGaWxlcy4uLiIKdHJ5IHsKICBUYWtlb3duIC9kIFkgL1IgL2YgIkM6XFdpbmRvd3NcVGVtcFwqIgogIEljYWNscyAiQzpcV2luZG93c1xUZW1wXCoiIC9HUkFOVDpyIGFkbWluaXN0cmF0b3JzOkYgL1QgL2MgL3EgIDI+JjEKICBSZW1vdmUtSXRlbSAiQzpcV2luZG93c1xUZW1wXCoiIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQp9IGNhdGNoIHsgfQoKV3JpdGUtSG9zdCAiQ0hFQ0tQT0lOVF8wMSBQcmVwYXJpbmcgc3lzcHJlcCIKCgojVGFrZW93biAvRiAiQzpcV2luZG93c1xTeXN0ZW0zMlxTeXNwcmVwXEFjdGlvbkZpbGVzXEdlbmVyYWxpemUueG1sIgojSWNhY2xzICJDOlxXaW5kb3dzXFN5c3RlbTMyXFN5c3ByZXBcQWN0aW9uRmlsZXNcR2VuZXJhbGl6ZS54bWwiIC9HUkFOVDpyIGFkbWluaXN0cmF0b3JzOkYgL1QgL2MgL3EgIDI+JjEKIyRnZW5lcmFsaXplQ29udGVudCA9IEdldC1Db250ZW50IEM6XFdpbmRvd3NcU3lzdGVtMzJcU3lzcHJlcFxBY3Rpb25GaWxlc1xHZW5lcmFsaXplLnhtbAoKIyBwYXRjaCBnZW5lcmFsaXplLnhtbCBmb3IgZXJyb3Igd2l0aCBWQU4gcmVnaXN0cnkga2V5IGluIFdpbmRvd3MgU2VydmVyIDIwMTYKIyRnZW5lcmFsaXplQ29udGVudCA9ICRnZW5lcmFsaXplQ29udGVudC5SZXBsYWNlKCdIS0VZX0NVUlJFTlRfVVNFUlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxWQU5cezc3MjRGNUI0LTlBNEEtNGE5My1BRDA5LUIwNkY3QUIzMTAzNX0nLCAnSEtFWV9MT0NBTF9NQUNISU5FXFNPRlRXQVJFXE1pY3Jvc29mdFxXaW5kb3dzXEN1cnJlbnRWZXJzaW9uXFZBTlx7NzcyNEY1QjQtOUE0QS00YTkzLUFEMDktQjA2RjdBQjMxMDM1fScpCiMkZ2VuZXJhbGl6ZUNvbnRlbnQgfCBTZXQtQ29udGVudCAtUGF0aCBDOlxXaW5kb3dzXFN5c3RlbTMyXFN5c3ByZXBcQWN0aW9uRmlsZXNcR2VuZXJhbGl6ZS54bWwKI2ljYWNscyAiQzpcV2luZG93c1xTeXN0ZW0zMlxTeXNwcmVwXEFjdGlvbkZpbGVzXEdlbmVyYWxpemUueG1sIiAvc2V0b3duZXIgIk5UIFNlcnZpY2VcVHJ1c3RlZEluc3RhbGxlciIKCldyaXRlLUhvc3QgIlN0YXJ0aW5nIHN5c3ByZXAiCgppZihUZXN0LVBhdGggIkM6XFByb2dyYW0gRmlsZXNcQ2xvdWRiYXNlIFNvbHV0aW9uc1xDbG91ZGJhc2UtSW5pdFxjb25mXFVuYXR0ZW5kLnhtbCIpCnsKICAgICZjOlx3aW5kb3dzXHN5c3RlbTMyXHN5c3ByZXBcc3lzcHJlcC5leGUgL29vYmUgL2dlbmVyYWxpemUgL3F1aXQgL21vZGU6dm0gL3F1aWV0IC91bmF0dGVuZDoiQzpcUHJvZ3JhbSBGaWxlc1xDbG91ZGJhc2UgU29sdXRpb25zXENsb3VkYmFzZS1Jbml0XGNvbmZcVW5hdHRlbmQueG1sIgp9CmVsc2UgewogICAgJmM6XHdpbmRvd3Ncc3lzdGVtMzJcc3lzcHJlcFxzeXNwcmVwLmV4ZSAvb29iZSAvZ2VuZXJhbGl6ZSAvcXVpdCAvbW9kZTp2bSAvcXVpZXQKfQoKJHN5c3ByZXBfc3VjY2VkZWQgPSBUZXN0LVBhdGggYzpcV2luZG93c1xTeXN0ZW0zMlxTeXNwcmVwXFN5c3ByZXBfc3VjY2VlZGVkLnRhZwoKJHRpbWVMZWZ0ID0gOTAwCiR3YWl0cyA9IDAKd2hpbGUoJHN5c3ByZXBfc3VjY2VkZWQgLW5lICR0cnVlKXsKICAgIAogICAgV3JpdGUtSG9zdCAiV2FpdGluZyBmb3Igc3lzcHJlcC4uLiAoJHRpbWVMZWZ0IHNlY29uZHMgbGVmdCkiCiAgICAkd2FpdHMrKwogICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMTAKICAgICR0aW1lTGVmdC09MTAKICAgICRzeXNwcmVwX3N1Y2NlZGVkID0gVGVzdC1QYXRoIGM6XFdpbmRvd3NcU3lzdGVtMzJcU3lzcHJlcFxTeXNwcmVwX3N1Y2NlZWRlZC50YWcKICAgIGlmKCR3YWl0cyAtZ2UgOTApewogICAgICAgIGJyZWFrCiAgICB9Cn0KCmlmKCRzeXNwcmVwX3N1Y2NlZGVkIC1uZSAkdHJ1ZSl7CgogICAgV3JpdGUtSG9zdCAiU3lzcHJlcCBlcnJvciBsb2cgY29udGVudDoiCiAgICBHZXQtQ29udGVudCAiYzpcV2luZG93c1xTeXN0ZW0zMlxTeXNwcmVwXFBhbnRoZXJcc2V0dXBlcnIubG9nIiAtRXJyb3JBY3Rpb24gQ29udGludWUKCiAgICBXcml0ZS1Ib3N0ICJTeXNwcmVwIGxvZyBjb250ZW50OiIKICAgIEdldC1Db250ZW50ICJjOlxXaW5kb3dzXFN5c3RlbTMyXFN5c3ByZXBcUGFudGhlclxzZXR1cGFjdC5sb2ciIC1FcnJvckFjdGlvbiBDb250aW51ZQogICAgCiAgICBXcml0ZS1FcnJvciAiU3lzcHJlcCBmYWlsZWQiIC1FcnJvckFjdGlvbiBTdG9wCiAgICByZXR1cm4gLTEKIH0KCiBXcml0ZS1Ib3N0ICJDSEVDS1BPSU5UXzAyOiBTeXNwcmVwIGNvbXBsZXRlZCIKCiAjIyB0aGVzZSBjaGFuZ2VzIGFyZSBhcHBsaWVkIGFmdGVyIHN5c3ByZXA6CiMjIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCgojIGRpc2FibGUgbmV0d29yayBkaXNjb3ZlcnkKTmV3LUl0ZW0gLVBhdGggIkhLTE06XFN5c3RlbVxDdXJyZW50Q29udHJvbFNldFxDb250cm9sXE5ldHdvcmtcTmV3TmV0d29ya1dpbmRvd09mZlwiIHwgT3V0LU51bGwKCgojIHJlbW92ZSBwYWdlIGZpbGUgLSBkaXNhYmxlZCBmb3Igbm93IGFzIHRoZXJlIGlzIGN1cnJlbnRseSBubyBhdXRvbWF0aWMgcmUtZW5hYmxlIG9uIGZpcnN0IGJvb3QKCiMkcHJpdmlsZWdlcyA9IEdldC1XbWlPYmplY3QgLUNsYXNzIFdpbjMyX2NvbXB1dGVyc3lzdGVtIC1FbmFibGVBbGxQcml2aWxlZ2VzCiMkcHJpdmlsZWdlcy5BdXRvbWF0aWNNYW5hZ2VkUGFnZWZpbGUgPSAkZmFsc2UKIyRwcml2aWxlZ2VzLlB1dCgpCgojJHBhZ2VmaWxlID0gR2V0LVdtaU9iamVjdCAtUXVlcnkgInNlbGVjdCAqIGZyb20gV2luMzJfUGFnZUZpbGVTZXR0aW5nIHdoZXJlIG5hbWU9J2M6XFxwYWdlZmlsZS5zeXMnIgojJHBhZ2VmaWxlLkRlbGV0ZSgpCgpXcml0ZS1Ib3N0ICJXaXBpbmcgZW1wdHkgc3BhY2Ugb24gZGlzay4uLiIKCiRGaWxlUGF0aD0iYzpcemVyby50bXAiCiRWb2x1bWUgPSBHZXQtV21pT2JqZWN0IHdpbjMyX2xvZ2ljYWxkaXNrIC1maWx0ZXIgIkRldmljZUlEPSdDOiciCiRBcnJheVNpemU9IDY0a2IKJFNwYWNlVG9MZWF2ZT0gJFZvbHVtZS5TaXplICogMC4wNQokRmlsZVNpemU9ICRWb2x1bWUuRnJlZVNwYWNlIC0gJFNwYWNldG9MZWF2ZQokWmVyb0FycmF5PSBuZXctb2JqZWN0IGJ5dGVbXSgkQXJyYXlTaXplKQoKJFN0cmVhbT0gW2lvLkZpbGVdOjpPcGVuV3JpdGUoJEZpbGVQYXRoKQp0cnkgewogICAkQ3VyRmlsZVNpemUgPSAwCiAgICB3aGlsZSgkQ3VyRmlsZVNpemUgLWx0ICRGaWxlU2l6ZSkgewogICAgICAgICRTdHJlYW0uV3JpdGUoJFplcm9BcnJheSwwLCAkWmVyb0FycmF5Lkxlbmd0aCkKICAgICAgICAkQ3VyRmlsZVNpemUgKz0kWmVyb0FycmF5Lkxlbmd0aAogICAgfQp9CmZpbmFsbHkgewogICAgaWYoJFN0cmVhbSkgewogICAgICAgICRTdHJlYW0uQ2xvc2UoKQogICAgfQp9CgpSZW1vdmUtSXRlbSAkRmlsZVBhdGgKV3JpdGUtSG9zdCAiQ0hFQ0tQT0lOVF8wMzogQ2xlYW51cCBjb21wbGV0ZWQiCgpXcml0ZS1Ib3N0ICJSYW5kb21pemUgQWRtaW5pc3RyYXRvciBwYXNzd29yZCBhbmQgZGlzYWJsZSBhY2NvdW50IgpBZGQtVHlwZSAtQXNzZW1ibHlOYW1lIFN5c3RlbS5XZWIKJGFkbWluUGFzc3dvcmRQbGFpbiA9IFtTeXN0ZW0uV2ViLlNlY3VyaXR5Lk1lbWJlcnNoaXBdOjpHZW5lcmF0ZVBhc3N3b3JkKDMwLDQpCiRhZG1pblBhc3N3b3JkID0gQ29udmVydFRvLVNlY3VyZVN0cmluZyAkYWRtaW5QYXNzd29yZFBsYWluIC1Bc1BsYWluVGV4dCAtRm9yY2UKJGFkbWluQWNjb3VudCA9IEdldC1Mb2NhbFVzZXIgQWRtaW5pc3RyYXRvcgokYWRtaW5BY2NvdW50IHwgU2V0LUxvY2FsVXNlciAtUGFzc3dvcmQgJGFkbWluUGFzc3dvcmQKJGFkbWluQWNjb3VudCB8IERpc2FibGUtTG9jYWxVc2VyCgpXcml0ZS1Ib3N0ICJJbWFnZSBidWlsZGluZyBjb21wbGV0ZWQuIE5leHQgc3RlcCB3aWxsIGRpc2FibGUgcGFja2VyIHVzZXIgYWNjb3VudCBhbmQgc2h1dGRvd24gdGhlIG1hY2hpbmUiCgokcGFja2VyQWNjb3VudCA9IEdldC1Mb2NhbFVzZXIgcGFja2VyIC1FcnJvckFjdGlvbiBDb250aW51ZQokcGFja2VyQWNjb3VudCB8IERpc2FibGUtTG9jYWxVc2VyIC1FcnJvckFjdGlvbiBDb250aW51ZQoKV3JpdGUtSG9zdCAiQ0hFQ0tQT0lOVF8wNDogU2h1dGRvd24iClN0b3AtQ29tcHV0ZXIgLUZvcmNlIC1FcnJvckFjdGlvbiBDb250aW51ZQoK
"@)) 
 
Write-Host "Writing shutdown script to C:\Windows\Temp\sysprep.ps1"
$script | Out-File -FilePath "C:\Windows\Temp\sysprep.ps1" -Encoding utf8

