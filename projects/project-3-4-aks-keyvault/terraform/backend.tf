terraform {
  cloud {
    organization = "vvr-org"
    workspaces { 
        name = "project34-aks-keyvault" 
    }
  }
  required_providers {
    azurerm = { 
        source = "hashicorp/azurerm" 
        version = "~> 4.0" 
    }
  }
}