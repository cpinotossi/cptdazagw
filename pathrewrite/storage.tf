module "storage1" {
  source                     = "./modules/storage_account"
  name                       = var.storage_account_name_1
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  virtual_network_subnet_ids = [azurerm_subnet.subnetagw.id]
  container_name             = "container1"
  depends_on                 = [azurerm_subnet.subnetagw]
}

module "storage2" {
  source                     = "./modules/storage_account"
  name                       = var.storage_account_name_2
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  virtual_network_subnet_ids = [azurerm_subnet.subnetagw.id]
  container_name             = "container1"
  depends_on                 = [azurerm_subnet.subnetagw]
}

resource "azurerm_role_assignment" "blob_contributor_storage1" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = module.storage1.storage_account_id
  depends_on           = [module.storage1]
}

resource "azurerm_role_assignment" "blob_contributor_storage2" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = module.storage2.storage_account_id
  depends_on           = [module.storage2]
}

resource "azurerm_storage_blob" "spiderman_blob" {
  name                   = "spiderman.txt"
  storage_account_name   = module.storage1.storage_account_name
  storage_container_name = module.storage1.container_name
  type                   = "Block"
  source                 = "spiderman.txt"
  depends_on             = [module.storage1, azurerm_role_assignment.blob_contributor_storage1]
}

resource "azurerm_storage_blob" "heartbeat1_blob" {
  name                   = "heartbeat.html"
  storage_account_name   = module.storage1.storage_account_name
  storage_container_name = module.storage1.container_name
  type                   = "Block"
  source                 = "heartbeat.html"
  depends_on             = [module.storage1, azurerm_role_assignment.blob_contributor_storage1]
}

resource "azurerm_storage_blob" "heartbeat2_blob" {
  name                   = "heartbeat.html"
  storage_account_name   = module.storage2.storage_account_name
  storage_container_name = module.storage2.container_name
  type                   = "Block"
  source                 = "heartbeat.html"
  depends_on             = [module.storage2, azurerm_role_assignment.blob_contributor_storage2]
}

resource "azurerm_storage_blob" "batman_blob" {
  name                   = "batman.txt"
  storage_account_name   = module.storage2.storage_account_name
  storage_container_name = module.storage2.container_name
  type                   = "Block"
  source                 = "batman.txt"
  depends_on             = [module.storage2, azurerm_role_assignment.blob_contributor_storage2]
}

resource "azurerm_monitor_diagnostic_setting" "storage1_diagnostic" {
  name                           = "storage1-diagnostic"
  target_resource_id             = "${module.storage1.storage_account_id}/blobServices/default"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
  depends_on = [module.storage1]
}

resource "azurerm_monitor_diagnostic_setting" "storage2_diagnostic" {
  name                           = "storage2-diagnostic"
  target_resource_id             = "${module.storage2.storage_account_id}/blobServices/default"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
  depends_on = [module.storage2]
}
