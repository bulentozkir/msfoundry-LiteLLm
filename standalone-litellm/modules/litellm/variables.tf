terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

variable "settings" {
  description = "Self-contained Azure deployment. No model account, Front Door, existing subnet or shared state is required."
  type = object({
    name                    = string
    location                = string
    image                   = string
    allowed_ingress_cidrs   = list(string)
    resource_group_name     = optional(string)
    private_ingress         = optional(bool, false)
    vnet_cidr               = optional(string, "10.80.0.0/16")
    cpu                     = optional(number, 2)
    memory                  = optional(string, "4Gi")
    min_replicas            = optional(number, 1)
    max_replicas            = optional(number, 3)
    http_concurrency        = optional(number, 25)
    revision_suffix         = optional(string)
    traffic_weights         = optional(map(number), {})
    public_base_url         = optional(string)
    ui_username             = optional(string, "aiadmin")
    postgres_sku            = optional(string, "B_Standard_B1ms")
    postgres_storage_mb     = optional(number, 32768)
    postgres_backup_days    = optional(number, 7)
    postgres_ha_mode        = optional(string)
    redis_sku               = optional(string, "Balanced_B0")
    redis_high_availability = optional(bool, false)
    disable_schema_update   = optional(bool, false)
    database_pool_limit     = optional(number, 5)
    provider_environment    = optional(map(string), {})
    model_list              = optional(any, [])
    tags                    = optional(map(string), {})
  })

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,17}[a-z0-9]$", var.settings.name)) && !strcontains(var.settings.name, "--")
    error_message = "name must be 3-19 lowercase letters/digits/hyphens, start with a letter, end alphanumeric, and contain no double hyphens."
  }
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.settings.image)) || can(regex(":v[0-9]+\\.[0-9]+\\.[0-9]+[^/]*$", var.settings.image))
    error_message = "Pin an existing versioned vX.Y.Z release image or sha256 digest; moving main-stable/latest tags are not accepted."
  }
  validation {
    condition = length(var.settings.allowed_ingress_cidrs) > 0 && alltrue([
      for cidr in var.settings.allowed_ingress_cidrs : can(cidrnetmask(cidr)) && !endswith(cidr, "/0")
    ])
    error_message = "Supply at least one trusted IPv4 CIDR (for example your corporate egress /32); /0 is not allowed."
  }
  validation {
    condition     = can(cidrsubnet(var.settings.vnet_cidr, 8, 3)) && can(cidrnetmask(var.settings.vnet_cidr)) && endswith(var.settings.vnet_cidr, "/16")
    error_message = "vnet_cidr must be an IPv4 /16. The module allocates /23 ACA, /24 PostgreSQL and /27 private-endpoint subnets."
  }
  validation {
    condition = contains(["0.5:1Gi", "1:2Gi", "1.5:3Gi", "2:4Gi"], "${var.settings.cpu}:${var.settings.memory}") && (
      var.settings.min_replicas >= 1 && var.settings.max_replicas >= var.settings.min_replicas &&
      floor(var.settings.min_replicas) == var.settings.min_replicas && floor(var.settings.max_replicas) == var.settings.max_replicas
    )
    error_message = "Use a supported Consumption CPU/memory pair and integer replica limits with max >= min >= 1."
  }
  validation {
    condition = length(var.settings.traffic_weights) == 0 || (
      sum(values(var.settings.traffic_weights)) == 100 && alltrue([
        for revision, weight in var.settings.traffic_weights : revision != "latest" && weight >= 0 && weight <= 100 && floor(weight) == weight
      ])
    )
    error_message = "traffic_weights must be empty for bootstrap or explicit revision names with integer weights totaling 100; 'latest' is forbidden during rollout."
  }
  validation {
    condition     = var.settings.postgres_ha_mode == null ? true : contains(["SameZone", "ZoneRedundant"], var.settings.postgres_ha_mode)
    error_message = "postgres_ha_mode must be null, SameZone or ZoneRedundant; choose an HA-compatible PostgreSQL SKU and region."
  }
  validation {
    condition     = var.settings.postgres_backup_days >= 7 && var.settings.postgres_backup_days <= 35 && floor(var.settings.postgres_backup_days) == var.settings.postgres_backup_days
    error_message = "postgres_backup_days must be an integer between 7 and 35 for native Azure PostgreSQL backups."
  }
  validation {
    condition     = var.settings.public_base_url == null ? true : can(regex("^https://[^/]+$", var.settings.public_base_url))
    error_message = "public_base_url must be an HTTPS origin with no trailing slash/path."
  }
  validation {
    condition     = can([for model in var.settings.model_list : model.model_name]) && alltrue([for model in var.settings.model_list : can(model.litellm_params.model)])
    error_message = "model_list must be a list of LiteLLM entries with model_name and litellm_params.model. Use os.environ references for credentials."
  }
}

variable "provider_secrets" {
  description = "Provider-specific secret environment variables. Keys are nonsecret names; values are stored in sensitive Terraform state and ACA secrets."
  type        = map(string)
  sensitive   = true
  default     = {}
}