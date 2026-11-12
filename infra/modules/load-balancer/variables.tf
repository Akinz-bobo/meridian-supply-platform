variable "name" {
  description = "Name of the load balancer. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 32
    error_message = "A load balancer name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 32 characters."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "subnet_ids" {
  description = "Subnets the load balancer is placed in, one per zone. Pass the public subnets for an internet-facing load balancer."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A load balancer needs subnets in at least two zones."
  }
}

variable "security_group_ids" {
  description = "Security groups of the load balancer. Pass the load balancer security group."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Attach at least one security group."
  }
}

variable "certificate_arn" {
  description = "ARN of the certificate the TLS listener presents."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "Give the ARN of an ACM certificate. The load balancer has no listener without TLS."
  }
}

variable "internal" {
  description = "Give the load balancer private addresses only, for traffic from inside the VPC or a connected network."
  type        = bool
  default     = false
}

variable "tls_policy" {
  description = "Security policy of the TLS listener. The default accepts TLS 1.3 and TLS 1.2 with forward secrecy only."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = startswith(var.tls_policy, "ELBSecurityPolicy-TLS13-")
    error_message = "Use a policy from the ELBSecurityPolicy-TLS13 family. Older policies accept TLS 1.0 or 1.1."
  }
}

variable "redirect_http" {
  description = "Also listen on port 80, only to redirect to 443. The load balancer security group must then allow port 80."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Refuse to delete the load balancer. Turn off only in an environment that is disposable."
  type        = bool
  default     = true
}

variable "idle_timeout_seconds" {
  description = "Seconds a connection may be idle before the load balancer closes it. Keep it below the keep-alive timeout of the services behind."
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout_seconds >= 1 && var.idle_timeout_seconds <= 4000
    error_message = "idle_timeout_seconds must be between 1 and 4000."
  }
}
