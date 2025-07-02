

# script from https://github.com/rgl/windows-vagrant/blob/master/remove-apps.ps1
# licensed by Rui Lopes (https://github.com/rgl) under MIT license

if windows_workstation?

powershell_script 'uninstall windows apps' do
    code <<-EOH

mkdir -Force 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' | Set-ItemProperty `
    -Name DisableWindowsConsumerFeatures `
    -Value 1


# remove appx packages
# we only remove the appx packages that are outdated and for end-user experience only.
# NB some packages fail to be removed and thats OK.
# see https://docs.microsoft.com/en-us/windows/application-management/apps-in-windows-10
@(
    'Clipchamp.Clipchamp'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.GamingApp'
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
    'Microsoft.Todos'
    'Microsoft.Wallet'
    'Microsoft.Windows.Photos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCalculator'
    'Microsoft.WindowsCamera'
    'microsoft.windowscommunicationsapps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
#  keep 'MicrosoftWindows.Client.WebExperience'
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
    'MicrosoftTeams'
) | ForEach-Object {
    $appx = Get-AppxPackage -AllUsers $_
    if ($appx) {
        Write-Output "Removing the $($appx.Name) appx package..."
        try {
            $appx | Remove-AppxPackage -AllUsers -ErrorAction Continue
            $appx | % { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageFullName -AllUsers -ErrorAction Continue }
        } catch {
            Write-Output "WARN Failed to remove appx: $_"
        }
    }
}

    EOH
  end

end