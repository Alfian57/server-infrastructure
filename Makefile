.PHONY: help setup ping check syntax lint install update clean vault-status vault-migrate vault-main

# Default target
.DEFAULT_GOAL := help

# Variables
PLAYBOOK := playbooks/server-setup.yml
INVENTORY := inventory/hosts.ini
VAULT_PASSWORD_FILE := .vault_pass

# Check if vault password file exists and add to ansible options
ifneq (,$(wildcard $(VAULT_PASSWORD_FILE)))
	ANSIBLE_OPTS := -i $(INVENTORY) --vault-password-file=$(VAULT_PASSWORD_FILE)
else
	ANSIBLE_OPTS := -i $(INVENTORY)
endif

##@ General Commands

help: ## Display this help message
	@printf "\n"
	@printf "\033[0;36m═══════════════════════════════════════════════════════\033[0m\n"
	@printf "\033[0;32m  Ansible Infrastructure Management - Makefile\033[0m\n"
	@printf "\033[0;36m═══════════════════════════════════════════════════════\033[0m\n"
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[0;36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[0;33m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\n"

ping: ## Test connection to all servers
	@printf "\033[0;34mTesting connection to servers...\033[0m\n"
	@ansible all $(ANSIBLE_OPTS) -m ping

check: ## Check playbook for syntax errors (dry-run)
	@printf "\033[0;34mChecking playbook syntax...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --syntax-check
	@printf "\033[0;32m✓ Syntax check passed!\033[0m\n"

syntax: check ## Alias for 'check'

lint: ## Lint Ansible playbook and roles with ansible-lint
	@printf "\033[0;34mLinting Ansible code...\033[0m\n"
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint $(PLAYBOOK); \
	else \
		printf "\033[0;31m✗ ansible-lint not installed. Install with: pip install ansible-lint\033[0m\n"; \
		exit 1; \
	fi

##@ Full Deployment

setup: check ## Run complete server setup (all roles)
	@printf "\033[0;32mRunning complete server setup...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS)

setup-ask-pass: check ## Run complete setup with password prompt
	@printf "\033[0;32mRunning complete server setup (with password prompt)...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --ask-become-pass

setup-verbose: check ## Run complete setup with verbose output
	@printf "\033[0;32mRunning complete server setup (verbose)...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) -vvv

setup-dry-run: check ## Run complete setup in check mode (dry-run)
	@printf "\033[0;33mRunning complete server setup (DRY RUN)...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --check

##@ Tag-based Deployment

system: check ## Deploy only system roles (update-apt, users-setup, git-setup)
	@printf "\033[0;32mDeploying system configuration...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags system

infrastructure: check ## Deploy only infrastructure roles (docker, autoheal, nginx-proxy)
	@printf "\033[0;32mDeploying infrastructure...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags infrastructure

database: check ## Deploy only database roles (mysql, postgres, redis)
	@printf "\033[0;32mDeploying databases...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags database

application: check ## Deploy only application roles (all apps)
	@printf "\033[0;32mDeploying applications...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags application

##@ Individual Role Deployment

update-apt: check ## Run only update-apt role
	@printf "\033[0;32mUpdating apt packages...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags update-apt

users: check ## Run only users-setup role
	@printf "\033[0;32mSetting up users...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags users-setup

git: check ## Run only git-setup role
	@printf "\033[0;32mSetting up git...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags git-setup

docker: check ## Run only docker-setup role
	@printf "\033[0;32mSetting up Docker...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags docker-setup

autoheal: check ## Run only autoheal-setup role
	@printf "\033[0;32mSetting up Autoheal...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags autoheal-setup

nginx: check ## Run only nginx-proxy-setup role
	@printf "\033[0;32mSetting up Nginx Proxy Manager...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags nginx-proxy-setup

mysql: check ## Run only mysql-setup role
	@printf "\033[0;32mSetting up MySQL...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags mysql-setup

postgres: check ## Run only postgres-setup role
	@printf "\033[0;32mSetting up PostgreSQL...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags postgres-setup

redis: check ## Run only redis-setup role
	@printf "\033[0;32mSetting up Redis...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags redis-setup

##@ Application Deployment

materi-ku: check ## Deploy only materi-ku application
	@printf "\033[0;32mDeploying Materi-Ku...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags materi-ku-setup

panca-trivia: check ## Deploy only panca-trivia application
	@printf "\033[0;32mDeploying Panca Trivia...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags panca-trivia-setup

ruang-istirahat: check ## Deploy only ruang-istirahat application
	@printf "\033[0;32mDeploying Ruang Istirahat...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags ruang-istirahat-setup

tech-talk: check ## Deploy only tech-talk application
	@printf "\033[0;32mDeploying Tech Talk...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags tech-talk-setup

all-apps: check ## Deploy all applications at once
	@printf "\033[0;32mDeploying all applications...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags application

##@ Server Management

facts: ## Gather and display server facts
	@printf "\033[0;34mGathering server facts...\033[0m\n"
	@ansible all $(ANSIBLE_OPTS) -m setup

list-hosts: ## List all hosts in inventory
	@printf "\033[0;34mListing all hosts...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --list-hosts

list-tags: ## List all available tags
	@printf "\033[0;34mListing all available tags...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --list-tags

list-tasks: ## List all tasks that would be executed
	@printf "\033[0;34mListing all tasks...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --list-tasks

server-info: ## Display server information
	@printf "\033[0;34mServer Information:\033[0m\n"
	@ansible all $(ANSIBLE_OPTS) -m shell -a "uname -a"
	@printf ""
	@ansible all $(ANSIBLE_OPTS) -m shell -a "docker --version 2>/dev/null || echo 'Docker not installed'"
	@printf ""
	@ansible all $(ANSIBLE_OPTS) -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo 'No containers running'"

##@ Vault Management

vault-create-pass: ## Create vault password file (interactive)
	@printf "\033[0;33mCreating vault password file...\033[0m\n"
	@read -sp "Enter vault password: " VAULT_PASS; \
	echo "$$VAULT_PASS" > $(VAULT_PASSWORD_FILE); \
	chmod 600 $(VAULT_PASSWORD_FILE); \
	echo ""; \
	printf "\033[0;32m✓ Vault password file created at $(VAULT_PASSWORD_FILE)\033[0m\n"
	@printf "\033[0;33m⚠️  Add $(VAULT_PASSWORD_FILE) to .gitignore!\033[0m\n"

vault-encrypt: ## Encrypt sensitive files with Ansible Vault
	@printf "\033[0;33mEncrypting files with Ansible Vault...\033[0m\n"
	@printf "Usage: make vault-encrypt FILE=path/to/file\n"
	@if [ -z "$(FILE)" ]; then \
		printf "\033[0;31m✗ Please specify FILE=path/to/file\033[0m\n"; \
		exit 1; \
	fi
	@ansible-vault encrypt $(FILE)

vault-decrypt: ## Decrypt Ansible Vault encrypted files
	@printf "\033[0;33mDecrypting files with Ansible Vault...\033[0m\n"
	@printf "Usage: make vault-decrypt FILE=path/to/file\n"
	@if [ -z "$(FILE)" ]; then \
		printf "\033[0;31m✗ Please specify FILE=path/to/file\033[0m\n"; \
		exit 1; \
	fi
	@ansible-vault decrypt $(FILE)

vault-edit: ## Edit Ansible Vault encrypted files
	@printf "\033[0;33mEditing encrypted file...\033[0m\n"
	@printf "Usage: make vault-edit FILE=path/to/file\n"
	@if [ -z "$(FILE)" ]; then \
		printf "\033[0;31m✗ Please specify FILE=path/to/file\033[0m\n"; \
		exit 1; \
	fi
	@ansible-vault edit $(FILE)

vault-view: ## View Ansible Vault encrypted files
	@printf "\033[0;33mViewing encrypted file...\033[0m\n"
	@printf "Usage: make vault-view FILE=path/to/file\n"
	@if [ -z "$(FILE)" ]; then \
		printf "\033[0;31m✗ Please specify FILE=path/to/file\033[0m\n"; \
		exit 1; \
	fi
	@ansible-vault view $(FILE)

vault-main: ## Quick edit main vault file (group_vars/all/vault.yml)
	@printf "\033[0;33mEditing main vault file...\033[0m\n"
	@ansible-vault edit group_vars/all/vault.yml

vault-status: ## Show status of vault files
	@printf "\033[0;36mVault Files Status:\033[0m\n"
	@printf "\n\033[0;33mMain Vault:\033[0m\n"
	@if [ -f group_vars/all/vault.yml ]; then \
		if grep -q '^\$$ANSIBLE_VAULT' group_vars/all/vault.yml 2>/dev/null; then \
			printf "  \033[0;32m✓\033[0m group_vars/all/vault.yml (encrypted)\n"; \
		else \
			printf "  \033[0;31m✗\033[0m group_vars/all/vault.yml (NOT encrypted!)\n"; \
		fi \
	else \
		printf "  \033[0;31m✗\033[0m group_vars/all/vault.yml (not found)\n"; \
	fi
	@printf "\n\033[0;33mOld Encrypted Files (should be migrated):\033[0m\n"
	@old_files=$$(find roles -type f \( -name "*.yml" -o -name ".env" \) -exec grep -l '^\$$ANSIBLE_VAULT' {} \; 2>/dev/null); \
	if [ -z "$$old_files" ]; then \
		printf "  \033[0;32m✓\033[0m No old encrypted files found\n"; \
	else \
		echo "$$old_files" | while read -r file; do \
			printf "  \033[0;33m⚠\033[0m $$file\n"; \
		done \
	fi
	@printf "\n"

vault-migrate: ## Run vault migration script
	@printf "\033[0;36mRunning vault migration script...\033[0m\n"
	@bash group_vars/migrate-vault.sh

##@ Utilities

install: ## Install Ansible and required collections
	@printf "\033[0;32mInstalling Ansible and collections...\033[0m\n"
	@pip install --upgrade ansible ansible-lint
	@ansible-galaxy collection install community.docker
	@ansible-galaxy collection install ansible.posix
	@ansible-galaxy collection install community.general
	@printf "\033[0;32m✓ Installation complete!\033[0m\n"

update: ## Update Ansible collections
	@printf "\033[0;32mUpdating Ansible collections...\033[0m\n"
	@ansible-galaxy collection install community.docker --force
	@ansible-galaxy collection install ansible.posix --force
	@ansible-galaxy collection install community.general --force
	@printf "\033[0;32m✓ Collections updated!\033[0m\n"

clean: ## Clean temporary files and caches
	@printf "\033[0;33mCleaning temporary files...\033[0m\n"
	@find . -type f -name "*.retry" -delete
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .ansible_facts_cache/
	@printf "\033[0;32m✓ Cleanup complete!\033[0m\n"

version: ## Show Ansible version
	@printf "\033[0;34mAnsible Version:\033[0m\n"
	@ansible --version

##@ Quick Actions

quick-setup: ## Quick setup (skip system updates)
	@printf "\033[0;32mRunning quick setup (skipping apt updates)...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --skip-tags update-apt

fresh-install: ## Fresh install on new server (interactive)
	@printf "\033[0;32mStarting fresh server installation...\033[0m\n"
	@printf "\033[0;33mThis will run the complete setup. Continue? [y/N]\033[0m\n"
	@read -r REPLY; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		$(MAKE) setup-verbose; \
	else \
		printf "\033[0;31mCancelled.\033[0m\n"; \
	fi

redeploy-app: ## Redeploy specific application (Usage: make redeploy-app APP=materi-ku)
	@if [ -z "$(APP)" ]; then \
		printf "\033[0;31m✗ Please specify APP=<app-name>\033[0m\n"; \
		printf "\033[0;33mAvailable apps: materi-ku, panca-trivia, ruang-istirahat, tech-talk\033[0m\n"; \
		exit 1; \
	fi
	@printf "\033[0;32mRedeploying $(APP)...\033[0m\n"
	@ansible-playbook $(PLAYBOOK) $(ANSIBLE_OPTS) --tags $(APP)-setup

status: ## Quick status check of all services
	@printf "\033[0;36m═══════════════════════════════════════════════════════\033[0m\n"
	@printf "\033[0;32m  Server Status\033[0m\n"
	@printf "\033[0;36m═══════════════════════════════════════════════════════\033[0m\n"
	@printf "\n"
	@printf "\033[0;33mChecking server connectivity...\033[0m\n"
	@ansible all $(ANSIBLE_OPTS) -m ping -o
	@printf "\n"
	@printf "\033[0;33mDocker containers:\033[0m\n"
	@ansible all $(ANSIBLE_OPTS) -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || echo 'Docker not available'" -o
	@printf "\n"
