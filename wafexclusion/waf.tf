# Simplified WAF Demo: Two Application Gateways, Two WAF Policies
# AGW 1: Standard WAF (blocks 941170)
# AGW 2: WAF with custom exclusion for /admin/users path

# WAF Policy 1: Standard Protection (NO exclusions)
resource "azurerm_web_application_firewall_policy" "standard" {
  name                = "${var.prefix}1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = azurerm_resource_group.main.tags

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb    = 100
  }

  # NO custom rules - all managed rules active

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
      
      # Explicitly enable 941170 (it's enabled by default, but making it clear)
      rule_group_override {
        rule_group_name = "REQUEST-941-APPLICATION-ATTACK-XSS"
        
        rule {
          id      = "941170"
          enabled = true
          action  = "Block"
        }
      }
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}

# WAF Policy 2: With Custom Exclusion for /admin/users
resource "azurerm_web_application_firewall_policy" "with_exclusion" {
  name                = "${var.prefix}2"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = azurerm_resource_group.main.tags

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb    = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
      
      rule_group_override {
        rule_group_name = "REQUEST-941-APPLICATION-ATTACK-XSS"
        
        rule {
          id      = "941170"
          enabled = true
          action  = "Block"
        }
      }
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }

  custom_rules {
    name      = "AllowAdminUsersPath"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Allow"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator     = "BeginsWith"
      match_values = ["/admin/users"]
    }
  }
}

# Public IP for Application Gateway 1 (Standard WAF)
resource "azurerm_public_ip" "appgw1" {
  name                = "${var.prefix}2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

# Public IP for Application Gateway 2 (With Exclusion)
resource "azurerm_public_ip" "appgw2" {
  name                = "${var.prefix}3"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

# Subnet for Application Gateway 1
resource "azurerm_subnet" "appgw1" {
  name                 = "${var.prefix}2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Subnet for Application Gateway 2
resource "azurerm_subnet" "appgw2" {
  name                 = "${var.prefix}3"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Application Gateway 1: Standard WAF (NO exclusions)
resource "azurerm_application_gateway" "standard" {
  name                = "${var.prefix}1"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = azurerm_resource_group.main.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw1.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw1.id
  }

  backend_address_pool {
    name         = "backend-pool"
    ip_addresses = [azurerm_network_interface.backend.private_ip_address]
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 20
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
    firewall_policy_id             = azurerm_web_application_firewall_policy.standard.id
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
}

# Application Gateway 2: With Custom Exclusion
resource "azurerm_application_gateway" "with_exclusion" {
  name                = "${var.prefix}2"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = azurerm_resource_group.main.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw2.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw2.id
  }

  backend_address_pool {
    name         = "backend-pool"
    ip_addresses = [azurerm_network_interface.backend.private_ip_address]
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 20
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
    firewall_policy_id             = azurerm_web_application_firewall_policy.with_exclusion.id
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
}

# Diagnostic Settings for AppGW 1 (Standard)
resource "azurerm_monitor_diagnostic_setting" "appgw1" {
  name                           = "${var.prefix}1"
  target_resource_id             = azurerm_application_gateway.standard.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic Settings for AppGW 2 (With Exclusion)
resource "azurerm_monitor_diagnostic_setting" "appgw2" {
  name                           = "${var.prefix}2"
  target_resource_id             = azurerm_application_gateway.with_exclusion.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
