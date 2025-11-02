$prefix = "cptdazagwwaf"
$location = "germanywestcentral"
$myIpAddress = (Invoke-RestMethod -Uri "http://ipinfo.io/json").ip
$myObjectId = az ad signed-in-user show --query id -o tsv
$deploymentResult = az deployment sub create -l $location -f "infra/main.bicep" -p prefix=$prefix location=$location myIpAddress=$myIpAddress myObjectId=$myObjectId functionAppRuntime=node functionAppRuntimeVersion=20 -o json | ConvertFrom-Json
# Get the outputs
$outputs = $deploymentResult.properties.outputs
$appGatewayUrl = $outputs.applicationGatewayUrl.value
$functionAppUrl = $outputs.functionAppUrl.value
$publicIp = $outputs.applicationGatewayPublicIp.value
$functionAppName = $outputs.functionAppName.value
$resourceGroupName = $outputs.resourceGroupName.value
# Publish the Function App
func azure functionapp publish $functionAppName --force --build remote


Write-Host "`n🧪 Testing URLs:" -ForegroundColor Cyan
Write-Host "   Normal request: $appGatewayUrl/?test=normal" -ForegroundColor Green
Write-Host "   Blocked request: $appGatewayUrl/?evil=true" -ForegroundColor Red
Write-Host "   Direct Function App: $functionAppUrl/api/HttpTrigger" -ForegroundColor Blue

Write-Host "`n✨ Deployment complete! The WAF will block requests with 'evil=true' query parameter." -ForegroundColor Green

Write-Host "`n🔒 Optional: Apply security hardening (disable shared key access):" -ForegroundColor Cyan
Write-Host "   .\secure-storage.ps1 -ResourceGroupName $resourceGroupName" -ForegroundColor Yellow

Write-Host "🔍 Getting deployment operation details..." -ForegroundColor Yellow

# Get the last deployment operation details
az deployment group list --resource-group $resourceGroupName --query "[0]" -o json

# Get activity log for more details
Write-Host "Recent activity log entries:" -ForegroundColor Yellow
az monitor activity-log list --resource-group $resourceGroupName --max-events 5 --offset 1h -o table
    
