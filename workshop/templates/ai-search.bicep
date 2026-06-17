import {
  RBACPrincipalType
} from './types.bicep'

import {
  tenant
} from './config.bicep'

@description('A list of Azure Active Directory principals (users, groups, or service principals) and their types to be assigned specific roles for resource access')
param rbacPrincipalsList RBACPrincipalType[]

@description('User assigned identity to be assigned to this resource')
param userAssignedIdentityResourceName string

@description('Name of the search service resource')
param aiSearchServiceName string

@description('Region location')
param location string

@description('Storage Account resource id for diagnostic settings')
param storageAccountResourceId string

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: userAssignedIdentityResourceName
}

var rbacAiSearchIndexContributor = [
  for p in rbacPrincipalsList: {
    principalId: p.principalId
    principalType: p.principalType
    roleDefinitionIdOrName: 'Search Index Data Contributor'
  }
]

var aiSearchRoleAssignments = concat(
  rbacAiSearchIndexContributor,
  [
      {
        principalId: userAssignedIdentity.properties.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Search Index Data Reader'
      }
  ]
)

module aiSearch 'br/public:avm/res/search/search-service:0.11.0' = {

  params: {
    name: aiSearchServiceName
    location: location
    cmkEnforcement: 'Disabled'
    disableLocalAuth: false
    hostingMode: 'default'
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        userAssignedIdentity.id
      ]
    }
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled ? 'Enabled' : 'Disabled'
    networkRuleSet: {
      bypass: 'AzureServices'
      ipRules: [
        for ip in tenant.publicNetworkAccess.networkAcls.addressPrefixIPs: {
          value: ip
        }
      ]
    }

    diagnosticSettings: [
      {
        name: aiSearchServiceName
        storageAccountResourceId: storageAccountResourceId
      }
    ]
    
    semanticSearch: 'free'
    sku: 'basic'
    roleAssignments: aiSearchRoleAssignments
    replicaCount: 1
    partitionCount: 1
  }
}

output primaryKey string = aiSearch.outputs.primaryKey
output endpoint string = aiSearch.outputs.endpoint
output resourceId string = aiSearch.outputs.resourceId
output name string = aiSearch.outputs.name
