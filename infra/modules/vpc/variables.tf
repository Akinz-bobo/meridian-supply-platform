variable "name" {
  description = "Name of the VPC, and the prefix of everything in it. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "cidr_block" {
  description = "Address range of the VPC. Must be a /16 so the fixed address plan fits."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "The VPC range must be a valid /16, for example 10.30.0.0/16. The address plan in docs/architecture/environments.md depends on it."
  }

  validation {
    condition     = can(regex("^10\\.", var.cidr_block))
    error_message = "The VPC range must be inside 10.0.0.0/8, the private range the address plan allocates from."
  }
}

variable "availability_zones" {
  description = "Zones to spread the subnets across, in address plan order. The first zone holds the NAT gateway when only one is used."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "Use two or three zones. One zone is not highly available and the address plan has room for three."
  }

  validation {
    condition     = length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Each availability zone may be listed only once."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all zones instead of one per zone. Cheaper, and an outage of that zone cuts outbound internet access for every private subnet."
  type        = bool
  default     = false
}

variable "public_subnet_tags" {
  description = "Extra tags for public subnets, for example the tag a load balancer controller uses to discover them."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets, for example the tag a load balancer controller uses to discover them."
  type        = map(string)
  default     = {}
}
