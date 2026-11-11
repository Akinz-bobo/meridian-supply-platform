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
LAYER ?= foundation
TF_DIR := infra/environments/$(ENV)/$(LAYER)
TF := terraform -chdir=$(TF_DIR)
TF_VARS := -var-file=../env.tfvars

# TARGET=emulator (the default) points Terraform at the local emulator.
# TARGET=aws leaves the provider on real AWS, using your own credentials.
TARGET ?= emulator
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

.PHONY: init
init: ## Initialise Terraform for ENV and LAYER against the remote state
	$(TF) init -input=false -reconfigure $(BACKEND)

.PHONY: plan
plan: init ## Show what would change for ENV and LAYER
	$(TF) plan -input=false $(TF_VARS)

.PHONY: apply
apply: init ## Apply ENV and LAYER
	$(TF) apply -input=false -auto-approve $(TF_VARS)

.PHONY: destroy
destroy: init ## Destroy ENV and LAYER
	$(TF) destroy -input=false -auto-approve $(TF_VARS)

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
	trivy config --config trivy.yaml infra

.PHONY: scan-all
scan-all: ## Scan and report every finding, including low severity, without failing
	trivy config --config trivy.yaml --severity LOW,MEDIUM,HIGH,CRITICAL --exit-code 0 infra

.PHONY: check
check: validate lint scan test ## Everything CI runs for infrastructure

.PHONY: test
test: ## Run the tests of every module that has them
	@./scripts/terraform-test-all.sh
