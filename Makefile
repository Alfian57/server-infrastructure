.PHONY: help setup ping check lint install clean

.DEFAULT_GOAL := help

# ═══════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════

PLAYBOOK := playbooks/server-setup.yml
INVENTORY := inventory/hosts.ini
VAULT_PASS := .vault_pass

# Ansible options
ifneq (,$(wildcard $(VAULT_PASS)))
	OPTS := -i $(INVENTORY) --vault-password-file=$(VAULT_PASS) -e @group_vars/all/vault.yml
else
	OPTS := -i $(INVENTORY)
endif

# SSH helper
SSH_PORT = $(shell grep '^ansible_port' ansible.cfg 2>/dev/null | awk -F'=' '{print $$2}' | tr -d ' ' || echo '22')
SSH_HOST = $(shell grep -v '^#' $(INVENTORY) | grep -v '^\[' | grep -v '^$$' | head -1 | awk '{print $$1}')
SSH = ssh -p $(SSH_PORT) deployer@$(SSH_HOST)

# Helper to run playbook with tag
run = @ansible-playbook $(PLAYBOOK) $(OPTS) --tags $(1)

# ═══════════════════════════════════════════════════════
# Main Targets
# ═══════════════════════════════════════════════════════

##@ General

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1m%-20s\033[0m %s\n", "Target", "Description"} /^[a-zA-Z_-]+:.*?##/ { printf "\033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

ping: ## Test connection
	@ansible all $(OPTS) -m ping

check: ## Check syntax
	@ansible-playbook $(PLAYBOOK) $(OPTS) --syntax-check && echo "✓ OK"

lint: ## Lint playbook
	@ansible-lint $(PLAYBOOK) 2>/dev/null || echo "Install: pip install ansible-lint"

##@ Deployment

full-setup: ## ⭐ ONE COMMAND: Bootstrap + Setup + Deploy (for fresh server)
	@echo "═══════════════════════════════════════════════════════════════════"
	@echo "  FULL SERVER SETUP - One Command Deployment"
	@echo "═══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "This will run:"
	@echo "  1. Bootstrap SSH key authentication"
	@echo "  2. Full server setup (Docker, databases, etc)"
	@echo "  3. Deploy all applications with migrations & seeders"
	@echo ""
	@echo "You will be prompted for the VPS root password."
	@echo ""
	@read -p "Press Enter to continue or Ctrl+C to cancel..."
	@echo ""
	@echo "════════════════════════════════════════════════════════════════════"
	@echo "  Step 1/3: Bootstrap SSH Key"
	@echo "════════════════════════════════════════════════════════════════════"
	@ansible-playbook playbooks/bootstrap-ssh.yml -i $(INVENTORY) --ask-pass
	@echo ""
	@echo "════════════════════════════════════════════════════════════════════"
	@echo "  Step 2/3: Switching to SSH Key Authentication"
	@echo "════════════════════════════════════════════════════════════════════"
	@./scripts/update-inventory-ssh.sh || true
	@sleep 2
	@echo ""
	@echo "════════════════════════════════════════════════════════════════════"
	@echo "  Step 3/3: Full Deployment with Migrations & Seeders"
	@echo "════════════════════════════════════════════════════════════════════"
	@ansible-playbook $(PLAYBOOK) $(OPTS) -e "run_seeder_on_deploy=true"
	@echo ""
	@echo "════════════════════════════════════════════════════════════════════"
	@echo "  ✅ FULL SETUP COMPLETE!"
	@echo "════════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "Your server is now ready. Access your apps via Nginx Proxy Manager."
	@echo ""
	@echo "Useful commands:"
	@echo "  make status     - Check server status"
	@echo "  make containers - List running containers"
	@echo "  make ssh        - SSH to server"
	@echo ""

bootstrap: ## Bootstrap SSH key (first run with password)
	@echo "═══════════════════════════════════════════"
	@echo "  SSH Key Bootstrap"
	@echo "═══════════════════════════════════════════"
	@echo "This will setup SSH key authentication on fresh VPS"
	@echo "You will be prompted for the VPS password"
	@echo ""
	@ansible-playbook playbooks/bootstrap-ssh.yml -i $(INVENTORY) --ask-pass
	@echo ""
	@echo "If successful, run: make switch-to-ssh"

switch-to-ssh: ## Switch inventory to use SSH key (after bootstrap)
	@./scripts/update-inventory-ssh.sh

deploy: check ## Full deployment (use after bootstrap)
	@ansible-playbook $(PLAYBOOK) $(OPTS)

deploy-fresh: check ## Fresh deployment with seeders
	@ansible-playbook $(PLAYBOOK) $(OPTS) -e "run_seeder_on_deploy=true"

deploy-script: ## Full deployment using script (interactive)
	@./scripts/full-deploy.sh

deploy-dry-run: ## Dry run deployment
	@./scripts/full-deploy.sh --dry-run

setup: check ## Full setup (alias for deploy)
	@ansible-playbook $(PLAYBOOK) $(OPTS)

setup-dry-run: check ## Dry run
	@ansible-playbook $(PLAYBOOK) $(OPTS) --check --diff

setup-verbose: check ## Verbose setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) -vvv

quick: check ## Quick (skip apt update)
	@ansible-playbook $(PLAYBOOK) $(OPTS) --skip-tags update-apt

##@ Category Deployment

system: check ## System setup only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags system

security: check ## Security hardening only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags security

infrastructure: check ## Infrastructure only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags infrastructure

database: check ## Databases only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags database

application: check ## Applications only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags application

optimization: check ## Cost optimization only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags optimization

##@ Individual Roles - Infrastructure

docker: check ## Docker setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags docker-setup

nginx: check ## Nginx Proxy Manager
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags nginx-proxy-setup

autoheal: check ## Autoheal setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags autoheal-setup

##@ Individual Roles - Databases

mysql: check ## MySQL setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags mysql-setup

postgres: check ## PostgreSQL setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags postgres-setup

redis: check ## Redis setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags redis-setup

##@ Individual Roles - Applications

materi-ku: check ## Materi-Ku app
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags materi-ku-setup

panca-trivia: check ## Panca Trivia app
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags panca-trivia-setup

ruang-istirahat: check ## Ruang Istirahat app
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags ruang-istirahat-setup

tech-talk: check ## Tech Talk app
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags tech-talk-setup

##@ GitHub Actions (Local - No SSH to Server)

trigger-actions: ## ⚡ Trigger all GitHub Actions workflows (from local)
	@./scripts/trigger-github-actions-local.sh

trigger-actions-dry: ## Dry run trigger actions
	@./scripts/trigger-github-actions-local.sh --dry-run

##@ Local Scripts (Run from local machine without server SSH)

update-cloud: ## ☁️ Update ALL cloud services (GitHub + Cloudflare) in sequence
	@./scripts/update-cloud-services.sh

update-cloud-y: ## ☁️ Update ALL cloud services (auto-confirm)
	@./scripts/update-cloud-services.sh -y

check-cloud: ## ✅ Verify GitHub secrets and Cloudflare DNS are configured
	@./scripts/check-cloud-services.sh

update-github-secrets: ## 🔑 Update GitHub secrets from local (no SSH needed)
	@./scripts/update-github-secrets-local.sh

update-cloudflare-dns: ## 🌐 Update Cloudflare DNS from local (no SSH needed)
	@./scripts/update-cloudflare-dns-local.sh

update-github-secrets-y: ## 🔑 Update GitHub secrets (auto-confirm)
	@./scripts/update-github-secrets-local.sh <<< "y"

update-cloudflare-dns-y: ## 🌐 Update Cloudflare DNS (auto-confirm)
	@./scripts/update-cloudflare-dns-local.sh -y

##@ Security Operations

security-ufw: check ## UFW firewall only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags security-ufw

security-fail2ban: check ## Fail2ban only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags security-fail2ban

security-ssh: check ## SSH hardening only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags security-ssh

security-docker: check ## Docker security only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags security-docker

security-check: ## Check security status
	@echo "═══════════════════════════════════════════"
	@echo "  Security Status Check"
	@echo "═══════════════════════════════════════════"
	@ansible all $(OPTS) -m shell -a "echo '=== UFW Status ===' && ufw status numbered" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "echo '=== Fail2ban ===' && fail2ban-client status" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "echo '=== SSH Config ===' && sshd -T 2>/dev/null | grep -E 'permitrootlogin|passwordauthentication|maxauthtries'" -b 2>/dev/null || true

##@ Cost Optimization

cost: check ## Full cost optimization
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags cost-optimization

cost-docker: check ## Docker cleanup only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags cost-docker

cost-logs: check ## Log cleanup only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags cost-logs

cost-resources: check ## Resource limits only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags cost-resources

cost-monitoring: check ## Disk monitoring only
	@ansible-playbook $(PLAYBOOK) $(OPTS) --tags cost-monitoring

cost-report: ## Show cost/resource report
	@echo "═══════════════════════════════════════════"
	@echo "  Resource & Cost Report"
	@echo "═══════════════════════════════════════════"
	@ansible all $(OPTS) -m shell -a "echo '=== Disk Usage ===' && df -h / /opt 2>/dev/null" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "echo '=== Memory ===' && free -h" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "echo '=== Docker ===' && docker system df" -b 2>/dev/null || true

##@ Vault Management

vault-create: ## Create vault from example
	@[ ! -f group_vars/all/vault.yml ] || (echo "vault.yml already exists!" && exit 1)
	@cp group_vars/all/vault.yml.example group_vars/all/vault.yml
	@echo "Edit group_vars/all/vault.yml then run: make vault-encrypt"

vault-edit: ## Edit vault file
	@ansible-vault edit $(if $(FILE),$(FILE),group_vars/all/vault.yml)

vault-encrypt: ## Encrypt file (FILE=path)
	@[ -n "$(FILE)" ] && ansible-vault encrypt $(FILE) || ansible-vault encrypt group_vars/all/vault.yml

vault-decrypt: ## Decrypt file (FILE=path)
	@[ -n "$(FILE)" ] && ansible-vault decrypt $(FILE) || ansible-vault decrypt group_vars/all/vault.yml

vault-view: ## View vault file
	@ansible-vault view $(if $(FILE),$(FILE),group_vars/all/vault.yml)

vault-status: ## Check vault encryption status
	@echo "═══════════════════════════════════════════"
	@echo "  Vault Status"
	@echo "═══════════════════════════════════════════"
	@[ -f group_vars/all/vault.yml ] && \
		(head -1 group_vars/all/vault.yml | grep -q '^\$$ANSIBLE_VAULT' && echo "✓ vault.yml: Encrypted" || echo "✗ vault.yml: NOT ENCRYPTED (DANGER!)") || \
		echo "✗ vault.yml: Not found"
	@[ -f .vault_pass ] && echo "✓ .vault_pass: Found" || echo "⚠ .vault_pass: Not found (will prompt for password)"

##@ Server Management

ssh: ## SSH to server
	@$(SSH)

reboot: ## Reboot server
	@echo "⚠️  Rebooting server..."
	@ansible all $(OPTS) -m reboot -a "reboot_timeout=300"

status: ## Show server status
	@echo "═══════════════════════════════════════════"
	@echo "  Server Status"
	@echo "═══════════════════════════════════════════"
	@ansible all $(OPTS) -m ping -o 2>/dev/null && echo "✓ Server reachable" || echo "✗ Server unreachable"
	@ansible all $(OPTS) -m shell -a "uptime" 2>/dev/null || true

containers: ## Show running containers
	@ansible all $(OPTS) -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null || true

logs: ## Show container logs (CONTAINER=name)
	@[ -n "$(CONTAINER)" ] && ansible all $(OPTS) -m shell -a "docker logs --tail 50 $(CONTAINER)" 2>/dev/null || \
		echo "Usage: make logs CONTAINER=container_name"

facts: ## Gather server facts
	@ansible all $(OPTS) -m setup

##@ Information

list-hosts: ## List inventory hosts
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-hosts

list-tags: ## List available tags
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-tags

list-tasks: ## List all tasks
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-tasks

list-roles: ## List roles structure
	@cat roles/ROLES.md 2>/dev/null || ls -la roles/

##@ Setup & Utilities

install: ## Install Ansible and dependencies
	@echo "Installing Ansible and dependencies..."
	@pip install --upgrade pip
	@pip install --upgrade ansible ansible-lint yamllint
	@ansible-galaxy collection install -r requirements.yml --force
	@echo "✓ Installation complete"

update: ## Update Ansible collections
	@ansible-galaxy collection install -r requirements.yml --force

clean: ## Clean temporary files
	@echo "Cleaning temporary files..."
	@find . -name "*.retry" -delete
	@find . -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf /tmp/ansible_facts_cache/ 2>/dev/null || true
	@echo "✓ Clean complete"

validate: check lint ## Full validation (syntax + lint)

version: ## Show versions
	@echo "═══════════════════════════════════════════"
	@echo "  Version Information"
	@echo "═══════════════════════════════════════════"
	@ansible --version | head -1
	@ansible-lint --version 2>/dev/null || echo "ansible-lint: not installed"

