terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "azurerm_cognitive_deployment" "model" {
  for_each = { model_router = true }

  name                   = "model-router"
  cognitive_account_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "OpenAI"
    name    = "model-router"
    version = "2025-11-18"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 100
  }
}

output "router_id" {
  value = azurerm_cognitive_deployment.model["model_router"].id
}
