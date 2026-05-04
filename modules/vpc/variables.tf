variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "vpc_name" {
  description = "VPC network name."
  type        = string
}

variable "subnet_ip_range" {
  description = "CIDR range for the primary subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "connector_ip_range" {
  description = "CIDR range for the Serverless VPC Access Connector. Must be a /28."
  type        = string
  default     = "10.8.0.0/28"
}
