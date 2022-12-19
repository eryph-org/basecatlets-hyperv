
template = "win11-21h1-enterprise"
iso_checksum = "sha256:e8b1d2a1a85a09b4bf6154084a8be8e3c814894a15a7bcf3e8e63fcfa9a528cb"
iso_url = "https://software-download.microsoft.com/download/sg/22000.194.210913-1444.co_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
windows_image_name = "Windows 10 Enterprise Evaluation"
componentElement = <<-EOT
<RunSynchronous>
    <RunSynchronousCommand wcm:action="add">
        <Order>1</Order>
        <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1</Path>
    </RunSynchronousCommand>
    <RunSynchronousCommand wcm:action="add">
        <Order>2</Order>
        <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1</Path>
    </RunSynchronousCommand>
    <RunSynchronousCommand wcm:action="add">
        <Order>3</Order>
        <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1</Path>
    </RunSynchronousCommand>
</RunSynchronous>
EOT
