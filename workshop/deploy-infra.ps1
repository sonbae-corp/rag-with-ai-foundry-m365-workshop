# 
<#
.SYNOPSIS
    Deploys the Azure infrastructure for the AI workshop

.DESCRIPTION
    Deploys the Azure infrastructure for application

.NOTES
    Version:        1.0
    Author:         Workshop Maintainers
    Creation Date:  17/09/2025
    Purpose/Change: Initial script development

.EXAMPLE

    Deploy all in from local machine:
    > deploy-infra.ps1 -Module <module name>

#>

[CmdletBinding()]
Param (

    [Parameter(Mandatory = $False)]
    [switch]$Manual,

    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet(
        'Module1',
        'Module2.1',
        'Module2.2',
        'Module3.1',
        'Module6'
    )]
    [string]$Module,

    [switch]$ConfigureSearch,

    [switch]$ConfigureAgent,

    [switch]$ConfigureWebApp
)

$ErrorActionPreference = "Stop"

. $PSScriptRoot/utils/Replace-Tokens.ps1
. $PSScriptRoot/utils/Login-Azure.ps1

Write-Verbose "`tInitializing variables..."

# Load correct variables according to the targeted environnement
. $PSScriptRoot/variables.local.ps1
Write-Verbose "Variables from local have been loaded..."

#region ----------------------------------------------------------[Azure resources deployment]---------------------------------------------------------
Import-Module Az.Accounts
Import-Module Az.Resources

Disable-AzContextAutosave

Login-Azure -Manual:$Manual

