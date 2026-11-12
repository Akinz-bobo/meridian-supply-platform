variable "name" {
  description = "Name of the role, for example meridian-prod-catalog-task-role. Build it from the context module's prefix."
  type        = string

  validation {
    condition     = length(var.name) <= 64
    error_message = "An IAM role name is at most 64 characters."
  }
}

variable "tags" {
  description = "Tags for the role. Take them from the context module."
  type        = map(string)
}

variable "description" {
  description = "What runs as this role, in one sentence."
  type        = string

  validation {
    condition     = length(var.description) >= 10
    error_message = "Describe what runs as this role in at least a few words."
  }
}

variable "workload" {
  description = "Where the workload runs: ecs-task, lambda, eks-pod, ec2, step-functions, scheduler or firehose. Decides who may assume the role."
  type        = string

  validation {
    condition     = contains(["ecs-task", "lambda", "eks-pod", "ec2", "step-functions", "scheduler", "firehose"], var.workload)
    error_message = "workload must be one of: ecs-task, lambda, eks-pod, ec2, step-functions, scheduler, firehose."
  }
}

variable "account_id" {
  description = "Account the workload runs in. Where the service supports it, the role can be assumed only on behalf of this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "An AWS account id is 12 digits."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the environment's permission boundary. Required: a workload role without a boundary is not allowed."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/.+", var.permissions_boundary_arn))
    error_message = "Give the ARN of an IAM policy, for example arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary."
  }
}

variable "policies" {
  description = "Inline policies for the role, as JSON documents keyed by a short name that says what each allows."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for name in keys(var.policies) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "Policy names are lower case words separated by hyphens, for example read-own-secrets."
  }
}

variable "managed_policy_arns" {
  description = "Managed policies to attach. Prefer inline policies written for the workload. AWS managed policies are usually wider than needed."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.managed_policy_arns : !endswith(arn, "/AdministratorAccess") && !endswith(arn, "/PowerUserAccess") && !endswith(arn, "FullAccess")])
    error_message = "AdministratorAccess, PowerUserAccess and the FullAccess policies may not be attached to a workload role."
  }
}
