resource "azurerm_service_plan" "plan" {
  name                = "${var.project_name}-${var.environment}-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_web_app" "app" {
  name                = "${var.project_name}-${var.environment}-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.plan.location
  service_plan_id     = azurerm_service_plan.plan.id

  identity { type = "SystemAssigned" }

  site_config {
    always_on = true
    application_stack {
      docker_image_name   = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
    health_check_path = "/health"
    health_check_eviction_time_in_min = 2
    container_registry_use_managed_identity = true
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE"   = "false"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.appinsights.connection_string
    "WEBSITES_PORT"                         = "8000"
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
      site_config[0].application_stack[0].docker_registry_url,
    ]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.app.id
  identity       { type = "SystemAssigned" }

  site_config {
    always_on = true
    application_stack {
      docker_image_name   = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
    health_check_path = "/health"
    health_check_eviction_time_in_min = 2
    container_registry_use_managed_identity = true
  }
   app_settings = {
    "WEBSITES_PORT"                         = "8000"
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
      site_config[0].application_stack[0].docker_registry_url,
    ]
  }
}