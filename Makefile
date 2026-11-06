.DEFAULT_GOAL := infra
.PHONY: infra

export ACTION ?= help
export GROUP APP SERVICE DESTROY_DATA SOURCE_DIR ALL
export ANSIBLE_LOCAL_TEMP := $(CURDIR)/.ansible/tmp
export ANSIBLE_HOME := $(CURDIR)/.ansible

infra:
	@python3 scripts/infra.py
