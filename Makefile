ENV     ?= dev
TFVARS  := environments/$(ENV).tfvars
BACKEND := environments/$(ENV).tfbackend

.PHONY: init plan apply destroy fmt validate

init:
	terraform init -backend-config=$(BACKEND) -reconfigure

plan:
	terraform plan -var-file=environments/$(ENV).tfvars -var="dbt_image_tag=$(IMAGE_TAG)"

apply:
	terraform apply -auto-approve -var-file=environments/$(ENV).tfvars -var="dbt_image_tag=$(IMAGE_TAG)"

destroy:
	terraform destroy -auto-approve -var-file=$(TFVARS)

fmt:
	terraform fmt -recursive

validate:
	terraform validate
