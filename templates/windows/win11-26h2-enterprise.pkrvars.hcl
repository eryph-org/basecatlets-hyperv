
template = "win11-26h2-enterprise"
iso_checksum = "sha256:BC3F24086EBADC94489066B5AD78089E2CF5C3491E90E790BB81A2B199C10E38"
iso_url = "https://software-static.download.prss.microsoft.com/dbazure/26300.9457.260913-1737.26h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
windows_image_name = "Windows 11 Enterprise Evaluation"
overwrite_tpm_enabled= true
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
<component name="microsoft-windows-securestartup-filterdriver-" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <PreventDeviceEncryption>true</PreventDeviceEncryption>
</component>
EOT

// disable automatic device encryption and TCG security activation - device encryption is auto enabled on Windows 11 24H2
oobeSystemComponents = <<-EOT
<component name="Microsoft-Windows-SecureStartup-FilterDriver" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
    <PreventDeviceEncryption>true</PreventDeviceEncryption>
</component>
<component name="Microsoft-Windows-EnhancedStorage-Adm" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
    <TCGSecurityActivationDisabled>1</TCGSecurityActivationDisabled>
</component>
EOT
