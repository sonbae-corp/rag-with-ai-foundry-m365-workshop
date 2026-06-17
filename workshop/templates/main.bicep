targetScope = 'subscription'

import {
  global
  tenant
  version
} from './config.bicep'

import {
  RBACPrincipalType
  UserLoginInfo
} from './types.bicep'

/*----------------------------------Params-------------------------------*/
@description('The environment unique name')
param environmentName string

@metadata({
  azd: {
    type: 'location'
  }
})
param location string = deployment().location

@description('The application version')
param appVersion string = '0.0.0'

@description('Resource group name where resources should be created')
param rgName string


@description('List of principals to configure for resource RBAC permissions')
param rbacPrincipalsList RBACPrincipalType[] = [
  {
    principalId: deployer().objectId
    principalType: 'ServicePrincipal'
  }
]

@description('User name or group name for SQL server administrator')
param rbacSqlEntraIdAdministrator UserLoginInfo

param createdAt string = utcNow()

@description('Current IP address of the currnet account used for deployment. Used to access SQL instance from local machine')
param deployerIpAddress string

@description('OAuth2 connection client ID for Bot Service to connect to Microsoft Graph')
param botOauthConnectionClientId string = ''

@description('OAuth2 connection client secret for Bot Service to connect to Microsoft Graph')
param botOauthConnectionClientSecret string = ''

@description('Resources types to provision')
param resourcesToProvision string[] = [
  'AIFoundry'
  'AISearch'
  'SQLServer'
  'AppService'
  'BotService'
  'KeyVault'
]

@description('Capabilities types to provision for resources')
param featuresToProvision string[] = [
  'AIFoundry/EmbeddingModel'
  'AIFoundry/CompletionModel'
  'AIFoundry/AISearchConnection'
]

@description('The runtime stack for the web app')
param stack string = 'node'

/*----------------------------------Variables---------------------------*/

var tags = {
  'azd-env-name': environmentName
}

var resourceToken = take(toLower(uniqueString(subscription().id, environmentName, location)), 5)

var resourceName = toLower(split(split(environmentName, '-')[0], '_')[0])

/*----------------------------------Resource group----------------------*/
module rg 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: '${global.abbreviations.deployments}rg-${resourceToken}'
  params: {
    name: rgName
    location: location
    tags: union(tags, {
      'genai-provisioned-by': deployer().objectId
      'genai-created-at': createdAt
      'genai-template-name': global.templateName
      'genai-template-version': version
      'solution-version': appVersion 
    })
  }
}


/*----------------------------------User Assigned Identity--------------*/
module userAssignedIdentityModule 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}userAssignedIdentity-${resourceToken}'
  params: {
    name: '${global.abbreviations.managedIdentityUserAssignedIdentities}${resourceName}-${resourceToken}'
  }
  dependsOn: [rg]
}

/*----------------------------------Logs--------------------------------*/
module logsModule './logs.bicep' = {
  name: '${global.abbreviations.deployments}logsModule-${resourceToken}'
  scope: resourceGroup(rgName)
  params: {
    storageAccountName: '${global.abbreviations.storageStorageAccounts}${resourceName}logs${resourceToken}'
    location: location
    userAssignedIdentityPrincipalId: userAssignedIdentityModule.outputs.principalId
  }
}

/*----------------------------------Storage Account---------------------*/
module saModule './sa.bicep' = {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}sa-${resourceToken}'
  params: {
    rbacPrincipalsList: rbacPrincipalsList
    location: location
    storageAccountName: '${global.abbreviations.storageStorageAccounts}${resourceName}${resourceToken}'
    storageAccountResourceId: logsModule.outputs.storageAccountResourceId
    userAssignedIdentityResourceName: userAssignedIdentityModule.outputs.name
  }
}

/*----------------------------------AI Foundry--------------------------*/
var rbacAiFoundryOpenAiContributorRoleAssignments = [
  for p in rbacPrincipalsList: {
    principalId: p.principalId
    principalType: p.principalType
    roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
  }
]

var rbacAiFoundryAzureAiUserRoleAssignments = [
  for p in rbacPrincipalsList: {
    principalId: p.principalId
    principalType: p.principalType
    roleDefinitionIdOrName: 'Azure AI User'
  }
]

