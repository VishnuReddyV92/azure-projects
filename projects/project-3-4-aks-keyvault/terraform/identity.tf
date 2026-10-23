# The Workload Identity itself
resource "azurerm_user_assigned_identity" "app4" {
  name                = "id-app4-workload"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Trusts tokens from THIS cluster's OIDC issuer, for THIS exact namespace:serviceaccount only
resource "azurerm_federated_identity_credential" "app4" {
  name                = "app4-fic"
  user_assigned_identity_id = azurerm_user_assigned_identity.app4.id
  #resource_group_name = azurerm_resource_group.main.name
  #parent_id           = azurerm_user_assigned_identity.app4.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
  audience            = ["api://AzureADTokenExchange"]
}

# Least privilege: read-only, scoped to this one vault
resource "azurerm_role_assignment" "app4_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app4.principal_id
}