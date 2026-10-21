SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

TF ?= terraform
# Match the Lambda runtime; fall back to python3 (e.g. on CI, where setup-python provides 3.14).
PYTHON ?= $(shell command -v python3.14 || echo python3)
SERVICE ?= length
# Run Lambdas natively: arm64 on Apple Silicon/ARM Linux, x86_64 elsewhere (e.g. GitHub runners).
LAMBDA_ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,x86_64)
LOCAL_TF = TF_VAR_architecture=$(LAMBDA_ARCH) AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_SESSION_TOKEN= AWS_PROFILE= AWS_DEFAULT_PROFILE= AWS_EC2_METADATA_DISABLED=true $(TF) -chdir=infra/local
MODULE_TF = $(TF) -chdir=infra/modules/lambda-service

.PHONY: help up down init test fmt fmt-check validate check deploy plan urls smoke logs destroy

help:
	@printf '%s\n' 'Local only: make up → make deploy → make smoke → make destroy → make down' 'Checks: make test (Python), make check (Python + Terraform, no AWS credentials)' 'Inspect: make urls, make plan, make logs SERVICE=length|json-validator' 'Real AWS is deliberately not a Make target; see docs/aws.md.'

up:
	docker compose up -d --wait --wait-timeout 180

down:
	docker compose down

init:
	$(LOCAL_TF) init -input=false -lockfile=readonly

test:
	$(PYTHON) -m unittest discover -s tests -v

fmt:
	$(TF) fmt -recursive infra

fmt-check:
	$(TF) fmt -recursive -check infra

validate: init
	$(LOCAL_TF) validate
	$(TF) -chdir=infra/aws init -backend=false -input=false -lockfile=readonly
	$(TF) -chdir=infra/aws validate
	$(TF) -chdir=infra/bootstrap init -input=false -lockfile=readonly
	$(TF) -chdir=infra/bootstrap validate

check: fmt-check test validate
	$(MODULE_TF) init -input=false
	$(MODULE_TF) test
	$(TF) -chdir=infra/aws test
	$(TF) -chdir=infra/bootstrap test

deploy: init
	$(LOCAL_TF) apply -input=false -auto-approve
	@$(MAKE) --no-print-directory urls

# Exits non-zero if the deployed stack has drifted from the configuration.
plan: init
	$(LOCAL_TF) plan -input=false -detailed-exitcode

urls:
	@$(LOCAL_TF) output -json service_urls

smoke:
	@$(LOCAL_TF) output -json service_urls | $(PYTHON) scripts/smoke.py

logs:
	docker compose exec -T localstack awslocal logs filter-log-events --log-group-name '/aws/lambda/cinfra-local-$(SERVICE)' --query 'events[].message' --output text

destroy: init
	$(LOCAL_TF) destroy -input=false -auto-approve
