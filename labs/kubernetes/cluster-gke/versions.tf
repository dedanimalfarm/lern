# Версии Terraform и провайдера.
# Провайдер google 6.x — актуальная линейка (поддерживает deletion_protection,
# VPC-native по умолчанию, spot-ноды). Pin по minor во избежание сюрпризов.
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
