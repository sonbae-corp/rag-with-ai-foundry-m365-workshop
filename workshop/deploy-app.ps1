# 
<#
.SYNOPSIS
    Deploys the Azure App Service code

.DESCRIPTION
    Deploys the Azure App Service code

.NOTES
    Version:        1.0
    Author:         Workshop Maintainers
    Creation Date:  04/12/2025
    Purpose/Change: Initial script development

.EXAMPLE

    Deploy all in from local machine:
    > deploy-app.ps1 -Env LOCAL

#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]$WebAppName,

    [Parameter(Mandatory = $True)]
    [string]$DistFolderPath
)

$ErrorActionPreference = "Stop"

Write-Verbose "`tInitializing variables..."
. $PSScriptRoot/variables.local.ps1

try {

    Push-Location -Path (Join-Path -Path $PSScriptRoot -ChildPath $DistFolderPath)

    Write-Verbose "Set location to '$(Get-Location)'"

    #region ----------------------------------------------------------[Azure Function deployment]---------------------------------------------------------
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

    #region Deploy

    Get-ChildItem . -Exclude "__pycache__",".venv","appPackage","devTools",".vscode" | Compress-Archive -DestinationPath app.zip -Force

    if (-not (Test-Path -Path app.zip)) {
        throw "The deployment package 'app.zip' was not created successfully."
    }

    Write-Verbose "Deploying App Service code to '$WebAppName'..."

    if ($ENV_WEBAPP_STACK -eq "python") {
        Write-Verbose "Configuring startup file for Python app..."
        az webapp config set --resource-group $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME --name $WebAppName --startup-file "startup.sh"
    }
    
    az webapp deploy --resource-group $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME --name $WebAppName --type zip --src-path app.zip --restart --clean true --debug --track-status false

    Pop-Location

    #endregion

} catch {
    Pop-Location
}

