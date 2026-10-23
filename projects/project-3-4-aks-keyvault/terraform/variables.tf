variable "location" {
  default = "centralindia"
}

variable "resource_group_name" {
  default = "rg-aks-keyvault"
}

variable "cluster_name" {
  default = "aks-project34"
}

variable "system_node_vm_size" {
  default = "Standard_D2s_v5"
}

variable "user_node_vm_size" {
  default = "Standard_D2s_v5"
}

variable "user_pool_min_count" {
  default = 1
}

variable "user_pool_max_count" {
  default = 3
}

variable "key_vault_name" {
  default = "kv-project34-vvr7421" # replace with a globally unique suffix, 3-24 chars total
}

variable "k8s_namespace" {
  default = "app4"
}

variable "k8s_service_account_name" {
  default = "app4-sa"
}

variable "aks_admin_object_id" {
  description = "Entra object ID of the human who needs kubectl cluster-admin"
  type        = string
}