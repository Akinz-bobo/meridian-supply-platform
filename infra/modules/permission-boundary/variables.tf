variable "name" {
  description = "Name of the boundary policy. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for the policy. Take them from the context module."
  type        = map(string)
}

variable "resource_prefix" {
  description = "Prefix that every named resource of the environment starts with, including the trailing hyphen, for example meridian-prod-."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)+-$", var.resource_prefix))
    error_message = "The resource prefix is <project>-<environment>- and ends with a hyphen, for example meridian-prod-. Without the hyphen, meridian-prod would also match meridian-production."
  }
}

variable "path_prefix" {
  description = "Path that every parameter, secret and log group of the environment lives under, including the trailing slash, for example /meridian/prod/."
  type        = string

  validation {
    condition     = can(regex("^/[a-z0-9]+(/[a-z0-9]+)+/$", var.path_prefix))
    error_message = "The path prefix is /<project>/<environment>/ and ends with a slash, for example /meridian/prod/."
  }
}

variable "account_id" {
  description = "Account the boundary is for. Resources in any other account are outside it."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "region" {
  description = "Region the environment is deployed to. Requests to any other region are denied."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "Give a region name, for example eu-west-1."
  }
}
