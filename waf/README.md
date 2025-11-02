# Azure Application Gateway with WAF and Azure Functions

## Run Azure Function App Locally

This project demonstrates a simple Azure Application Gateway with Web Application Firewall (WAF) enabled, protecting an Azure Function backend.

## Architecture

- **Azure Application Gateway** with WAF v2 SKU
- **Custom WAF Rule** that blocks requests containing `evil=true` query parameter  
- **Azure Function** (HTTP Trigger) as the backend returning JSON
- **Virtual Network** with dedicated subnets for App Gateway and Function App
- **Public IP** for external access


~~~powershell
$prefix = "cptdazagwwaf"
# call poweershell script and provide parameters
.\deploy.ps1
# Testing the WAF Rule
# retrive the Application Gateway URL

$publicIpId = az network application-gateway show --resource-group $prefix --name $prefix --query "frontendIPConfigurations[0].publicIPAddress.id" -o tsv
$fqdn = az network public-ip show --ids $publicIpId --query "dnsSettings.fqdn" -o tsv
~~~

## Testing the WAF Rule

After deployment, test the custom WAF rule by calling the Function endpoints directly:

### ✅ **Allowed Requests** (should return JSON):
- `http://[agw-url]/api/HttpTrigger?test=normal`
- `http://[agw-url]/api/HttpTrigger?evil=false`  
- `http://[agw-url]/api/HttpTrigger?other=value`

### ❌ **Blocked Requests** (should return 403):
- `http://[agw-url]/api/HttpTrigger?evil=true`
- `http://[agw-url]/api/HttpTrigger?param1=value&evil=true`

## Key Features

### WAF Configuration
- **Mode**: Prevention (blocks malicious requests)
- **Rule Set**: OWASP 3.2 managed rules
- **Custom Rule**: Blocks requests with `evil=true` query parameter

### Application Gateway
- **SKU**: WAF_v2 (supports autoscaling and zone redundancy)
- **Capacity**: 1 instance (minimum for demo)
- **Frontend**: HTTP on port 80
- **Backend**: App Service with health probe

### Networking
- **VNet**: 10.0.0.0/16
- **App Gateway Subnet**: 10.0.1.0/24
- **App Service Subnet**: 10.0.2.0/24 (with delegation)

## Cleanup

To remove all resources:

```bash
az group delete --name rg-agw-demo-dev --yes --no-wait
```

## Customization

You can customize the deployment by modifying:

- **Parameters**: Edit `main.parameters.json`
- **WAF Rules**: Modify the `customRules` section in `main.bicep`
- **Backend App**: Replace `index.html` with your application
- **Networking**: Adjust VNet and subnet configurations

## Cost Considerations

This demo uses:
- Application Gateway WAF_v2 (hourly charges apply)
- App Service Basic B1 plan
- Standard Public IP
- Virtual Network (no additional charges)

Remember to delete resources after testing to avoid ongoing charges.

## Troubleshooting

### Fixed: Storage Account Issues (Azure Functions)

✅ **RESOLVED**: The circular dependency and storage container issues have been fixed in the latest version.

The template now automatically:
- Creates required storage containers (`deployments`, `azure-webjobs-hosts`, `azure-webjobs-secrets`)
- Manages dependencies correctly without circular references
- Uses managed identity authentication for enhanced security

If you still encounter deployment issues:

```powershell
# Run the troubleshooting script
.\troubleshoot-storage.ps1 -ResourceGroupName "your-resource-group"

# Validate template before deployment
.\validate-template.ps1 -ResourceGroupName "your-resource-group"

# Manual deployment retry if needed
az functionapp deployment source config-zip --resource-group "your-rg" --name "your-function-app" --src functionapp.zip
```


### Useful Commands:
```bash
# Check deployment status
az deployment group show --resource-group your-rg --name main

# Check Function App logs
az functionapp log tail --name your-function-app --resource-group your-rg

# Test backend health
az network application-gateway show-backend-health --resource-group your-rg --name your-agw
```
