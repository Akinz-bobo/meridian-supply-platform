# Developer entry points. Run `make help` for the list.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

export FLOCI_PORT ?= 4566
export AWS_ENDPOINT_URL ?= http://localhost:$(FLOCI_PORT)
export AWS_DEFAULT_REGION ?= eu-west-1
# The emulator accepts any non-empty credentials. These are not secrets.
export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: doctor
doctor: ## Check that the required tools are installed
	@./scripts/doctor.sh

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
