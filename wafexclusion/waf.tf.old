# WAF Policy WITHOUT Exclusions (Standard Protection)
resource "azurerm_web_application_firewall_policy" "standard" {
  name                = "${local.resource_prefix}-wafpol-standard-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = azurerm_resource_group.main.tags

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb    = 100
  }

  # NO custom rules - all requests go through managed rules
  
  # Managed Rules - OWASP Core Rule Set 3.2
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}

# WAF Policy WITH URL-Specific Exclusion
resource "azurerm_web_application_firewall_policy" "with_exclusion" {
  name                = "${local.resource_prefix}-wafpol-exclusion-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = azurerm_resource_group.main.tags

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb    = 100
  }

  # Custom Rule: Allow /admin/content-editor to bypass all managed rules
  custom_rules {
    name      = "AllowContentEditorPath"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Allow"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "BeginsWith"
      negation_condition = false
      match_values       = ["/admin/content-editor"]
    }
  }

  # Managed Rules - OWASP Core Rule Set 3.2 (same as standard)
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}
          id      = "942100"
          enabled = true
          action  = "Block"
        }
        
        rule {
          id      = "942110"
          enabled = true
          action  = "Block"
        }
      }

      rule_group_override {
        rule_group_name = "REQUEST-930-APPLICATION-ATTACK-LFI"
        
        # Rules that might trigger on wp-admin
        rule {
          id      = "930100"
          enabled = true
          action  = "Block"
        }
      }
    }

    # Microsoft Bot Manager Rule Set
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }

    # Exclusions (these don't help with path-specific issues)
    exclusion {
      match_variable          = "RequestHeaderNames"
      selector               = "User-Agent"
      selector_match_operator = "Contains"
    }
  }
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "${local.resource_prefix}-appgw-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = azurerm_resource_group.main.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIp"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "backend-pool"
    ip_addresses = [azurerm_network_interface.backend.private_ip_address]
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 20
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 1
  }

  # SSL Policy Configuration
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  # Associate WAF Policy
  firewall_policy_id = azurerm_web_application_firewall_policy.main.id

  depends_on = [
    azurerm_web_application_firewall_policy.main
  ]
}

# Diagnostic setting to send WAF logs to Log Analytics (Resource-Specific)
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                           = "appgw-diagnostics"
  target_resource_id             = azurerm_application_gateway.main.id
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