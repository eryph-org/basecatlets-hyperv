

# script from https://github.com/rgl/windows-vagrant/blob/master/remove-apps.ps1
# licensed by Rui Lopes (https://github.com/rgl) under MIT license

if windows_workstation?

powershell_script 'uninstall windows apps' do
    code <<-EOH

mkdir -Force 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' | Set-ItemProperty `
    -Name DisableWindowsConsumerFeatures `
    -Value 1

# when running on pwsh and windows 10, explicitly import the appx module.
# see https://github.com/PowerShell/PowerShell/issues/13138
$currentVersionKey = Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion'
$build = [int]$currentVersionKey.CurrentBuildNumber
if (($PSVersionTable.PSEdition -ne 'Desktop') -and ($build -lt 22000)) {
    Import-Module Appx -UseWindowsPowerShell
}

# remove all the provisioned appx packages.
# NB some packages fail to be removed and thats OK.
Get-AppXProvisionedPackage -Online | ForEach-Object {
    Write-Host "Removing the $($_.PackageName) provisioned appx package..."
    try {
        $_ | Remove-AppxProvisionedPackage -Online | Out-Null
    } catch {
        Write-Output "WARN Failed to remove appx: $_"
    }
}

# remove appx packages.
# NB some packages fail to be removed and thats OK.
# see https://docs.microsoft.com/en-us/windows/application-management/apps-in-windows-10
@(
    'Microsoft.BingWeather'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.MixedReality.Portal'
    'Microsoft.MSPaint'
    'Microsoft.Office.OneNote'
    'Microsoft.People'
    'Microsoft.ScreenSketch'
    'Microsoft.Services.Store.Engagement'
    'Microsoft.SkypeApp'
    'Microsoft.StorePurchaseApp'
    'Microsoft.Wallet'
    'Microsoft.Windows.Photos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCalculator'
    'Microsoft.WindowsCamera'
    'microsoft.windowscommunicationsapps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
#  keep windows store 'Microsoft.WindowsStore' 
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
) | ForEach-Object {
    $appx = Get-AppxPackage -AllUsers $_
    if ($appx) {
        Write-Host "Removing the $($appx.Name) appx package..."
        try {
            $appx | Remove-AppxPackage -AllUsers
        } catch {
            Write-Output "WARN Failed to remove appx: $_"
        }
    }
}

    EOH
  end

end