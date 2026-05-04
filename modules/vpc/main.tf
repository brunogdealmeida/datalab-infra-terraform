locals {
  connector_name = substr("${var.vpc_name}-con", 0, 25)
}

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  project                  = var.project_id
  name                     = "${var.vpc_name}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_ip_range
  private_ip_google_access = true
}

resource "google_vpc_access_connector" "connector" {
  project       = var.project_id
  name          = local.connector_name
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = var.connector_ip_range
}

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.vpc_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
