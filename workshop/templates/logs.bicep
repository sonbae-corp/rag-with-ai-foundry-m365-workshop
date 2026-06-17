import {
  global
  tenant
} from './config.bicep'

param location string
param storageAccountName string

param subnetForPrivateEndpointsResourceId string = ''

param userAssignedIdentityPrincipalId string

module saLogs 'br/public:avm/res/storage/storage-account:0.20.0' = {
  name: '${global.abbreviations.deployments}saLogs-${location}'
  params: {
    name: storageAccountName
    location: location

    kind: 'StorageV2'
    skuName: 'Standard_LRS'

    allowSharedKeyAccess: false
    publicNetworkAccess: tenant.publicNetworkAccess.isEnabled ? 'Enabled' : 'Disabled'

    fileServices: {
      shareDeleteRetentionPolicy: {
        allowPermanentDelete: true
        enabled: false
      }
    }

    blobServices: {
      containerDeleteRetentionPolicyEnabled: false
      deleteRetentionPolicyEnabled: false
      containerDeleteRetentionPolicyAllowPermanentDelete: true
      deleteRetentionPolicyAllowPermanentDelete: true
      isVersioningEnabled: false
      restorePolicyEnabled: false

      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: [
            'DELETE'
            'GET'
            'HEAD'
            'OPTIONS'
            'PATCH'
            'POST'
            'PUT'
          ]
          maxAgeInSeconds: 20
          exposedHeaders: ['*']
          allowedHeaders: ['*']
        }
      ]
    }

    networkAcls:  {
        bypass: 'AzureServices'
        defaultAction: 'Deny'
        ipRules: [
          for ip in tenant.publicNetworkAccess.networkAcls.addressPrefixIPs: {
            action: 'Allow'
            value: ip
          }
        ]
        virtualNetworkRules: tenant.isProduction ? [
          {
            action: 'Allow'
            id: subnetForPrivateEndpointsResourceId
          }
        ] : null
    }

    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'

    managementPolicyRules: [
      {
        definition: {
          actions: {
            baseBlob: {
              delete: {
                daysAfterModificationGreaterThan: 180
              }
            }
          }
          filters: {
            blobTypes: ['blockBlob', 'appendBlob']
            prefixMatch: ['']
          }
        }
        enabled: true
        name: 'Cleanup after 180 days'
        type: 'Lifecycle'
      }
    ]
  }
}

module logsRoleAssignments './logs-role-assignments.bicep' = {
  name: '${global.abbreviations.deployments}logsRoleAssignments-${location}'
  params: {
    storageAccountResourceId: saLogs.outputs.resourceId
    userAssignedIdentityPrincipalId: userAssignedIdentityPrincipalId
  }
}

output storageAccountResourceId string = saLogs.outputs.resourceId
output storageAccountResourceName string = saLogs.outputs.name
