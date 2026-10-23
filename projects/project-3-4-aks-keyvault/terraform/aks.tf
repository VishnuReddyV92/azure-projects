resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aksproject34"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                          = "system"
    vm_size                       = var.system_node_vm_size
    vnet_subnet_id                = azurerm_subnet.aks.id
    node_count                    = 1
    only_critical_addons_enabled  = true   # app pods forced onto the user pool
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"       # real VNet IPs per pod, needed for private endpoints etc.
    service_cidr   = "10.20.0.0/16"
    dns_service_ip = "10.20.0.10"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
  }

  local_account_disabled    = true    # no static admin kubeconfig backdoor
  oidc_issuer_enabled       = true    # required for Workload Identity
  workload_identity_enabled = true    # installs the mutating webhook

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  tags = { project = "project-3-4-aks-keyvault" }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  auto_scaling_enabled  = true
  min_count             = var.user_pool_min_count
  max_count             = var.user_pool_max_count
  mode                  = "User"
}