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
    $variants = $_.Value
        $variants | ForEach-Object {          
   
            $template = $_
            if($Filter -and $template -notlike $Filter){
                return
            }

            $template
        }  
}

