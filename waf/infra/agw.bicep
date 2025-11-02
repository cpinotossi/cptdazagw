@description('Location for all resources')
param location string

@description('Name prefix for all resources')
param prefix string

@description('Function App private IP address for backend')
param functionAppPrivateIP string


// Removed myIpAddress parameter since we're allowing anonymous access

// Variables
// var resourceToken = substring(uniqueString(resourceGroup().id), 0, 6)
var functionAppName = prefix
// var functionAppPlanName = prefix
// var storageAccountName = 'funcstore${resourceToken}'
// var storageDownloadName = 'download${resourceToken}'
var applicationGatewayName = prefix
var virtualNetworkName = prefix
var publicIpName = '${prefix}agw'
var wafPolicyName = prefix
// var applicationInsightsName = '${prefix}-insights'
// var logAnalyticsWorkspaceName = '${prefix}-logs'

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' existing = {
  name: virtualNetworkName
}

resource subnetAgw 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: 'AzureAGWSubnet'
  parent: virtualNetwork
}

// Public IP for Application Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: prefix
    }
  }
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-04-01' = {
  name: wafPolicyName
  location: location
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
    customRules: [
      {
        name: 'BlockEvilQuery'
        priority: 100
        ruleType: 'MatchRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'QueryString'
              }
            ]
            operator: 'Contains'
            negationConditon: false
            matchValues: [
              'evil=true'
            ]
            transforms: [
              'Lowercase'
            ]
          }
        ]
      }
    ]
  }
}

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetAgw.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'functionAppBackendPool'
        properties: {
          backendAddresses: [
            {
              ipAddress: functionAppPrivateIP
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'functionAppBackendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          hostName: '${functionAppName}.azurewebsites.net'
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'functionAppProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule1'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'functionAppBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'functionAppBackendHttpSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'functionAppProbe'
        properties: {
          protocol: 'Https'
          path: '/api/httptrigger'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
    enableHttp2: false
  }
}

// Outputs
output applicationGatewayPublicIp string = publicIp.properties.ipAddress
output applicationGatewayFqdn string = publicIp.properties.dnsSettings.fqdn
output functionAppUrl string = 'https://${functionAppName}.azurewebsites.net'
output applicationGatewayUrl string = 'http://${publicIp.properties.dnsSettings.fqdn}'
output functionAppName string = functionAppName
