variable "project" {
  description = "Short name of the platform. First part of every resource name."
  type        = string
  default     = "meridian"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.project))
    error_message = "The project must be 2 to 16 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment the resources belong to. `shared` is the shared-services account."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod", "shared"], var.environment)
    error_message = "The environment must be one of: dev, stg, prod, shared."
  }
}

variable "component" {
  description = "Service or building block that owns the resources, in kebab case. For example: network, inventory."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.component)) && length(var.component) <= 24
    error_message = "The component must be kebab case (lower-case letters, digits and single hyphens) and at most 24 characters."
  }
}

variable "owner" {
  description = "Team responsible for the resources."
  type        = string
  default     = "platform"
}

variable "cost_centre" {
  description = "Cost allocation label."
  type        = string
  default     = "supply-chain"
}

variable "repository" {
  description = "Repository that defines the resources."
  type        = string
  default     = "Akinz-bobo/meridian-supply-platform"
}

variable "extra_tags" {
  description = "Additional tags. They cannot override the standard tags."
  type        = map(string)
  default     = {}
}
