# 
<#
.SYNOPSIS
    Create or update AI Foundry agents

.DESCRIPTION
    Create or update AI Foundry agents

.NOTES
    Version:        1.0
    Author:         Workshop Maintainers
    Creation Date:  04/12/2025
    Purpose/Change: Initial script development

.EXAMPLE

    Deploy all in from local machine:
    > setup-agent.ps1 -Env LOCAL -AzureFoundryProjectEndpointUrl "https://<your-project>.foundry.azureaiapps.com" -BotWebAppDomain "https://app-<your-env>.azurewebsites.net"

#>

[CmdletBinding()]
Param (


    [Parameter(Mandatory = $False)]
    [switch]$Manual,

    [Parameter(Mandatory = $True)]
    [string]$AzureFoundryProjectEndpointUrl,

    [Parameter(Mandatory = $True)]
    [string]$AzureAiSearchFoundryConnectionResId
)

$ErrorActionPreference = "Stop"

. $PSScriptRoot/utils/Replace-Tokens.ps1

Write-Verbose "`tInitializing variables..."

# Load correct variables according to the targeted environnement
. $PSScriptRoot/variables.local.ps1
Write-Verbose "Variables from local have been loaded..."


#region ----------------------------------------------------------[Azure resources deployment]---------------------------------------------------------
Import-Module Az.Accounts

Disable-AzContextAutosave

$IsLogged = !!(az account show)

if (-not($IsLogged)) {

    if ($Manual.IsPresent) {

        az login --use-device-code --tenant $ENV_AZURE_DEPLOY_TENANT_ID

    } else {
            
        if ($ENV_AZURE_DEPLOY_APP_CLIENT_SECRET) {

            az login --service-principal --username $ENV_AZURE_DEPLOY_APP_CLIENT_ID --password $ENV_AZURE_DEPLOY_APP_CLIENT_SECRET --tenant $ENV_AZURE_DEPLOY_TENANT_ID
        
        } else {
            throw "No valid credentials found for application connection."
        }
    }
}

#region Microsoft Foundry configuration

    $token = az account get-access-token --resource "https://ai.azure.com" | ConvertFrom-Json | Select-Object -ExpandProperty accessToken # Doesn't work with PowerShell

    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json' 
        'Accept' = 'application/json' 
    }

    try {

        #region Microsoft Foundry agents configuration
        
        $Tokens = @{
            AI_SEARCH_FOUNDRY_CONNECTION_RESOURCE_ID = $AzureAiSearchFoundryConnectionResId
        }

        # Create or update agents
        $agentsFolder = Join-Path -Path $PSScriptRoot -ChildPath "agents"

        # Remove existing file
        Get-ChildItem -Path $agentsFolder -Filter *.json -File | Remove-Item -Force
        
        # Replace tokens in agents template files
        Get-ChildItem -Path $agentsFolder -Filter *.template -File | Sort-Object Name | ForEach-Object {

                Write-Verbose "Processing agent template file: $($_.Name)"
                            
                $outputFileName = $_.Name -replace '\.template$', ''
                $outputFilePath = Join-Path -Path $_.DirectoryName -ChildPath $outputFileName
                
                Replace-Tokens `
                    -InputFile $($_.FullName) `
                    -OutputFile $outputFilePath `
                    -Tokens $Tokens `
                    -StartTokenPattern "{{" `
                    -EndTokenPattern "}}"
        }

        Get-ChildItem -Path $agentsFolder -Filter *.json -File | Sort-Object Name | ForEach-Object {

            Write-Verbose "Processing agent file: $($_.Name)"

            $agentPayload = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
            $agentName = $agentPayload.name
            $url = "$AzureFoundryProjectEndpointUrl/agents/$($agentName)?api-version=2025-11-15-preview"

            Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck -StatusCodeVariable "statusCode" | Out-Null
            if ($statusCode -eq 404) {
                Write-Verbose "Creating agent '$agentName'..."
                $url = "$AzureFoundryProjectEndpointUrl/agents?api-version=2025-11-15-preview"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($agentPayload | ConvertTo-Json -Depth 24) | Out-Null
            } else {

                Write-Verbose "Agent '$agentName' already exists. Updating..."
                $url = "$AzureFoundryProjectEndpointUrl/agents/$($agentName)?api-version=2025-11-15-preview"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($agentPayload | ConvertTo-Json -Depth 24) | Out-Null                
            }
        }


        #endregion

    } catch {
        Write-Error $_.Exception.Message
    }

#endregion
