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
        $variants | % {          

            try{
                Join-Path ./templates $osType | Push-Location                   
                try{            

                    $template = $_        
                    Write-Output "Build image $osType/$template"
                    ./build.ps1 -Template_name $template     
                    
                }
                finally{
                    Pop-Location
                }
                .\tools\catlettify.ps1 -BasePath .\builds -TemplateName $template
            }
            catch{
                Write-Output "Building image $osType/$template failed"
                Write-Error $_
            }

        }


   
}

