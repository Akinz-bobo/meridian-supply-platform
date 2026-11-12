# Developer entry points. Run `make help` for the list.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

export FLOCI_PORT ?= 4566
export AWS_ENDPOINT_URL ?= http://localhost:$(FLOCI_PORT)
export AWS_DEFAULT_REGION ?= eu-west-1
# The emulator accepts any non-empty credentials. These are not secrets.
export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test

# Which environment and state layer the Terraform targets act on.
ENV ?= dev
ENVS ?= dev staging production
LAYER ?= foundation
TF_DIR := infra/environments/$(ENV)/$(LAYER)
TF := terraform -chdir=$(TF_DIR)
TF_VARS := -var-file=../env.tfvars

# TARGET=emulator (the default) points Terraform at the local emulator.
# TARGET=aws leaves the provider on real AWS, using your own credentials.
export TARGET ?= emulator
SHARED := infra/environments/_shared
BACKEND := -backend-config=$(CURDIR)/$(SHARED)/backend.hcl \
	-backend-config=key=$(ENV)/$(LAYER)/terraform.tfstate
ifeq ($(TARGET),emulator)
export TF_VAR_aws_endpoint_url := $(AWS_ENDPOINT_URL)
BACKEND += -backend-config=$(CURDIR)/$(SHARED)/backend.emulator.hcl \
	-backend-config='endpoints={s3="$(AWS_ENDPOINT_URL)"}'
endif

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: doctor
doctor: ## Check that the required tools are installed
	@./scripts/doctor.sh

.PHONY: tools
tools: ## Install the pinned analysis tools into ~/.local/bin
	@./scripts/install-tools.sh

.PHONY: up
up: ## Start the AWS emulator and wait until it is healthy
	docker compose up --detach
	@./scripts/wait-for-emulator.sh

.PHONY: down
down: ## Stop the emulator and remove everything it created
	docker compose down --volumes --remove-orphans
	@# Containers the emulator started for RDS, ECS, EKS and EC2 are its children, not compose's.
	@docker ps --all --quiet --filter 'name=^floci-aws-' | xargs --no-run-if-empty docker rm --force >/dev/null
	@echo 'Emulator stopped and cleaned up.'

.PHONY: status
status: ## Show whether the emulator is running and which services answer
	@curl --fail --silent --max-time 3 $(AWS_ENDPOINT_URL)/_floci/health \
	  | jq -r '"Floci \(.version) at $(AWS_ENDPOINT_URL): \(.services | to_entries | map(select(.value == "running")) | length) services running"' \
	  || { echo 'The emulator is not running. Start it with: make up'; exit 1; }

.PHONY: logs
logs: ## Follow the emulator logs
	docker compose logs --follow floci

.PHONY: bootstrap
bootstrap: ## Create the remote state bucket (once, before the first apply)
	terraform -chdir=infra/bootstrap init -input=false
	terraform -chdir=infra/bootstrap apply -input=false -auto-approve -var-file=bootstrap.tfvars

# Extra arguments for plan, apply and destroy, placed after the variable
# file so that a -var given here wins over the file. An environment
# variable such as TF_VAR_disposable would not: a value in env.tfvars
# takes precedence over it. Used by `make teardown`.
TF_EXTRA_VARS ?=

.PHONY: init
init: ## Initialise Terraform for ENV and LAYER against the remote state
	$(TF) init -input=false -reconfigure $(BACKEND)

.PHONY: plan
plan: init ## Show what would change for ENV and LAYER
	$(TF) plan -input=false $(TF_VARS) $(TF_EXTRA_VARS)

.PHONY: apply
apply: init ## Apply ENV and LAYER
	$(TF) apply -input=false -auto-approve $(TF_VARS) $(TF_EXTRA_VARS)

.PHONY: destroy
destroy: init ## Destroy ENV and LAYER
	$(TF) destroy -input=false -auto-approve $(TF_VARS) $(TF_EXTRA_VARS)

.PHONY: apply-all
apply-all: ## Apply every layer of ENV, in dependency order
	@./scripts/each-layer.sh apply $(ENV)

.PHONY: destroy-all
destroy-all: ## Destroy every layer of ENV, in reverse order
	@./scripts/each-layer.sh destroy $(ENV)

