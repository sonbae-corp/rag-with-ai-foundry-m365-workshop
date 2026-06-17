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

@description('Key Vault resource name')
param kvName string

@description('Region location')
param location string

@description('Resource ID of the subnet where the endpoint needs to be created for this resource.')
param subnetResourceId string = ''

@description('Storage Account resource id for diagnostic settings')
param storageAccountResourceId string

@description('Tags to be associated with the resources')
param tags object

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' existing = {
  name: userAssignedIdentityResourceName
}

var rbacKeyVaultRoleAssignments = [
  for p in rbacPrincipalsList: {
    principalId: p.principalId
    principalType: p.principalType
    roleDefinitionIdOrName: 'Key Vault Administrator'
  }
]

var keyVaultRoleAssignments = concat(rbacKeyVaultRoleAssignments, [
  {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Key Vault Crypto Service Encryption User'
  }
  {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Key Vault Certificates Officer'
  }
  {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Key Vault Secrets Officer'
  }
])

module kv 'br/public:avm/res/key-vault/vault:0.13.0' = {
  params: {
    name: kvName
    tags: union(tags, {
      'azd-keyvault-identity': userAssignedIdentity.id
    })
    location: location
    sku: 'premium'
    enableVaultForDeployment: true
    enableVaultForDiskEncryption: true
    enableVaultForTemplateDeployment: true
    enablePurgeProtection: tenant.isProduction ? true : false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90

    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled ? 'Enabled' : 'Disabled'

    networkAcls: {
      virtualNetworkRules: tenant.isProduction ? [
        {
          action: 'Allow'
          id: subnetResourceId
        }
      ] : null
      bypass: 'AzureServices'
      defaultAction: tenant.publicNetworkAccess.isEnabled ? 'Allow' : 'Deny'
      ipRules: [
        for item in tenant.publicNetworkAccess.networkAcls.addressPrefixCIDRs: {
          value: item
        }
      ]
      
    }
    privateEndpoints: tenant.isProduction ? [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: format(
                '/subscriptions/{0}/resourceGroups/{1}{2}',
                tenant.vnet.privateEndpoints.privateDnsZones.subscription,
                tenant.vnet.privateEndpoints.privateDnsZones.resourceGroup,
                tenant.vnet.privateEndpoints.privateDnsZones.providers.keyVault
              )
            }
          ]
        }
        subnetResourceId: subnetResourceId
      }
    ]: null

    roleAssignments: keyVaultRoleAssignments

    diagnosticSettings: [
      {
        logCategoriesAndGroups: [
          {
            category: 'AzurePolicyEvaluationDetails'
          }
          {
            category: 'AuditEvent'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: kvName
        storageAccountResourceId: storageAccountResourceId
      }
    ]
  }
}

output kvName string = kvName
