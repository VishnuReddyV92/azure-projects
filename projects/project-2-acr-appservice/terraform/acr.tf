resource "azurerm_container_registry" "acr" {
  name                = "${var.project_name}${var.environment}acr${var.unique_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false
}