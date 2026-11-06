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

variable "model_router_routing_models" {
  type = list(object({
    format  = string
    name    = string
    version = string
  }))
  default = [
    { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
    { format = "OpenAI", name = "gpt-5.6-sol", version = "2026-07-09" },
    { format = "OpenAI", name = "gpt-5.6-terra", version = "2026-07-09" },
    { format = "Fireworks", name = "FW-Kimi-K3", version = "1" },
  ]
}

resource "azapi_resource" "model_router" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name      = "model-router"
  parent_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = 1000
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = "model-router"
        version = "2025-11-18"
      }
      versionUpgradeOption = "NoAutoUpgrade"
      routing = {
        mode   = "balanced"
        models = var.model_router_routing_models
      }
    }
  }

  ignore_missing_property = false
  list_unique_id_property = {
    "properties.routing.models" = "name,version"
  }
}

output "router_id" {
  value = azapi_resource.model_router.id
}
