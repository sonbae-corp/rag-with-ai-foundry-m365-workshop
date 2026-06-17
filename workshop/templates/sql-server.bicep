import {
  tenant
} from './config.bicep'

@description('Location of the resources')
param location string

@description('SQL Server name to be used')
param serverName string

@description('SQL Database name to be used')
param databaseName string

@description('SQL Administrator login name. Can be a user or a group')
param administratorLogin string

@description('SQL Administrator principal ID')
param administratorPrincipalId string

@description('User Assigned Managed Identity principal ID to be configured as reader on the database')
param userAssignedIdentityPrincipalId string

@description('User Assigned Managed Identity resource ID to be configured as identity for the SQL server')
param userAssignedIdentityResourceId string

@description('Storage account resource id used for audit logs')
param logsStorageAccountResourceId string

@description('The current IP address for the deployer')
param deployerIpAddress string

var sqlServerRoleAssignments = [
  {
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Reader'
  }
]

module sqlServer 'br/public:avm/res/sql/server:0.20.3' = {
  params: {
    name: serverName
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: administratorLogin
      sid: administratorPrincipalId
      tenantId: deployer().tenantId
      azureADOnlyAuthentication: true
    }
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentityResourceId
      ]
    }
    location: location
    restrictOutboundNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled ? 'Enabled' : 'Disabled'
    roleAssignments: sqlServerRoleAssignments

    primaryUserAssignedIdentityResourceId: userAssignedIdentityResourceId

  }
}

resource sqlServerFirewallRuleSet 'Microsoft.Sql/servers/firewallRules@2024-05-01-preview' = if (!tenant.isProduction) {
  parent: sqlServerAvm
  name: 'DeployerNetworkFirewallRules'
  properties: {
    startIpAddress: deployerIpAddress
    endIpAddress: deployerIpAddress
  }
}

resource sqlServerFirewallRuleSetAzureIps 'Microsoft.Sql/servers/firewallRules@2024-05-01-preview' = if (!tenant.isProduction) {
  parent: sqlServerAvm
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlServerAvm 'Microsoft.Sql/servers@2024-05-01-preview' existing = {
  name: serverName
  dependsOn: [
    sqlServer
  ]
}

resource sqlDb 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: sqlServerAvm
  name: databaseName
  location: location
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
    isLedgerOn: false
    autoPauseDelay: 60
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
  }
}

resource sqlServerDbDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlDb
  name: '${serverName}-ds' 
  properties: {
    storageAccountId: logsStorageAccountResourceId
    logs: [
      {
        category: null
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          days: 1850
          enabled: false
        }
      }
    ]
  }
}

output serverFullyQualifiedDomainName string = sqlServer.outputs.fullyQualifiedDomainName

output sqlDatabaseName string = sqlDb.name
output sqlDatabaseResourceId string = sqlDb.id
output sqlServerUserIdentityPrincipalId string = userAssignedIdentityPrincipalId
output sqlServerResourceId string = sqlServer.outputs.resourceId
output sqlServerResourceName string = sqlServer.outputs.name

