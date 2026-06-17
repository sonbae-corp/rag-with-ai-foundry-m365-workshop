# 
<#
.SYNOPSIS
    Deploys the Docusaurus documentation to App Service

.DESCRIPTION
    Deploy all assets of Docusaurus static site

.NOTES
    Version:        1.0
    Author:         Workshop Maintainers
    Creation Date:  17/10/2024
    Purpose/Change: Initial script development

.EXAMPLE

    Deploy all in from local machine:
    > deploy.ps1 -Env LOCAL

#>

[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]$WebAppName,

    [Parameter(Mandatory = $False)]
    [switch]$Manual
)

$ErrorActionPreference = "Stop"

. $PSScriptRoot/variables.local.ps1
Write-Verbose "Variables from local have been loaded..."

#region ----------------------------------------------------------[Azure resources deployment]---------------------------------------------------------
if ($Manual.IsPresent) {

    # Manual connection
    az login --use-device-code --tenant $ENV_AZURE_DEPLOY_TENANT_ID

} else {
        
    if ($ENV_AZURE_DEPLOY_APP_CLIENT_SECRET) {
        az login --service-principal --username $ENV_AZURE_DEPLOY_APP_CLIENT_ID --password $ENV_AZURE_DEPLOY_APP_CLIENT_SECRET --tenant $ENV_AZURE_DEPLOY_TENANT_ID
    
    } else {
        throw "No valid credentials found for application connection."
    }
}

try {

    # > Publish to Azure App Service as ZIP deploy
    $distFolderPath = Join-Path -Path $PSScriptRoot -ChildPath "../../documentation/dist"

    Write-Verbose "Building application ZIP package..."
    Compress-Archive -Path "$distFolderPath/*" -DestinationPath "$distFolderPath/app.zip" -Force

    Write-Verbose "Deploying application package..."
    az webapp deploy --resource-group $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME --name $WebAppName --type zip --src-path "$distFolderPath/app.zip" --restart --clean true --debug --track-status false
    
    Write-Host "Deployment done successfully."

} catch {
    Write-Error "Deployment error ... $($_.Exception.Message)"
}