// Define the target scope for the Bicep file.
targetScope = 'subscription'


//********************************************
// Parameters
//********************************************

@description('A unique token used for resource name generation.')
@minLength(5)
param prefix string

@description('Primary region for all Azure resources.')
@minLength(1)
param location string

@description('The IP address to allow access to the function app.')
param myIpAddress string

@description('My User Object Id.')
param myObjectId string

@description('Language runtime used by the function app.')
@allowed(['dotnet-isolated','python','java', 'node', 'powerShell'])
param functionAppRuntime string = 'node' //Defaults to Node.js

@description('Target language version used by the function app.')
@allowed(['3.10','3.11', '7.4', '8.0', '9.0', '10', '11', '17', '20'])
param functionAppRuntimeVersion string = '20' //Defaults to Node.js 20

@description('The maximum scale-out instance count limit for the app.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

@description('The memory size of instances used by the app.')
@allowed([512,2048,4096])
param instanceMemoryMB int = 2048





//********************************************
// Resource Group Creation
//********************************************

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: prefix
  location: location
  tags: {
    'azd-env-name': prefix
  }
}

//********************************************
// Deploy resources to the resource group
//********************************************

module functionAppResources 'function.flex.bicep' = {
  name: 'functionAppDeployment'
  scope: resourceGroup
  params: {
    location: location
    functionAppRuntime: functionAppRuntime
    functionAppRuntimeVersion: functionAppRuntimeVersion
    maximumInstanceCount: maximumInstanceCount
    instanceMemoryMB: instanceMemoryMB
    prefix: prefix
    myIpAddress: myIpAddress
    myObjectId: myObjectId
  }
}

module ApplicationGatewayResources 'agw.bicep' = {
  name: 'ApplicationGatewayDeployment'
  scope: resourceGroup
  params: {
    prefix: prefix
    location: location
    functionAppPrivateIP: functionAppResources.outputs.functionAppPrivateIP
  }
  dependsOn: [
    functionAppResources
  ]
}

//********************************************
// Outputs
//********************************************

@description('The name of the resource group.')
output resourceGroupName string = resourceGroup.name

@description('The name of the function app.')
output functionAppName string = functionAppResources.outputs.functionAppName

@description('The default hostname of the function app.')
output functionAppHostName string = functionAppResources.outputs.functionAppHostName

@description('The resource ID of the function app.')
output functionAppResourceId string = functionAppResources.outputs.functionAppResourceId

@description('The name of the storage account.')
output storageAccountName string = functionAppResources.outputs.storageAccountName

@description('The name of the Application Insights instance.')
output applicationInsightsName string = functionAppResources.outputs.applicationInsightsName

@description('The URL of the Application Gateway.')
output applicationGatewayUrl string = ApplicationGatewayResources.outputs.applicationGatewayUrl

@description('The FQDN of the Application Gateway.')
output applicationGatewayFqdn string = ApplicationGatewayResources.outputs.applicationGatewayFqdn

@description('The public IP address of the Application Gateway.')
output applicationGatewayPublicIp string = ApplicationGatewayResources.outputs.applicationGatewayPublicIp

@description('The URL of the Function App.')
output functionAppUrl string = ApplicationGatewayResources.outputs.functionAppUrl
