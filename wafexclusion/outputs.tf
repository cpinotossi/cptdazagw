# Output values for dual-AGW testing
output "agw_standard_public_ip" {
  description = "Public IP of AGW with standard WAF (blocks all XSS)"
  value       = azurerm_public_ip.appgw1.ip_address
}

output "agw_exclusion_public_ip" {
  description = "Public IP of AGW with custom exclusion (allows /admin/users)"
  value       = azurerm_public_ip.appgw2.ip_address
}

output "backend_vm_private_ip" {
  description = "Private IP address of the shared backend VM"
  value       = azurerm_network_interface.backend.private_ip_address
}

output "backend_vm_public_ip" {
  description = "Public IP address of the backend VM (for direct testing)"
  value       = azurerm_public_ip.backend.ip_address
}

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "log_analytics_workspace_name" {
  description = "Name of the shared Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "test_commands" {
  description = "curl commands for testing WAF behavior"
  value = <<-EOT
    
    🛡️ Dual-AGW WAF Exclusion Demo Deployed!
    
    📊 Test Configuration:
    • AGW-STD:  ${azurerm_public_ip.appgw1.ip_address} (blocks all 941170)
    • AGW-EXCL: ${azurerm_public_ip.appgw2.ip_address} (allows /admin/users)
    • Backend:  ${azurerm_network_interface.backend.private_ip_address}
    
    📋 Test 1: Normal Request (Both AGWs Allow)
    http GET http://${azurerm_public_ip.appgw1.ip_address}/admin/users
    http GET http://${azurerm_public_ip.appgw2.ip_address}/admin/users
    Expected: Both return 200 OK

    📋 Test 2: XSS on /admin/users (Standard Blocks, Exclusion Allows)
    http GET http://${azurerm_public_ip.appgw1.ip_address}/admin/users "Referer:javascript:alert(1)"
    Expected: 403 Forbidden (rule 941170)

    http GET http://${azurerm_public_ip.appgw2.ip_address}/admin/users "Referer:javascript:alert(1)"
    Expected: 200 OK (custom allow rule bypassed WAF)

    📋 Test 3: XSS on /test-xss (Both AGWs Block)
    http GET http://${azurerm_public_ip.appgw1.ip_address}/test-xss "Referer:javascript:alert(1)"
    http GET http://${azurerm_public_ip.appgw2.ip_address}/test-xss "Referer:javascript:alert(1)"
    Expected: Both return 403 Forbidden

    📋 Test 4: Direct Backend Access
    http --timeout 10 GET http://${azurerm_public_ip.backend.ip_address}/admin/users
    Expected: Connection timeout (backend isolated)
    
    🔍 Monitor WAF Logs:
    AGWFirewallLogs
    | where TimeGenerated > ago(1h)
    | where action_s == "Blocked" or action_s == "Matched"
    | project TimeGenerated, Resource, requestUri_s, action_s, Message
    | order by TimeGenerated desc
    
    🧹 Cleanup: terraform destroy -auto-approve
    
  EOT
}