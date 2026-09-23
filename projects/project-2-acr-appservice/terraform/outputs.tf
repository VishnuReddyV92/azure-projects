output "acr_login_server" { value = azurerm_container_registry.acr.login_server }
output "acr_name"         { value = azurerm_container_registry.acr.name }
output "app_service_name" { value = azurerm_linux_web_app.app.name }
output "resource_group"   { value = azurerm_resource_group.main.name }