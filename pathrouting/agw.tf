resource "azurerm_application_gateway" "agw" {
  location            = azurerm_resource_group.rg.location
  name                = var.prefix
  resource_group_name = azurerm_resource_group.rg.name
  tags                = {}
  zones               = ["1", "2", "3"]
  autoscale_configuration {
    max_capacity = 10
    min_capacity = 1
  }
  backend_address_pool {
    fqdns = ["${var.storage_account_name_1}.blob.core.windows.net"]
    name  = "storage1"
  }
  backend_address_pool {
    fqdns = ["${var.storage_account_name_2}.blob.core.windows.net"]
    name  = "storage2"
  }
  backend_http_settings {
    name                                = "storage1"
    cookie_based_affinity               = "Disabled"
    pick_host_name_from_backend_address = true
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 20
    probe_name                          = "storage1"
  }
  backend_http_settings {
    name                                = "storage2"
    cookie_based_affinity               = "Disabled"
    pick_host_name_from_backend_address = true
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 20
    probe_name                          = "storage2"
  }
  frontend_ip_configuration {
    name                          = "appGwPublicFrontendIpIPv4"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pubipagw.id
  }
  frontend_port {
    name = "port_80"
    port = 80
  }
  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.subnetagw.id
  }
  http_listener {
    frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
    frontend_port_name             = "port_80"
    host_name                      = ""
    host_names                     = ["${var.prefix}.swedencentral.cloudapp.azure.com"]
    name                           = "public"
    protocol                       = "Http"
  }
  probe {
    host                                      = ""
    interval                                  = 30
    minimum_servers                           = 0
    name                                      = "storage1"
    path                                      = "/container1/heartbeat.html"
    pick_host_name_from_backend_http_settings = true
    port                                      = 443
    protocol                                  = "Https"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    match {
      body        = ""
      status_code = ["200-399"]
    }
  }
  probe {
    host                                      = ""
    interval                                  = 30
    minimum_servers                           = 0
    name                                      = "storage2"
    path                                      = "/container2/heartbeat.html"
    pick_host_name_from_backend_http_settings = true
    port                                      = 443
    protocol                                  = "Https"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    match {
      body        = ""
      status_code = ["200-399"]
    }
  }
  request_routing_rule {
    backend_address_pool_name  = "storage1"
    backend_http_settings_name = "storage1"
    http_listener_name         = "public"
    name                       = "storage1"
    priority                   = 2
    rule_type                  = "PathBasedRouting"
    url_path_map_name          = var.prefix
  }

  url_path_map {
    name                               = var.prefix
    default_backend_address_pool_name  = "storage1"
    default_backend_http_settings_name = "storage1"
    path_rule {
      name                       = "container2"
      paths                      = ["/container1/container2/*"]
      backend_address_pool_name  = "storage2"
      backend_http_settings_name = "storage2"
      rewrite_rule_set_name      = "storage2"
    }
    path_rule {
      name                       = "container1"
      paths                      = ["/container1/*"]
      backend_address_pool_name  = "storage1"
      backend_http_settings_name = "storage1"
    }
  }

  rewrite_rule_set {
    name = "storage2"
    rewrite_rule {
      name          = "storage2"
      rule_sequence = 100
      condition {
        ignore_case = true
        negate      = false
        pattern     = "/container1(/container2/.*)"
        variable    = "var_uri_path"
      }
      url {
        components   = "path_only"
        path         = "{var_uri_path_1}"
        query_string = ""
        reroute      = false
      }
    }
  }

  sku {
    capacity = 0
    name     = "Standard_v2"
    tier     = "Standard_v2"
  }
  depends_on = [
    azurerm_public_ip.pubipagw,
    azurerm_subnet.subnetagw,
    azurerm_public_ip.pubipagw,
    azurerm_log_analytics_workspace.law,
    azurerm_storage_blob.batman_blob,
    azurerm_storage_blob.spiderman_blob
  ]
}

resource "azurerm_public_ip" "pubipagw" {
  allocation_method       = "Static"
  domain_name_label       = var.prefix
  ddos_protection_mode    = "VirtualNetworkInherited"
  idle_timeout_in_minutes = 4
  ip_tags                 = {}
  ip_version              = "IPv4"
  location                = azurerm_resource_group.rg.location
  name                    = var.prefix
  resource_group_name     = azurerm_resource_group.rg.name
  sku                     = "Standard"
  sku_tier                = "Regional"
  tags                    = {}
  zones                   = ["1", "2", "3"]
  depends_on = [
    azurerm_resource_group.rg,
  ]
}

resource "azurerm_monitor_diagnostic_setting" "agw_diagnostic" {
  name                           = var.prefix
  target_resource_id             = azurerm_application_gateway.agw.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
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