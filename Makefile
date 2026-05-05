ENV     ?= dev
TFVARS  := environments/$(ENV).tfvars
BACKEND := environments/$(ENV).tfbackend

.PHONY: init plan apply destroy fmt validate

init:
	terraform init -backend-config=$(BACKEND) -reconfigure

plan:
	terraform plan -var-file=$(TFVARS)

apply:
	terraform apply -var-file=$(TFVARS)

destroy:
	terraform destroy -var-file=$(TFVARS)

fmt:
	terraform fmt -recursive

validate:
	terraform validate
