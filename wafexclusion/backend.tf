# Test Backend VM to simulate a web server
resource "azurerm_network_interface" "backend" {
  name                = "${local.resource_prefix}-backend-nic-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = azurerm_resource_group.main.tags
}

# Test VM to act as backend web server
resource "azurerm_linux_virtual_machine" "backend" {
  name                = "${local.resource_prefix}-backend-vm-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  # Disable password authentication and use SSH key
  disable_password_authentication = false
  admin_password                  = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.backend.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Install nginx and create test pages
  custom_data = base64encode(file("${path.module}/scripts/setup-webserver-simple.sh"))

  tags = azurerm_resource_group.main.tags
}

# Public IP for direct access to backend (for testing)
resource "azurerm_public_ip" "backend" {
  name                = "${local.resource_prefix}-backend-pip-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = azurerm_resource_group.main.tags
}

# Associate public IP with backend NIC
resource "azurerm_network_interface" "backend_public" {
  name                = "${local.resource_prefix}-backend-public-nic-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.backend.id
  }

  tags = azurerm_resource_group.main.tags
}

# Note: For simplicity, we're using separate NICs instead of multiple IP configs
# In production, you'd typically use a single NIC with multiple IP configurations