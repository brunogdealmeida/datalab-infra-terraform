# Root terraform.tfvars is intentionally minimal.
# Use environment-specific var files instead:
#
#   terraform init -backend-config=environments/dev.tfbackend
#   terraform plan  -var-file=environments/dev.tfvars
#   terraform apply -var-file=environments/dev.tfvars
#
# Or use the Makefile:
#   make ENV=dev init
#   make ENV=dev plan
#   make ENV=dev apply
