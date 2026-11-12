variable "name" {
  description = "Prefix for the endpoints and their security group. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "vpc_id" {
  description = "Identifier of the VPC the endpoints belong to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "Address range of the VPC. Interface endpoints accept HTTPS from this range only."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid address range, for example 10.30.0.0/16."
  }
}

variable "account_id" {
  description = "Account the VPC is in. Endpoint policies admit this account's principals, and gateway endpoints reach this account's resources only."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "route_table_ids" {
  description = "Route tables that get routes to the gateway endpoints. Pass the private route tables."
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnets that get a network interface for each interface endpoint, one per zone. Pass the private subnets."
  type        = list(string)
}

variable "gateway_services" {
  description = "Services reached through a gateway endpoint. Only S3 and DynamoDB offer one."
  type        = set(string)
  default     = ["s3", "dynamodb"]

  validation {
    condition     = length(setsubtract(var.gateway_services, ["s3", "dynamodb"])) == 0
    error_message = "Only s3 and dynamodb have gateway endpoints. Put other services in interface_services."
  }
}

variable "interface_services" {
  description = "Services reached through an interface endpoint, by the last part of the service name, for example ecr.api. Each one is billed per zone per hour."
  type        = set(string)
  nullable    = false
  default = [
    "ecr.api",
    "ecr.dkr",
    "kms",
    "logs",
    "secretsmanager",
    "sqs",
    "ssm",
    "sts",
  ]

  validation {
    condition     = length(setintersection(var.interface_services, ["s3", "dynamodb"])) == 0
    error_message = "s3 and dynamodb use gateway endpoints, which are free. Put them in gateway_services."
  }

  validation {
    condition     = alltrue([for service in var.interface_services : can(regex("^[a-z0-9]+([.-][a-z0-9]+)*$", service))])
    error_message = "Give each service as the last part of its endpoint service name, in lower case, for example ecr.api or secretsmanager."
  }
}
