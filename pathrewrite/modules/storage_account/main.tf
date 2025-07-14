resource "azurerm_storage_account" "storage" {
  access_tier              = var.access_tier
  account_kind             = var.account_kind
  account_replication_type = var.account_replication_type
  account_tier             = var.account_tier
  location                 = var.location
  name                     = var.name
  resource_group_name      = var.resource_group_name

  blob_properties {
    change_feed_enabled      = var.change_feed_enabled
    last_access_time_enabled = var.last_access_time_enabled
    versioning_enabled       = var.versioning_enabled
  }

  network_rules {
    default_action             = var.default_action
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = var.virtual_network_subnet_ids
  }
}

resource "azurerm_storage_container" "container" {
  name                  = var.container_name
  storage_account_id  = azurerm_storage_account.storage.id
  container_access_type = var.container_access_type
}