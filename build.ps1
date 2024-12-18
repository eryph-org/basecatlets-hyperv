[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]
    $Filter
)

Push-Location $PSScriptRoot


function Get-ObjectMember {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key"}
    }
}

$buildList = Get-Content -Raw -Path "build.json" | ConvertFrom-Json | Get-ObjectMember


$buildList | ForEach-Object {
    $osType = $_.Key
    $variants = $_.Value
        $variants | ForEach-Object {          
            $template = $_ 

            if($Filter -and $template -notlike $Filter){
                return
            }

            try{
                Join-Path ./templates $osType | Push-Location                   
                try{            

                           
                    Write-Output "Build image $osType/$template"
                    ./build.ps1 -Template_name $template     
                    
                }
                finally{
                    Pop-Location
                }
                .\tools\catletlify.ps1 -BasePath .\builds -TemplateName $template
            }
            catch{
                Write-Output "Building image $osType/$template failed"
                Write-Error $_
            }

        }


   
}