var aiFoundryRoleAssignments = concat(
  rbacAiFoundryAzureAiUserRoleAssignments,
  rbacAiFoundryOpenAiContributorRoleAssignments,
  [
    {
      principalId: userAssignedIdentityModule.outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'Cognitive Services Contributor'
    }
    {
      principalId: userAssignedIdentityModule.outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'Cognitive Services OpenAI Contributor'
    }
    {
      principalId: userAssignedIdentityModule.outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'Azure AI User' // Needed for Azure Function to read agents
    }
  ]
)

module aiFoundry './ai-foundry.bicep' = if (contains(resourcesToProvision, 'AIFoundry')) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}aiFoundry-${resourceToken}'
  params: {
    location: location // Necessary to get the Agents Service
    kind: 'AIServices'
    name: '${global.abbreviations.cognitiveServicesAccounts}${resourceName}-${resourceToken}'
    sku: 'S0'
    disableLocalAuth: false
    featuresToProvision: featuresToProvision
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentityModule.outputs.resourceId
      ]
    }

    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled
    restrictOutboundNetworkAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }

    allowProjectManagement: true

    storageAccountResourceId: saModule.outputs.resourceId
    appInsightsResourceId: appInsights.?outputs.resourceId ?? ''
    appInsightsApiKey: logAnalyticsWorkspace.?outputs.primarySharedKey ?? ''
    searchServiceResourceId: aiSearchModule.?outputs.resourceId ?? ''

    project: 'project-${resourceName}-${resourceToken}'

    diagnosticSettings: [
      {
        name: '${global.abbreviations.cognitiveServicesAccounts}${resourceName}-${resourceToken}'
        storageAccountResourceId: logsModule.outputs.storageAccountResourceId
      }
    ]

    roleAssignments: aiFoundryRoleAssignments
  }
}

/*----------------------------------AI Search---------------------------*/
module aiSearchModule './ai-search.bicep' = if (contains(resourcesToProvision, 'AISearch')) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}aiSearch-${resourceToken}'
  params: {
    aiSearchServiceName: '${global.abbreviations.searchSearchServices}${resourceName}-${resourceToken}'
    location: location
    rbacPrincipalsList: rbacPrincipalsList
    userAssignedIdentityResourceName: userAssignedIdentityModule.outputs.name
    storageAccountResourceId: logsModule.outputs.storageAccountResourceId
  }
}

/*----------------------------------Log Analytics workspace-------------*/
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.11.2' = {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}logAnalyticsWorkspace-${resourceToken}'
  params: {
    name: '${global.abbreviations.operationalInsightsWorkspaces}${resourceName}-${resourceToken}'

    location: location
    linkedStorageAccounts: [
      {
        name: 'Query'
        storageAccountIds: [
          saModule.outputs.resourceId
        ]
      }
    ]

    publicNetworkAccessForIngestion: tenant.isProduction ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery:  tenant.isProduction ? 'Disabled' : 'Enabled'

    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentityModule.outputs.resourceId
      ]
    }

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Monitoring Contributor'
      }
    ]
  }
}

/*----------------------------------App Insights------------------------*/
module appInsights 'br/public:avm/res/insights/component:0.6.0' = {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}appInsights-${resourceToken}'
  params: {
    name: '${global.abbreviations.insightsComponents}${resourceName}-${resourceToken}'

    location: location

    kind: 'web'

    linkedStorageAccountResourceId: saModule.outputs.resourceId
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId

    publicNetworkAccessForIngestion: tenant.isProduction ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery:  tenant.isProduction ? 'Disabled' : 'Enabled'
    forceCustomerStorageForProfiler: false
    retentionInDays: 90

    disableIpMasking: false
    disableLocalAuth: false

    roleAssignments: [
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Monitoring Contributor'
      }
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Monitoring Metrics Publisher'
      }
      {
        principalId: userAssignedIdentityModule.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Application Insights Component Contributor'
      }
    ]
  }
}

/*----------------------------------SQL Server--------------------------*/
module sqlModule './sql-server.bicep' = if (contains(resourcesToProvision, 'SQLServer') ) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}sql-${resourceToken}'
  params: {
    location: location
    serverName: '${global.abbreviations.sqlServers}${resourceName}-${resourceToken}'
    databaseName: '${global.abbreviations.sqlServersDatabases}${resourceName}-${resourceToken}' 
    administratorLogin: rbacSqlEntraIdAdministrator.login
    administratorPrincipalId: rbacSqlEntraIdAdministrator.principalId
    userAssignedIdentityPrincipalId: userAssignedIdentityModule.outputs.principalId
    userAssignedIdentityResourceId: userAssignedIdentityModule.outputs.resourceId
    logsStorageAccountResourceId: logsModule.outputs.storageAccountResourceId
    deployerIpAddress: deployerIpAddress
  }
}

