resource "azurerm_application_insights" "appinsights" {
  name                = "${var.project_name}-${var.environment}-ai"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
}