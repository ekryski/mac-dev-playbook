.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help deps install check lint update dry-run

help: ## Show this help.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

deps: ## Install the Ansible collections the playbook needs.
	ansible-galaxy install -r requirements.yml

install: deps ## Run the full playbook.
	ansible-playbook main.yml --ask-become-pass

dry-run: deps ## Show what would change without changing anything.
	ansible-playbook main.yml --check --diff --ask-become-pass

check: ## Syntax-check the playbook.
	ansible-playbook main.yml --syntax-check

lint: ## Lint the playbook.
	ansible-lint

update: deps ## Upgrade every Homebrew formula, cask and App Store app.
	ansible-playbook main.yml --ask-become-pass \
		-e homebrew_upgrade_all=true -e mas_upgrade_all=true \
		--tags homebrew,mas