# Protections against data loss (deletion protection, final snapshots,
# refusing to empty a bucket) make destroy-all fail outside dev, which is
# their job. Decommissioning is therefore two deliberate steps: apply with
# the protections lifted, then destroy.
.PHONY: teardown
teardown: ## Lift ENV's deletion protections, then destroy every layer. For rehearsals and for decommissioning
	@echo "Lifting deletion protections in $(ENV), then destroying it."
	@TF_EXTRA_VARS='-var disposable=true' ./scripts/each-layer.sh apply $(ENV)
	@TF_EXTRA_VARS='-var disposable=true' ./scripts/each-layer.sh destroy $(ENV)

.PHONY: report
report: ## Plan every layer of ENVS, check policies and write plan-report.md
	@./scripts/plan-report.sh plan-report.md $(ENVS)

.PHONY: smoke
smoke: ## Check that the applied ENV looks right, by asking the AWS API
	@./scripts/smoke-test.sh $(ENV)

.PHONY: data-check
data-check: ## Use the stores of ENV the way a service would: key design, SQL, cache access rule, a backup
	@./scripts/data-model-check.sh $(ENV)
	@./scripts/database-check.sh $(ENV)
	@./scripts/cache-acl-check.sh $(ENV)
	@./scripts/backup-check.sh $(ENV)

.PHONY: event-check
event-check: ## Send events through ENV and follow them: fan-out, dead-letter, redrive, alarms, notifications, stream order
	@./scripts/event-check.sh $(ENV)

SERVICE ?= sample

.PHONY: image
image: ## Build SERVICE and push its image to the repository of ENV. Prints the image reference
	@./scripts/push-image.sh $(ENV) $(SERVICE)

.PHONY: service-test
service-test: ## Run the unit tests of every service
	@for service in services/*/; do \
	  echo "== $$service"; \
	  python3 -m unittest discover --start-directory "$$service/tests" --pattern 'test_*.py' || exit 1; \
	done

.PHONY: state-audit
state-audit: ## Fail if the remote state of ENV holds a secret value
	@./scripts/state-audit.sh $(ENV)

.PHONY: fmt
fmt: ## Format every Terraform file
	terraform fmt -recursive infra

.PHONY: validate
validate: ## Check formatting and validate every layer and module
	terraform fmt -recursive -check infra
	@./scripts/terraform-validate-all.sh

.PHONY: lint
lint: ## Lint every layer and module with tflint
	@./scripts/terraform-lint-all.sh

.PHONY: scan
scan: ## Scan the Terraform for security misconfigurations (medium and above)
	@./scripts/terraform-scan.sh

.PHONY: scan-all
scan-all: ## Scan and report every finding, including low severity, without failing
	@./scripts/terraform-scan.sh --severity LOW,MEDIUM,HIGH,CRITICAL --exit-code 0

# Uses a shellcheck on the PATH when there is one. Otherwise it runs the
# linter from its container image, so nothing needs to be installed.
.PHONY: shellcheck
shellcheck: ## Lint the shell scripts, as CI does
	@if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh; \
	else docker run --rm --volume "$(CURDIR):/mnt:ro" --workdir /mnt koalaman/shellcheck:v0.10.0 scripts/*.sh; fi
	@echo 'Shell scripts are clean.'

.PHONY: contract-test
contract-test: ## Test the event contracts and their validator
	@python3 -m unittest discover --start-directory scripts/tests --pattern 'test_*.py'

.PHONY: policy-test
policy-test: ## Run the tests of the policies themselves
	conftest fmt --check infra/policies
	conftest verify --policy infra/policies --data infra/policies/data

.PHONY: policy
policy: init ## Plan ENV and LAYER and check the plan against the policies
	@./scripts/terraform-policy.sh $(TF_DIR) $(TF_VARS)

.PHONY: docs
docs: ## Generate the README of every module from its code
	@./scripts/terraform-docs.sh

.PHONY: docs-check
docs-check: ## Fail if a module README is out of date
	@./scripts/terraform-docs.sh --check

.PHONY: module
module: ## Create the skeleton of a new module: make module NAME=sqs-consumer-queue
	@./scripts/new-module.sh $(NAME)

.PHONY: check
check: validate lint scan test policy-test contract-test docs-check ## Every infrastructure check that needs no emulator

.PHONY: test
test: ## Run the plan tests of every module. Needs nothing running
	@./scripts/terraform-test-all.sh

.PHONY: test-emulator
test-emulator: ## Run the apply tests of every module against the emulator
	@./scripts/terraform-test-all.sh --emulator
