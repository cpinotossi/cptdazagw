resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = var.prefix
  tags     = {}
}

resource "azurerm_virtual_network" "vnet" {
  address_space       = ["10.0.0.0/16"]
  dns_servers         = []
  location            = azurerm_resource_group.rg.location
  name                = var.prefix
  resource_group_name = azurerm_resource_group.rg.name
  tags                = {}
}
resource "azurerm_subnet" "subnetagw" {
  address_prefixes                              = ["10.0.0.0/24"]
  default_outbound_access_enabled               = true
  name                                          = "agwsubnet"
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
  resource_group_name                           = azurerm_resource_group.rg.name
  service_endpoint_policy_ids                   = []
  service_endpoints                             = ["Microsoft.Storage"]
  virtual_network_name                          = var.prefix
  depends_on = [
    azurerm_virtual_network.vnet,
  ]
}

resource "azurerm_subnet" "subnetdefault" {
  address_prefixes                              = ["10.0.1.0/24"]
  default_outbound_access_enabled               = true
  name                                          = "default"
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = true
  resource_group_name                           = azurerm_resource_group.rg.name
  service_endpoint_policy_ids                   = []
  service_endpoints                             = []
  virtual_network_name                          = var.prefix
  depends_on = [
    azurerm_virtual_network.vnet,
  ]
}


data "azurerm_client_config" "current" {}

resource "azurerm_log_analytics_workspace" "law" {
  name                = var.prefix
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = {}
}

