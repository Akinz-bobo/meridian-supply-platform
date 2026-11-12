variable "name" {
  description = "Name of the service, and of its task definition, security group and target group. Take it from the context module's prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 32
    error_message = "A service name starts with a letter, uses lower case letters, digits and single hyphens, and is at most 32 characters, which is the limit for a target group."
  }
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster the service runs in."
  type        = string
}

variable "cluster_name" {
  description = "Name of the same cluster. Autoscaling addresses a service by cluster name."
  type        = string
}

variable "vpc_id" {
  description = "Identifier of the VPC."
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

variable "subnet_ids" {
  description = "Subnets the tasks run in. Pass the private subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Give subnets in at least two zones, so that losing a zone does not stop the service."
  }
}

variable "image" {
  description = "Image to run, with its tag or digest. Never latest: a tag must identify one build."
  type        = string

  validation {
    condition     = can(regex("(:[^:/]+|@sha256:[0-9a-f]{64})$", var.image)) && !endswith(var.image, ":latest")
    error_message = "Give the image with an exact tag or a digest. latest is refused, and so is an image with no tag."
  }
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1024 && var.container_port <= 65535
    error_message = "A container that does not run as root listens on a port from 1024 to 65535."
  }
}

variable "container_user" {
  description = "User the container runs as, as uid:gid. It must not be root."
  type        = string
  default     = "10001:10001"

  validation {
    condition     = can(regex("^[1-9][0-9]*(:[0-9]+)?$", var.container_user))
    error_message = "Give a numeric user other than 0, for example 10001:10001. The container may not run as root."
  }
}

variable "cpu" {
  description = "CPU units for the task. 1024 is one vCPU."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a size Fargate offers: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Memory for the task, in MiB."
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "cpu_architecture" {
  description = "Processor architecture the image was built for: X86_64 or ARM64."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "execution_role_arn" {
  description = "ARN of the role ECS uses to start the task: pull the image, write logs, fetch secrets. Create it with the workload-role module."
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the role the application runs as. Create it with the workload-role module."
  type        = string
}

variable "environment" {
  description = "Environment variables that are not secret. Anyone who can describe the task definition can read them."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for name in keys(var.environment) : !can(regex("(?i)password|secret|token|api_?key|private_?key|credential", name))])
    error_message = "A variable name suggests a secret. Pass it in secrets, by reference, so the value never appears in the task definition."
  }
}

variable "secrets" {
  description = "Secrets and parameters injected as environment variables, by reference: variable name to the ARN of a Secrets Manager secret or Parameter Store parameter. ECS fetches the value when the task starts."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for reference in values(var.secrets) : can(regex("^arn:aws[a-z-]*:(secretsmanager|ssm):", reference))])
    error_message = "Each secret is the ARN of a Secrets Manager secret or a Parameter Store parameter, never a value."
  }
}

variable "listener_arn" {
  description = "ARN of the load balancer's TLS listener. The service adds its rule to it."
  type        = string
}

variable "listener_rule_priority" {
  description = "Order in which the listener evaluates this service's rule. Lower runs first. Each service needs a different number."
  type        = number

  validation {
    condition     = var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000
    error_message = "listener_rule_priority must be between 1 and 50000."
  }
}

variable "path_patterns" {
  description = "Paths routed to the service, for example /catalog and /catalog/*."
  type        = list(string)

  validation {
    condition     = length(var.path_patterns) >= 1 && length(var.path_patterns) <= 5
    error_message = "Give between one and five path patterns."
  }

  validation {
    condition     = alltrue([for pattern in var.path_patterns : startswith(pattern, "/") && pattern != "/" && pattern != "/*"])
    error_message = "A path pattern starts with a slash and names the service's own prefix. / and /* would take every request."
  }
}

variable "health_check_path" {
  description = "Path the load balancer calls to decide whether a task is healthy. It must answer 200 quickly and do no work."
  type        = string

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path starts with a slash."
  }
}

variable "load_balancer_security_group_id" {
  description = "Security group of the load balancer. The service accepts traffic from it, and a rule is added to it so that it may send to the service."
  type        = string
}

variable "data_access" {
  description = "Data stores the service may reach, keyed by what the store is: its security group and port. A rule pair is created for each. A service that lists none can reach no store."
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}
}

variable "desired_count" {
  description = "Tasks to run, and the fewest that autoscaling keeps."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "max_count" {
  description = "The most tasks autoscaling may run. A ceiling on cost as well as on capacity."
  type        = number
  default     = 6

  validation {
    condition     = var.max_count >= 1 && var.max_count <= 100
    error_message = "max_count must be between 1 and 100."
  }

  validation {
    condition     = var.max_count >= var.desired_count
    error_message = "max_count must not be lower than desired_count."
  }
}

variable "cpu_target_percent" {
  description = "Average CPU use that autoscaling aims for. Lower leaves more headroom and costs more."
  type        = number
  default     = 60

  validation {
    condition     = var.cpu_target_percent >= 20 && var.cpu_target_percent <= 90
    error_message = "cpu_target_percent must be between 20 and 90."
  }
}

variable "stop_timeout_seconds" {
  description = "Seconds a container gets to finish requests in flight after SIGTERM, before it is killed."
  type        = number
  default     = 30

  validation {
    condition     = var.stop_timeout_seconds >= 5 && var.stop_timeout_seconds <= 120
    error_message = "stop_timeout_seconds must be between 5 and 120, which is the most Fargate allows."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Seconds a new task may fail health checks while it starts, before it is replaced."
  type        = number
  default     = 30
}

variable "enable_execute_command" {
  description = "Allow a shell to be opened in a running container. Leave off, and turn on for an incident. Sessions are recorded by the cluster."
  type        = bool
  default     = false
}

variable "log_group_name" {
  description = "Name of the service's log group, a path under /<project>/<environment>/."
  type        = string

  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "Log group names in this platform are paths and start with a slash."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the key that encrypts the service's log group. Pass the logs key."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.logs_kms_key_arn))
    error_message = "Give the ARN of a KMS key."
  }
}

variable "log_retention_days" {
  description = "How long the service's logs are kept."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731], var.log_retention_days)
    error_message = "Retention must be a value CloudWatch accepts and at least 30 days: 30, 60, 90, 120, 150, 180, 365, 400, 545 or 731."
  }
}
