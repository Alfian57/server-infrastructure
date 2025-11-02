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
	OPTS := -i $(INVENTORY) --vault-password-file=$(VAULT_PASS)
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

setup: check ## Full setup
	@ansible-playbook $(PLAYBOOK) $(OPTS)

setup-dry-run: check ## Dry run
	@ansible-playbook $(PLAYBOOK) $(OPTS) --check

setup-verbose: check ## Verbose setup
	@ansible-playbook $(PLAYBOOK) $(OPTS) -vvv

quick: check ## Quick (skip apt update)
	@ansible-playbook $(PLAYBOOK) $(OPTS) --skip-tags update-apt

##@ Components

system: check ## System setup
	$(call run,system)

security: check ## Security hardening
	$(call run,security)

infrastructure: check ## Infrastructure
	$(call run,infrastructure)

database: check ## Databases
	$(call run,database)

application: check ## Applications
	$(call run,application)

optimization: check ## Cost optimization
	$(call run,optimization)

##@ Infrastructure

docker: check ## Docker
	$(call run,docker-setup)

nginx: check ## Nginx Proxy
	$(call run,nginx-proxy-setup)

mysql: check ## MySQL
	$(call run,mysql-setup)

postgres: check ## PostgreSQL
	$(call run,postgres-setup)

redis: check ## Redis
	$(call run,redis-setup)

##@ Applications

materi-ku: check ## Materi-Ku
	$(call run,materi-ku-setup)

panca-trivia: check ## Panca Trivia
	$(call run,panca-trivia-setup)

ruang-istirahat: check ## Ruang Istirahat
	$(call run,ruang-istirahat-setup)

tech-talk: check ## Tech Talk
	$(call run,tech-talk-setup)

##@ Security

security-ufw: check ## UFW firewall
	$(call run,security-ufw)

security-fail2ban: check ## Fail2ban
	$(call run,security-fail2ban)

security-ssh: check ## SSH hardening
	$(call run,security-ssh)

security-docker: check ## Docker security
	$(call run,security-docker)

security-check: ## Security status
	@echo "=== Security Status ==="
	@ansible all $(OPTS) -m shell -a "ufw status" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "fail2ban-client status" -b 2>/dev/null || true

##@ Optimization

cost: check ## Full cost optimization
	$(call run,cost-optimization)

cost-docker: check ## Docker cleanup
	$(call run,cost-docker)

cost-logs: check ## Log cleanup
	$(call run,cost-logs)

cost-resources: check ## Resource limits
	$(call run,cost-resources)

cost-monitoring: check ## Disk monitoring
	$(call run,cost-monitoring)

cost-report: ## Cost report
	@echo "=== Cost Report ==="
	@ansible all $(OPTS) -m shell -a "disk-check 2>/dev/null || df -h /" -b 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "docker system df 2>/dev/null || echo 'N/A'" -b 2>/dev/null || true

##@ Vault

vault-edit: ## Edit vault file
	@ansible-vault edit $(if $(FILE),$(FILE),group_vars/all/vault.yml)

vault-encrypt: ## Encrypt file (FILE=path)
	@[ -n "$(FILE)" ] || (echo "Usage: make vault-encrypt FILE=path" && exit 1)
	@ansible-vault encrypt $(FILE)

vault-decrypt: ## Decrypt file (FILE=path)
	@[ -n "$(FILE)" ] || (echo "Usage: make vault-decrypt FILE=path" && exit 1)
	@ansible-vault decrypt $(FILE)

vault-status: ## Vault status
	@echo "=== Vault Status ==="
	@[ -f group_vars/all/vault.yml ] && \
		(grep -q '^\$$ANSIBLE_VAULT' group_vars/all/vault.yml && echo "✓ Encrypted" || echo "✗ Not encrypted") || \
		echo "✗ Not found"

##@ Server

ssh: ## SSH to server
	@$(SSH)

ssh-github: ## Update GitHub secrets
	@$(SSH) -t 'update-github-secrets'

ssh-cloudflare: ## Update Cloudflare DNS
	@$(SSH) -t 'update-cloudflare-dns'

status: ## Server status
	@echo "=== Status ==="
	@ansible all $(OPTS) -m ping -o 2>/dev/null || true
	@ansible all $(OPTS) -m shell -a "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null || true

facts: ## Server facts
	@ansible all $(OPTS) -m setup

##@ Info

list-hosts: ## List hosts
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-hosts

list-tags: ## List tags
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-tags

list-tasks: ## List tasks
	@ansible-playbook $(PLAYBOOK) $(OPTS) --list-tasks

##@ Utils

install: ## Install Ansible
	@pip install --upgrade ansible ansible-lint
	@ansible-galaxy collection install community.docker ansible.posix community.general

update: ## Update collections
	@ansible-galaxy collection install community.docker ansible.posix community.general --force

clean: ## Clean temp files
	@find . -name "*.retry" -delete
	@find . -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@rm -rf .ansible_facts_cache/

version: ## Show version
	@ansible --version
