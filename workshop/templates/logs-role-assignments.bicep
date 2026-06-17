param storageAccountResourceId string

param userAssignedIdentityPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: last(split(storageAccountResourceId, '/'))
}

resource storageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, userAssignedIdentityPrincipalId, 'Storage Blob Data Owner')
  properties: {
    principalId: userAssignedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    )
    principalType: 'ServicePrincipal'
  }
  scope: storageAccount
}
