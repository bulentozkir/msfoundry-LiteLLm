variable "subscription_id" {
  description = "Azure subscription that receives the isolated APIM AI Gateway deployment."
  type        = string
  default     = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "tenant_id" {
  description = "Microsoft Entra tenant for the target subscription."
  type        = string
  default     = "16b3c013-d300-468d-ac64-7eda0820b6d3"
}

variable "location" {
  description = "Azure region for the APIM AI Gateway preview architecture."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = lower(var.location) == "swedencentral"
    error_message = "This deployment is intentionally pinned to Sweden Central."
  }
}

variable "resource_group_name" {
  description = "Resource group for only the APIM AI Gateway and Foundry resources."
  type        = string
  default     = "rg-foundry-aigateway-sweden"
}

variable "publisher_name" {
  description = "Publisher name required by the API Management resource."
  type        = string
  default     = "AI Platform Team"
}

variable "publisher_email" {
  description = "Publisher email required by the API Management resource."
  type        = string
  default     = "bulento@microsoft.com"
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default = {
    architecture = "apim-ai-gateway-foundry"
    environment  = "test"
    managed_by   = "terraform"
  }
}
