variable "name" {
  description = "Prefix of the three groups. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "vpc_id" {
  description = "Identifier of the VPC the groups belong to."
  type        = string
}

variable "vpc_cidr_block" {
  description = "Address range of the VPC, used for the DNS rule."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid address range, for example 10.30.0.0/16."
  }
}

variable "load_balancer_ports" {
  description = "Listener ports the load balancer group accepts from clients."
  type        = set(number)
  default     = [443]

  validation {
    condition     = length(setsubtract(var.load_balancer_ports, [80, 443])) == 0
    error_message = "A load balancer listens on 443, and on 80 only to redirect to 443. No other port may be opened to clients."
  }

  validation {
    condition     = contains(var.load_balancer_ports, 443)
    error_message = "Port 443 must be among the listener ports. Port 80 alone would serve plain HTTP."
  }
}

variable "load_balancer_ingress_cidrs" {
  description = "Address ranges allowed to reach the load balancers. The default is the internet. An internal platform passes its office or VPN ranges."
  type        = set(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.load_balancer_ingress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every entry must be a valid address range."
  }

  validation {
    condition     = length(var.load_balancer_ingress_cidrs) > 0
    error_message = "Give at least one address range, or nothing can reach the load balancers."
  }
}

variable "app_ports" {
  description = "Ports workloads listen on for traffic from load balancers."
  type        = set(number)
  default     = [8080]

  validation {
    condition     = alltrue([for port in var.app_ports : port >= 1024 && port <= 65535])
    error_message = "Workloads run without root and listen on ports from 1024 to 65535."
  }
}

variable "data_ports" {
  description = "Ports of the data stores, keyed by what listens there. The key appears in rule descriptions."
  type        = map(number)
  default = {
    postgresql = 5432
    redis      = 6379
  }

  validation {
    condition     = alltrue([for port in values(var.data_ports) : port >= 1 && port <= 65535])
    error_message = "Every data port must be between 1 and 65535."
  }
}
