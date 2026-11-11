#!/usr/bin/env bash
# Creates the skeleton of a new Terraform module that meets the standards in
# docs/architecture/module-standards.md.
#
# Usage: new-module.sh <name>      (kebab case, for example: sqs-consumer-queue)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="${1:-}"

if ! [[ "$name" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
  echo 'Usage: new-module.sh <name>   The name must be kebab case, for example: sqs-consumer-queue' >&2
  exit 1
fi

dir="$root/infra/modules/$name"
if [ -e "$dir" ]; then
  echo "infra/modules/$name already exists." >&2
  exit 1
fi

snake="${name//-/_}"
mkdir -p "$dir/tests" "$dir/examples/basic"

cat >"$dir/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
EOF

cat >"$dir/main.tf" <<'EOF'
# One sentence saying what this module creates.
#
# Notes for someone reading the code: why it is built this way. What a
# caller needs to know belongs in README.md, above the generated section.
EOF

cat >"$dir/variables.tf" <<'EOF'
variable "name" {
  description = "Name of the resource. Take it from the context module's prefix."
  type        = string
}

variable "tags" {
  description = "Tags for every resource in the module. Take them from the context module."
  type        = map(string)
}
EOF

cat >"$dir/outputs.tf" <<'EOF'
# Every output needs a description. Output what another module or layer
# needs in order to use this one: identifiers, ARNs, names, endpoints.
EOF

cat >"$dir/tests/$snake.tftest.hcl" <<'EOF'
# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed. Assert every protection the module promises, and every input
# validation, so that removing one fails a test.

mock_provider "aws" {}

variables {
  name = "meridian-prod-example"
  tags = {
    Project = "meridian"
  }
}

# run "describes_one_behaviour_the_module_guarantees" {
#   command = plan
#
#   assert {
#     condition     = true
#     error_message = "Say what was expected and what was found."
#   }
# }
EOF

cat >"$dir/examples/basic/main.tf" <<EOF
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "example"
}

module "$snake" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags
}
EOF

cat >"$dir/README.md" <<EOF
# $name

TODO: say in one sentence what this module creates.

Then say what a caller needs to know: what is on by default, what cannot be
turned off, and which decision record or guide explains why.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
EOF

echo "Created infra/modules/$name. Next:"
echo "  1. Describe the module in the comment at the top of main.tf, then add resources."
echo "  2. Write tests in tests/$snake.tftest.hcl."
echo "  3. make docs && make check"
