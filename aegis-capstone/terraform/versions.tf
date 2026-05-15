terraform {
  required_version = ">= 1.5"

  backend "azurerm" {
    resource_group_name  = "aegis-tfstate-rg"
    storage_account_name = "aegistfstate52018f"
    container_name       = "tfstate"
    key                  = "aegis-v4.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