/*----------------------------------Key Vault---------------------------*/
module kvModule './kv.bicep' = if (contains(resourcesToProvision, 'KeyVault')) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}kv-${resourceToken}'
  params: {
    kvName: '${global.abbreviations.keyVaultVaults}${resourceName}-${resourceToken}'
    location: location
    rbacPrincipalsList: rbacPrincipalsList
    userAssignedIdentityResourceName: userAssignedIdentityModule.outputs.name
    storageAccountResourceId: logsModule.outputs.storageAccountResourceId
    tags: tags
  }
  dependsOn: [rg]
}

/*----------------------------------WebApp----------------------------*/
module webAppModule './webapp.bicep' = if (contains(resourcesToProvision, 'AppService') ) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}site-${resourceToken}'
  params: {
    location: location
    appServiceName: '${global.abbreviations.webServerFarms}${resourceName}-${resourceToken}'
    siteName: '${global.abbreviations.webSitesAppService}${resourceName}-${resourceToken}'
    userAssignedIdentityResourceId: userAssignedIdentityModule.outputs.resourceId
    deploymentStorageAccountResourceId: saModule.outputs.resourceId
    applicationInsightsResourceId: appInsights.outputs.resourceId
    logsModuleStorageAccountResourceId: logsModule.outputs.storageAccountResourceId
    stack: stack
  }
}

/*----------------------------------Bot Service----------------------------*/
module botService './bot.bicep' = if (contains(resourcesToProvision, 'BotService') ) {
  scope: resourceGroup(rgName)
  name: '${global.abbreviations.deployments}bot-${resourceToken}'
  params: {
    botDisplayName: '${global.abbreviations.botServices}${resourceName}-${resourceToken}'
    botAppDomain: webAppModule.outputs.webAppDomain
    userAssignedIdentityResourceId: userAssignedIdentityModule.outputs.resourceId
    botServiceSku: tenant.isProduction ? 'S1':'F0' 
    botServiceName: '${global.abbreviations.botServices}${resourceName}-${resourceToken}'
    botOauthConnectionClientId: botOauthConnectionClientId
    botOauthConnectionClientSecret: botOauthConnectionClientSecret
  }
}

/*----------------------------------Outputs-----------------------------*/
output serverFullyQualifiedDomainName string = sqlModule.?outputs.serverFullyQualifiedDomainName ?? ''
output sqlDatabaseName string = sqlModule.?outputs.sqlDatabaseName ?? ''
output sqlDatabaseResourceId string = sqlModule.?outputs.sqlDatabaseResourceId ?? ''
output userManagedIdentityResourceId string = userAssignedIdentityModule.outputs.resourceId
output userManagedIdentityName string = userAssignedIdentityModule.outputs.name
output userManagedIdentityClientId string = userAssignedIdentityModule.outputs.clientId
output sqlServerUserIdentityPrincipalId string = sqlModule.?outputs.sqlServerUserIdentityPrincipalId ?? ''
output azureAiSearchApiKey string = aiSearchModule.?outputs.primaryKey ?? ''
output azureAiSearchEndpoint string = aiSearchModule.?outputs.endpoint ?? ''
output aiFoundryResourceName string = aiFoundry.?outputs.aiFoundryResourceName ?? ''
output aiFoundryProjectEndpoint string = aiFoundry.?outputs.aiFoundryProjectEndpoint ?? ''
output aiFoundryProjectConnectionAiSearchName string = aiFoundry.?outputs.aiFoundryProjectConnectionAiSearchName ?? ''
output azureKeyVaultName string = kvModule.?outputs.kvName ?? ''
output aiFoundryProjectConnectionAiSearchResourceId string = aiFoundry.?outputs.aiFoundryProjectConnectionAiSearchResourceId ?? ''
output botWebAppDomain string = webAppModule.?outputs.webAppDomain ?? ''
output botId string = botService.?outputs.botId ?? ''
output webAppResourceName string = webAppModule.?outputs.webAppResourceName ?? ''
output webAppResourceId string = webAppModule.?outputs.webAppResourceId ?? ''
