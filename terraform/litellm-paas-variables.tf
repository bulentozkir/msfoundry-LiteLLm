# ---------------------------------------------------------------------------
# Optional LiteLLM support resources in this shared stack.
#
# The LiteLLM runtime is external to this root (for example standalone-litellm).
# These settings create private PaaS cache resources that external LiteLLM can
# consume when network connectivity is available.
# ---------------------------------------------------------------------------

variable "litellm_enable_paas_cache" {
  description = "Create dedicated PaaS cache resources for LiteLLM in this shared stack."
  type        = bool
  default     = true
}

variable "litellm_redis_sku" {
  description = "Azure Managed Redis SKU for LiteLLM cache support. Balanced_B0 is the minimum-cost SKU."
  type        = string
  default     = "Balanced_B0"
}

variable "litellm_redis_high_availability" {
  description = "Enable zone-aware high availability for the LiteLLM Redis cache."
  type        = bool
  default     = false
}
