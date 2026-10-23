output "cluster_name"                { value = azurerm_kubernetes_cluster.main.name }
output "resource_group_name"         { value = azurerm_resource_group.main.name }
output "oidc_issuer_url"             { value = azurerm_kubernetes_cluster.main.oidc_issuer_url }
output "key_vault_name"              { value = azurerm_key_vault.main.name }
output "workload_identity_client_id" { value = azurerm_user_assigned_identity.app4.client_id }
output "kube_config_host" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive = true
}