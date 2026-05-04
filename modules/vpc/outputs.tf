output "network_id" {
  description = "VPC network self-link."
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Subnet self-link."
  value       = google_compute_subnetwork.subnet.id
}

output "connector_id" {
  description = "VPC Access Connector ID (full resource path)."
  value       = google_vpc_access_connector.connector.id
}
