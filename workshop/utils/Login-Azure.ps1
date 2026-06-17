#
<#
.SYNOPSIS
    Authenticates to Azure using either interactive (device-code) or service principal login.

.DESCRIPTION
    Handles Azure PowerShell and Azure CLI authentication. When an existing AzContext is
    already present the function skips re-authentication. All required values are read from
    environment variables that must be loaded before calling this script.

.PARAMETER Manual
    Switch to force an interactive device-code login instead of service principal authentication.

.NOTES
    Version:        1.0
    Author:         Franck Cornu - Microsoft 365 Solution Architect
    Creation Date:  25/05/2026
    Purpose/Change: Initial script development

.EXAMPLE
    # Dot-source and call from a parent deploy script
    . "$PSScriptRoot/scripts/Login-Azure.ps1"
    Login-Azure -Manual

#>

function Login-Azure {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $False)]
        [switch]$Manual
    )

    if ($Manual.IsPresent) {

        $Context = Get-AzContext

        if (-not($Context)) {

            # Manual / interactive connection
            Connect-AzAccount -TenantId $ENV_AZURE_DEPLOY_TENANT_ID -Subscription $ENV_AZURE_DEPLOY_SUBSCRIPTION_ID

            az login --use-device-code --tenant $ENV_AZURE_DEPLOY_TENANT_ID
        }

    } else {

        $Context = Get-AzContext

        if (-not($Context)) {

            Disable-AzContextAutosave

            if ($ENV_AZURE_DEPLOY_APP_CLIENT_SECRET) {

                [pscredential]$Credentials = New-Object System.Management.Automation.PSCredential(
                    $ENV_AZURE_DEPLOY_APP_CLIENT_ID,
                    (ConvertTo-SecureString $ENV_AZURE_DEPLOY_APP_CLIENT_SECRET -AsPlainText -Force)
                )

                Connect-AzAccount   -TenantId $ENV_AZURE_DEPLOY_TENANT_ID `
                                    -Subscription $ENV_AZURE_DEPLOY_SUBSCRIPTION_ID `
                                    -Credential $Credentials `
                                    -ServicePrincipal `
                                    -Environment AzureCloud

                az login --service-principal --username $ENV_AZURE_DEPLOY_APP_CLIENT_ID --password $ENV_AZURE_DEPLOY_APP_CLIENT_SECRET --tenant $ENV_AZURE_DEPLOY_TENANT_ID

            } else {
                throw "No valid credentials found for application connection."
            }

        } else {

            $Context
            Write-Verbose "Already connected to Azure with subscription '$($ENV_AZURE_DEPLOY_SUBSCRIPTION_ID)' and tenant '$($ENV_AZURE_DEPLOY_TENANT_ID)'..."
        }
    }
}
