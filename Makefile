TOFU_DIR=tofu
ANSIBLE_DIR=ansible

.PHONY: fmt validate plan apply ansible-deps deploy-awx

fmt:
	tofu -chdir=$(TOFU_DIR) fmt -recursive

validate:
	tofu -chdir=$(TOFU_DIR) init -backend=false
	tofu -chdir=$(TOFU_DIR) validate

plan:
	tofu -chdir=$(TOFU_DIR) plan

apply:
	tofu -chdir=$(TOFU_DIR) apply

ansible-deps:
	ansible-galaxy collection install -r $(ANSIBLE_DIR)/requirements.yml

deploy-awx:
	ansible-playbook -i $(ANSIBLE_DIR)/inventory/hosts.yml $(ANSIBLE_DIR)/playbooks/deploy_awx.yml