try {

    $templateTemplateFilePath = Join-Path -Path $PSScriptRoot -ChildPath "./templates/main.bicep"
    $sqlCreateTableFilePath = Join-Path -Path $PSScriptRoot -ChildPath "./templates/sql_table.sql"
    $currentIpAddress = Invoke-RestMethod -Uri 'http://api.ipify.org'

    # Generate config.yaml from template, substituting the tenant ID
    Replace-Tokens `
        -InputFile  (Join-Path -Path $PSScriptRoot -ChildPath "./templates/config.yaml.template") `
        -OutputFile (Join-Path -Path $PSScriptRoot -ChildPath "./templates/config.yaml") `
        -Tokens @{ ENV_AZURE_DEPLOY_TENANT_ID = $ENV_AZURE_DEPLOY_TENANT_ID } `
        -StartTokenPattern "{{" `
        -EndTokenPattern "}}"

    $rbacPrincipalsList = @(
        @{
            principalId = $ENV_AZURE_DEPLOY_APP_CLIENT_ID
            principalType = "ServicePrincipal"
        }
    )

    # Add current user
    if ($Manual.IsPresent) {
        $rbacPrincipalsList += @{
            principalId = (az ad signed-in-user show --query id -o tsv)
            principalType = "User"
        }
    }

    $templateParameterObject = @{
        rgName = $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME
        environmentName = $ENV_AZURE_DEPLOYMENT_STACK_ENV_NAME
        appVersion = $AppVersion
        rbacPrincipalsList =$rbacPrincipalsList
        rbacSqlEntraIdAdministrator = @{
            login = $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_NAME
            principalId = $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_ID
        }
        deployerIpAddress = $currentIpAddress
        botOauthConnectionClientId = $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_CLIENT_ID
        botOauthConnectionClientSecret = $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_CLIENT_SECRET
        stack = $ENV_WEBAPP_STACK
    }

    # Determine resources and capabilities based on workshop modules
    $allResources = @()
    $allCapabilities = @()

    $moduleConfig = $ENV_MODULES_CONFIG[$Module]
    $allResources += $moduleConfig.Resources
    $allCapabilities += $moduleConfig.Capabilities

    # Remove duplicates and add to template parameters
    $templateParameterObject['resourcesToProvision'] = $allResources
    $templateParameterObject['featuresToProvision'] = $allCapabilities
    
   
    # Need to install Bicep manually with PowerShell https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#install-manually
    $res = New-AzSubscriptionDeploymentStack `
        -Name $ENV_AZURE_DEPLOYMENT_STACK_ENV_NAME `
        -Location $ENV_AZURE_LOCATION `
        -TemplateFile $templateTemplateFilePath `
        -TemplateParameterObject  $templateParameterObject `
        -ActionOnUnmanage "deleteAll" `
        -DenySettingsMode "none" `
        -Force
        
    #region SQL Configuration
    $ServerFullyQualifiedDomainName = $res.outputs.serverFullyQualifiedDomainName.Value
    $SqlDatabaseName = $res.outputs.sqlDatabaseName.Value
    $SqlDatabaseResourceId = $res.outputs.sqlDatabaseResourceId.Value
    $ManagedIdentityName = $res.outputs.userManagedIdentityName.Value
    $SqlUserAssignedIdentityPrincipalId = $res.outputs.sqlServerUserIdentityPrincipalId.Value

    # Add the managed identity created as Directory Readers so we can create users for database
    $user = Get-AzADGroupMember -GroupObjectId $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_ID | Where-Object { $_.Id -eq $SqlUserAssignedIdentityPrincipalId } | Select-Object -First 1
    if (-not($user)) {
        Add-AzADGroupMember -TargetGroupObjectId $ENV_AZURE_DEPLOYMENT_STACK_SQL_ADMINS_ENTRA_GROUP_ID -MemberObjectId $SqlUserAssignedIdentityPrincipalId

        # Make sure the permissions is applied before creating the user and avoid timing issue
        Start-Sleep -Seconds 30
    } else {
        Write-Warning "User managed identity '$SqlUserAssignedIdentityPrincipalId' is already a member of SQL admins group. Skipping... "
    }

    $token = (Get-AzAccessToken -ResourceUrl https://database.windows.net/).Token
    Invoke-Sqlcmd -ServerInstance $ServerFullyQualifiedDomainName -Database $SqlDatabaseName -InputFile $sqlCreateTableFilePath -AccessToken $token
    Invoke-Sqlcmd -ServerInstance $ServerFullyQualifiedDomainName -Database $SqlDatabaseName -Query "IF USER_ID('$ManagedIdentityName') IS NULL CREATE USER [$ManagedIdentityName] FROM EXTERNAL PROVIDER;EXEC sp_addrolemember 'db_datareader', [$ManagedIdentityName];" -AccessToken $token
	
    #endregion

    #region Azure AI Search configuration
    if ($ConfigureSearch.IsPresent) {

        $headers = @{
            'api-key' = $res.outputs.azureAiSearchApiKey.Value
            'Content-Type' = 'application/json' 
            'Accept' = 'application/json' 
        }

        $dataSourceName ="ai-knowledge-sql"
        $indexName = "ai-knowledge-index"
        $skillSetName = "ai-knowledge-skillset"
        $indexerName = "ai-knowledge-indexer"
        $azureOpenAiEndpoint = "https://$($res.outputs.aiFoundryResourceName.Value).openai.azure.com"

        # Create Data source
        try {

            $url = "$($res.outputs.azureAiSearchEndpoint.Value)/datasources('$dataSourceName')?api-version=2025-05-01-preview"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck -StatusCodeVariable "statusCode" | Out-Null

            if ($statusCode -eq 404) {
            
                $dataSourcePayload = @{
                    name = $dataSourceName
                    description = $null
                    type = "azuresql"
                    subtype = $null
                    credentials = @{
                        connectionString = "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Database=$SqlDatabaseName;ResourceId=$SqlDatabaseResourceId"
                    }
                    container = @{
                        name = "Articles"
                        query = $null
                    }
                    dataChangeDetectionPolicy = $null
                    dataDeletionDetectionPolicy = $null
                    encryptionKey = $null
                    identity = @{
                        "@odata.type" = "#Microsoft.Azure.Search.DataUserAssignedIdentity"
                        userAssignedIdentity = $res.outputs.userManagedIdentityResourceId.Value
                    }
                }

                $url = "$($res.outputs.azureAiSearchEndpoint.Value)/datasources?api-version=2025-05-01-preview"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($dataSourcePayload | ConvertTo-Json -Depth 4)

            } else {
                Write-Warning "Datasource '$dataSourceName' already exists. Skipping..."
            }

        } catch {
            Write-Error $_.Exception.Message
        }

        # Create index
        try {

            $url = "$($res.outputs.azureAiSearchEndpoint.Value)/indexes('$indexName')?api-version=2025-09-01"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck -StatusCodeVariable "statusCode" | Out-Null

            if ($statusCode -eq 404) {
                
                $indexPayload = @{
                    "name" = $indexName
                    "fields" = @(
                        @{
                            name         = "chunk_id"
                            type         = "Edm.String"
                            searchable   = $true
                            filterable   = $false
                            retrievable  = $true
                            stored       = $true
                            sortable     = $true
                            facetable    = $false
                            key          = $true
                            analyzer     = "keyword"
                            synonymMaps  = @()
                        },
                        @{
                            name         = "parent_id"
                            type         = "Edm.String"
                            searchable   = $false
                            filterable   = $true
                            retrievable  = $true
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "chunk"
                            type         = "Edm.String"
                            searchable   = $true
                            filterable   = $false
                            retrievable  = $true
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name                   = "text_vector"
                            type                   = "Collection(Edm.Single)"
                            searchable             = $true
                            filterable             = $false
                            retrievable            = $true
                            stored                 = $true
                            sortable               = $false
                            facetable              = $false
                            key                    = $false
                            dimensions             = 1024
                            vectorSearchProfile    = "ai-knowledge-aiFoundryCatalog-text-profile"
                            synonymMaps            = @()
                        },
                        @{
                            name         = "id"
                            type         = "Edm.String"
                            searchable   = $false
                            filterable   = $false
                            retrievable  = $true
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "author"
                            type         = "Edm.String"
                            searchable   = $true
                            filterable   = $false
                            retrievable  = $false
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "claps"
                            type         = "Edm.String"
                            searchable   = $false
                            filterable   = $false
                            retrievable  = $false
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "reading_time"
                            type         = "Edm.Int32"
                            searchable   = $false
                            filterable   = $false
                            retrievable  = $false
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "link"
                            type         = "Edm.String"
                            searchable   = $false
                            filterable   = $false
                            retrievable  = $true
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "title"
                            type         = "Edm.String"
                            searchable   = $true
                            filterable   = $false
                            retrievable  = $true
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        },
                        @{
                            name         = "text"
                            type         = "Edm.String"
                            searchable   = $true
                            filterable   = $false
                            retrievable  = $false
                            stored       = $true
                            sortable     = $false
                            facetable    = $false
                            key          = $false
                            synonymMaps  = @()
                        }
                    )
                    
                    "similarity" = @{
                        "@odata.type" = "#Microsoft.Azure.Search.BM25Similarity"
                    }
                    "vectorSearch" = @{
                        "algorithms" = @(
                            @{
                                "name" = "ai-knowledge-algorithm"
                                "kind" = "hnsw"
                                "hnswParameters" = @{
                                    "metric" = "cosine"
                                    "m" = 4
                                    "efConstruction" = 400
                                    "efSearch" = 500
                                }
                            }
                        )
                        "profiles" = @(
                            @{
                                "name" = "ai-knowledge-aiFoundryCatalog-text-profile"
                                "algorithm" = "ai-knowledge-algorithm"
                                "vectorizer" = "ai-knowledge-aiFoundryCatalog-text-vectorizer"
                            }
                        )
                        "vectorizers" = @(
                            @{
                                "name" = "ai-knowledge-aiFoundryCatalog-text-vectorizer"
                                "kind" = "azureOpenAI"
                                "azureOpenAIParameters" = @{
                                    "resourceUri" = $azureOpenAiEndpoint
                                    "deploymentId" = "text-embedding-3-large"
                                    "modelName" = "text-embedding-3-large"
                                    "authIdentity" = @{
                                        "@odata.type" = "#Microsoft.Azure.Search.DataUserAssignedIdentity"
                                        userAssignedIdentity = $res.outputs.userManagedIdentityResourceId.Value
                                    } # Important to use the managed identity here to get access to OpenAI for query vectorization. Will use system assigned by default otherwise resutling to an access denied.
                                }
                            }
                        )
                        "compressions" = @(

                        )
                    }
                }

                $url = "$($res.outputs.azureAiSearchEndpoint.Value)/indexes?api-version=2024-07-01"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($indexPayload | ConvertTo-Json -Depth 12)

            } else {
                Write-Warning "Index '$indexName' already exists. Skipping..."
            }

        } catch {
            Write-Error $_.Exception.Message
        }

        # Create Skillset
        try {

            $url = "$($res.outputs.azureAiSearchEndpoint.Value)/skillsets('$skillSetName')?api-version=2024-07-01"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck -StatusCodeVariable "statusCode" | Out-Null

            if ($statusCode -eq 404) {

                $skillsetPayload = @{
                    name = $skillSetName
                    description = "Skillset to chunk documents and generate embeddings"
                    skills = @(
                        @{
                            "@odata.type" = "#Microsoft.Skills.Text.SplitSkill"
                            name = "#1"
                            description = "Split skill to chunk documents"
                            context = "/document"
                            defaultLanguageCode = "en"
                            textSplitMode = "pages"
                            maximumPageLength = 2000
                            pageOverlapLength = 500
                            maximumPagesToTake = 0
                            unit = "characters"
                            inputs = @(
                                @{
                                    name = "text"
                                    source = "/document/text"
                                    inputs = @()
                                }
                            )
                            outputs = @(
                                @{
                                    name = "textItems"
                                    targetName = "pages"
                                }
                            )
                        },
                        @{
                            "@odata.type" = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
                            name = "#2"
                            context = "/document/pages/*"
                            resourceUri = $azureOpenAiEndpoint
                            deploymentId = "text-embedding-3-large"
                            dimensions = 1024
                            modelName = "text-embedding-3-large"
                            authIdentity = @{
                                "@odata.type" = "#Microsoft.Azure.Search.DataUserAssignedIdentity"
                                userAssignedIdentity = $res.outputs.userManagedIdentityResourceId.Value
                            }
                            inputs = @(
                                @{
                                    name = "text"
                                    source = "/document/pages/*"
                                    inputs = @()
                                }
                            )
                            outputs = @(
                                @{
                                    name = "embedding"
                                    targetName = "text_vector"
                                }
                            )
                        }
                    )
                    indexProjections = @{
                        selectors = @(
                            @{
                                targetIndexName = $indexName
                                parentKeyFieldName = "parent_id"
                                sourceContext = "/document/pages/*"
                                mappings =  @(
                                    @{ name = "text_vector"; source = "/document/pages/*/text_vector"; inputs = @() },
                                    @{ name = "chunk"; source = "/document/pages/*"; inputs = @() },
                                    @{ name = "id"; source = "/document/id"; inputs = @() },
                                    @{ name = "author"; source = "/document/author"; inputs = @() },
                                    @{ name = "link"; source = "/document/link"; inputs = @() },
                                    @{ name = "title"; source = "/document/title"; inputs = @() }
                                )
                            }
                        )
                        parameters = @{
                            projectionMode = "skipIndexingParentDocuments"
                        }
                    }
                
                }

                $url = "$($res.outputs.azureAiSearchEndpoint.Value)/skillsets?api-version=2025-05-01-preview"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($skillsetPayload | ConvertTo-Json -Depth 12)
            } else {
                Write-Warning "Skillset '$skillSetName' already exists. Skipping..."
            }

        } catch {
            Write-Error $_.Exception.Message
        }

        # Create Indexer
        try {

            $url = "$($res.outputs.azureAiSearchEndpoint.Value)/indexers('$indexerName')?api-version=2024-07-01"
            Invoke-RestMethod -Uri $url -Headers $headers -Method Get -SkipHttpErrorCheck -StatusCodeVariable "statusCode" | Out-Null

            if ($statusCode -eq 404) {

                $indexerPayload = @{
                    name = $indexerName
                    description = $null
                    dataSourceName = $dataSourceName
                    skillsetName = $skillSetName
                    targetIndexName = $indexName
                    disabled = $null
                    schedule = $null
                    parameters = @{
                        batchSize = $null
                        maxFailedItems = $null
                        maxFailedItemsPerBatch = $null
                        configuration = @{
                            executionEnvironment = (($ENV_AZURE_ENV_STAGE -eq 'preprod') -or ($ENV_AZURE_ENV_STAGE -eq 'prod')) ? "Private" : "Standard" #https://learn.microsoft.com/en-us/azure/search/search-indexer-howto-access-private?tabs=portal-create 
                        }
                    }     
                    fieldMappings = @(
                    @{
                        sourceFieldName = "id"
                        targetFieldName = "chunk_id"
                        mappingFunction = $null
                    }
                    )
                    outputFieldMappings = @()
                    encryptionKey = $null
                }
                
                $url = "$($res.outputs.azureAiSearchEndpoint.Value)/indexers?api-version=2024-07-01"
                Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body ($indexerPayload | ConvertTo-Json -Depth 12)

            } else {
                Write-Warning "Indexer '$indexerName' already exists. Skipping..."
            } 

        } catch {
            Write-Error $_.Exception.Message
        }
    }
    #endregion

    #region Microsoft Foundry agents configuration
    if ($configureAgent.IsPresent) {
        . "$PSScriptRoot/setup-agent.ps1" `
        -Manual:$Manual `
        -AzureFoundryProjectEndpointUrl $res.outputs.aiFoundryProjectEndpoint.Value `
        -AzureAiSearchFoundryConnectionResId $res.outputs.aiFoundryProjectConnectionAiSearchResourceId.Value
    }
    #endregion

    #region Azure App Service configuration
    if ($ConfigureWebApp.IsPresent) {

        Write-Verbose "`tUpdated Key Vault Value..."

        $KeyVaultValues = @{
            "AIFOUNDRYPROJECTENDPOINT" = $res.outputs.aiFoundryProjectEndpoint.Value;
            "USERMANAGEDIDENTITYCLIENTID" = $res.outputs.userManagedIdentityClientId.Value;
            "AIFOUNDRYAGENTID" = $ENV_FOUNDRY_AGENT_NAME;
            "TENANTID" = $ENV_AZURE_DEPLOY_TENANT_ID;
        }

        $KeyVaultValues.Keys | ForEach-Object {

            # Create or update secret
            Write-Information "Creating/Updating Secret '$_'..."
            if ($KeyVaultValues[$_]) {
                Set-AzKeyVaultSecret -VaultName $res.outputs.azureKeyVaultName.Value -Name $_ -SecretValue (ConvertTo-SecureString $KeyVaultValues[$_] -AsPlainText -Force) -ContentType "txt"
            }        
        }

        Write-Verbose "`tUpdating App Service settings..."

        $AppSettings = @{
            "ENV_AZURE_DEPLOY_AI_FOUNDRY_PROJECT_ENDPOINT" = "@Microsoft.KeyVault(SecretUri=https://$($res.outputs.azureKeyVaultName.Value).vault.azure.net/secrets/AIFOUNDRYPROJECTENDPOINT)";
            "ENV_FOUNDRY_AGENT_NAME" = "@Microsoft.KeyVault(SecretUri=https://$($res.outputs.azureKeyVaultName.Value).vault.azure.net/secrets/AIFOUNDRYAGENTID)";
            "clientId" = "@Microsoft.KeyVault(SecretUri=https://$($res.outputs.azureKeyVaultName.Value).vault.azure.net/secrets/USERMANAGEDIDENTITYCLIENTID)"; # Used to connecto to bot service from app service via managed identity
            "tenantId" = "@Microsoft.KeyVault(SecretUri=https://$($res.outputs.azureKeyVaultName.Value).vault.azure.net/secrets/TENANTID)"; 
            "graph_connectionName" = $ENV_AZURE_SEARCH_APP_OAUTH_CONNECTION_NAME; # OAuth2 Connection on Bot Service;
            "ENV_AZURE_DEPLOY_USER_MANAGED_IDENTITY_CLIENT_ID" = "@Microsoft.KeyVault(SecretUri=https://$($res.outputs.azureKeyVaultName.Value).vault.azure.net/secrets/USERMANAGEDIDENTITYCLIENTID)";
        }
        
        Set-AzWebApp `
            -Name $res.outputs.webAppResourceName.Value `
            -ResourceGroupName $ENV_AZURE_DEPLOYMENT_STACK_RG_NAME `
            -AppSettings $AppSettings

        # Refresh key vault references

        Write-Verbose "`tRefreshing key vault references..."

        $token = az account get-access-token --resource "https://management.azure.com" | ConvertFrom-Json | Select-Object -ExpandProperty accessToken # Doesn't work with PowerShell

        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json' 
            'Accept' = 'application/json' 
        }
        
        $url = "https://management.azure.com$($res.outputs.webAppResourceId.Value)/config/configreferences/appsettings/refresh?api-version=2022-03-01"
        Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body (@{} | ConvertTo-Json)
    }
    #endregion


    Write-Output "Deployment done!"

} catch {
    Write-Error "Deployment error ... $($_.Exception.Message)"
}