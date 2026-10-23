terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
  }
}

variable "subscription_id" {
  type    = string
  default = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "location" {
  type    = string
  default = "swedencentral"
}

variable "name_suffix" {
  type    = string
  default = "8ps1sz"
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"

  features {}
}

data "azurerm_client_config" "operator" {}

locals {
  tags = {
    purpose = "customer-model-token-usage"
    source  = "imported-csv-examples"
  }
}

resource "azurerm_resource_group" "observability" {
  name     = "rg-law"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "tokens" {
  name                         = "law-customer-tokens-${var.name_suffix}"
  location                     = azurerm_resource_group.observability.location
  resource_group_name          = azurerm_resource_group.observability.name
  sku                          = "PerGB2018"
  retention_in_days            = 30
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_application_insights" "csv_import" {
  name                         = "appi-token-import-${var.name_suffix}"
  location                     = azurerm_resource_group.observability.location
  resource_group_name          = azurerm_resource_group.observability.name
  application_type             = "other"
  workspace_id                 = azurerm_log_analytics_workspace.tokens.id
  retention_in_days            = 30
  sampling_percentage          = 100
  local_authentication_enabled = false
  internet_ingestion_enabled   = true
  internet_query_enabled       = true
  tags                         = local.tags
}

resource "azurerm_dashboard_grafana" "tokens" {
  name                              = "amg-tokens-${var.name_suffix}"
  location                          = azurerm_resource_group.observability.location
  resource_group_name               = azurerm_resource_group.observability.name
  grafana_major_version             = "12"
  sku                               = "Standard"
  sku_size                          = "X1"
  api_key_enabled                   = false
  public_network_access_enabled     = true
  deterministic_outbound_ip_enabled = false
  zone_redundancy_enabled           = false
  tags                              = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "grafana_logs" {
  scope                = azurerm_log_analytics_workspace.tokens.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_dashboard_grafana.tokens.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_grafana" {
  scope                = azurerm_dashboard_grafana.tokens.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.operator.object_id
}

resource "azurerm_role_assignment" "operator_ingestion" {
  scope                = azurerm_application_insights.csv_import.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = data.azurerm_client_config.operator.object_id
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.tokens.workspace_id
}

output "workspace_resource_id" {
  value = azurerm_log_analytics_workspace.tokens.id
}

output "application_insights_resource_id" {
  value = azurerm_application_insights.csv_import.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.csv_import.connection_string
  sensitive = true
}

output "grafana_endpoint" {
  value = azurerm_dashboard_grafana.tokens.endpoint
}

output "grafana_resource_id" {
  value = azurerm_dashboard_grafana.tokens.id
}
