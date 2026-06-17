import {
  tenant
} from './config.bicep'

@description('Location of resources')
param location string

@description('The app service name')
param siteName string

@description('The app service plan name')
param appServiceName string

@description('User assigned identity resource ID')
param userAssignedIdentityResourceId string

@description('Storage account resource ID')
param deploymentStorageAccountResourceId string

@description('Storage account resource ID for logs')
param logsModuleStorageAccountResourceId string

@description('Application Insights resource ID')
param applicationInsightsResourceId string

@description('The runtime stack for the web app')
param stack string = 'node'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: last(split(userAssignedIdentityResourceId, '/'))
}

resource deploymentStorageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: last(split(deploymentStorageAccountResourceId, '/'))
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: last(split(applicationInsightsResourceId, '/'))
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  params: {
    name: appServiceName
    sku: {
      name: 'B1'
      tier: 'Basic'
    }
    reserved: false
    location: location
  }
}

module webApp 'br/public:avm/res/web/site:0.19.3' = {
  name: 'webapp'
  params: {
    kind: 'app,linux'
    name: siteName
    location: location

    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled ? 'Enabled' : 'Disabled'
    
    serverFarmResourceId: appServicePlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentityResourceId
      ]
    }

    keyVaultAccessIdentityResourceId: userAssignedIdentityResourceId

    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: stack == 'python' ? 'PYTHON|3.14' : 'NODE|24-lts'
      alwaysOn: false
      cors: {
        allowedOrigins: tenant.publicNetworkAccess.isEnabled ? ['*'] : []
        supportCredentials: false
      }      
    }

    configs: [
      {
        name: 'appsettings'
        properties:{
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__blobServiceUri: 'https://${deploymentStorageAccount.name}.blob.${environment().suffixes.storage}'
          AzureWebJobsStorage__queueServiceUri: 'https://${deploymentStorageAccount.name}.queue.${environment().suffixes.storage}'
          AzureWebJobsStorage__tableServiceUri: 'https://${deploymentStorageAccount.name}.table.${environment().suffixes.storage}'
          AzureWebJobsStorage__accountName: deploymentStorageAccount.name
          AzureWebJobsStorage__clientId: userAssignedIdentity.properties.clientId
          APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${userAssignedIdentity.properties.clientId};Authorization=AAD'   
        }
      }      
  ]
    
    diagnosticSettings: [
      {
        name: siteName
        storageAccountResourceId: logsModuleStorageAccountResourceId
      }
    ]
  }
}

output webAppDomain string = webApp.outputs.defaultHostname
output webAppResourceName string = webApp.outputs.name
output webAppResourceId string = webApp.outputs.resourceId
