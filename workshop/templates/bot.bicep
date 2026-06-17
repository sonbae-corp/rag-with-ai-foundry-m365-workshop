@description('User assigned identity resource ID')
param userAssignedIdentityResourceId string

param botDisplayName string

param botServiceName string

param botServiceSku string = 'F0'

param botAppDomain string

@description('OAuth2 connection client ID for Bot Service to connect to Microsoft Graph')
param botOauthConnectionClientId string = ''

@description('OAuth2 connection client secret for Bot Service to connect to Microsoft Graph')
@secure()
param botOauthConnectionClientSecret string = ''

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: last(split(userAssignedIdentityResourceId, '/'))
}

// Register your web service as a bot with the Bot Framework
resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  kind: 'azurebot'
  location: 'global'
  name: botServiceName
  properties: {
    displayName: botDisplayName
    endpoint: 'https://${botAppDomain}/api/messages'
    msaAppId: userAssignedIdentity.properties.clientId
    msaAppMSIResourceId: userAssignedIdentity.id
    msaAppTenantId: userAssignedIdentity.properties.tenantId
    msaAppType:'UserAssignedMSI'
    disableLocalAuth: true
  }
  sku: {
    name: botServiceSku
  }
}

// Connect the bot service to Microsoft Teams
resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2021-03-01' = {
  parent: botService
  location: 'global'
  name: 'MsTeamsChannel'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

// OAuth2 connection
resource botServiceAADv2OAuthConnection 'Microsoft.BotService/botServices/connections@2023-09-15-preview' = {
  parent: botService
  kind: 'azurebot'
  location: 'global'
  name: 'copilotCustomAuth'
  properties: {
    clientId: botOauthConnectionClientId
    clientSecret: botOauthConnectionClientSecret
    name: 'copilotCustomAuth'
    parameters: [
      {
        key: 'TenantId'
        value: tenant().tenantId
      }
    ]
    scopes: 'ExternalItem.Read.All'
    serviceProviderDisplayName: 'Azure Active Directory v2'
    serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c' // Azure Active Directory v2
  }
}

output botId string = botService.properties.msaAppId
