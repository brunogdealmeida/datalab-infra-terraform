terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.8"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.8"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.terraform_service_account != "" ? var.terraform_service_account : null
}

provider "google-beta" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.terraform_service_account != "" ? var.terraform_service_account : null
}
