.DEFAULT_GOAL := help
.PHONY: help app-list plan deploy app app-dry-run deploy-all check lint test validate shell-check platform preflight install-helpers decommission consolidate-postgres
TARGET_ARGS = $(if $(GROUP),--group $(GROUP),) $(if $(APP),--app $(APP),)
export ANSIBLE_LOCAL_TEMP := $(CURDIR)/.ansible/tmp
export ANSIBLE_HOME := $(CURDIR)/.ansible
help:
	@printf '%s\n' 'make app-list [GROUP=uty]' 'make plan GROUP=uty [APP=sistertika-uty-api]' 'make deploy GROUP=uty [APP=sistertika-uty-api]' 'make app APP=guardian-lab' 'make platform SERVICE=postgres' 'make deploy-all' 'make validate'
app-list:
	@python3 scripts/catalog.py list $(TARGET_ARGS)
plan:
	@python3 scripts/catalog.py plan $(TARGET_ARGS)
deploy:
	@python3 scripts/deploy.py deploy $(TARGET_ARGS)
app: deploy
app-dry-run:
	@python3 scripts/deploy.py check $(TARGET_ARGS)
deploy-all:
	@python3 scripts/deploy.py all
platform:
	@python3 scripts/deploy.py platform --service '$(SERVICE)'
preflight:
	@python3 scripts/deploy.py preflight
install-helpers:
	@python3 scripts/deploy.py helpers
decommission:
	@python3 scripts/deploy.py decommission $(if $(filter yes,$(DESTROY_DATA)),--destroy-data,)
consolidate-postgres:
	@python3 scripts/deploy.py consolidate
check:
	@ansible-playbook playbooks/deploy-group.yml --syntax-check
	@ansible-playbook playbooks/platform.yml --syntax-check
	@ansible-playbook playbooks/decommission.yml --syntax-check
	@ansible-playbook playbooks/consolidate-postgres.yml --syntax-check
lint:
	@ansible-lint playbooks/deploy-group.yml playbooks/platform.yml playbooks/decommission.yml playbooks/consolidate-postgres.yml playbooks/install-helpers.yml
test:
	@python3 -m unittest discover -s tests -v
shell-check:
	@python3 scripts/check-shell.py
validate: test check lint shell-check
	@python3 scripts/catalog.py doctor
	@python3 scripts/app-catalog.py doctor
app-env-check:
	@python3 scripts/app-catalog.py env-check $(TARGET_ARGS)
env-contract-check:
	@python3 scripts/env-contracts.py check $(TARGET_ARGS) $(if $(SOURCE_DIR),--source-dir '$(SOURCE_DIR)',)
env-contract-show:
	@python3 scripts/env-contracts.py show $(TARGET_ARGS) $(if $(SOURCE_DIR),--source-dir '$(SOURCE_DIR)',)
repo-audit:
	@python3 scripts/repo-audit.py check $(TARGET_ARGS) $(if $(SOURCE_DIR),--source-dir '$(SOURCE_DIR)',)
update-github-secrets:
	@python3 scripts/env-contracts.py github-sync $(TARGET_ARGS) $(if $(ALL),--all,)
update-cloudflare-dns:
	@python3 scripts/deploy.py dns $(TARGET_ARGS)
vault-view:
	@ansible-vault view $(if $(GROUP),projects/$(GROUP),platform)/vault.yml
vault-edit:
	@ansible-vault edit $(if $(GROUP),projects/$(GROUP),platform)/vault.yml
ping:
	@ansible all -m ping
aldera-router:
	@python3 scripts/deploy.py deploy --app aldera-router
aldera-router-staging:
	@python3 scripts/deploy.py deploy --app aldera-router-staging
aldera-web-staging:
	@python3 scripts/deploy.py deploy --app aldera-tech-staging
postgres mysql redis nginx docker:
	@python3 scripts/deploy.py platform --service $@
full-setup:
	@python3 scripts/deploy.py platform --service all
	@python3 scripts/deploy.py all

trigger-github-actions:
	@python3 scripts/trigger-workflows.py $(TARGET_ARGS) $(if $(ALL),--all,)
