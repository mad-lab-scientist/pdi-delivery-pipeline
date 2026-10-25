# GCP VPC: custom-subnet network, subnets with optional secondary ranges (GKE) and flow logs,
# firewall rules (allow internal, allow SSH from trusted sources, deny the rest implicitly),
# and an optional Cloud NAT for egress from private instances.
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 9.0"
    }
  }
}

resource "google_compute_network" "this" {
  project                         = var.project_id
  name                            = "${var.name}-vpc"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "this" {
  for_each                 = var.subnets
  project                  = var.project_id
  name                     = "${var.name}-${each.key}"
  network                  = google_compute_network.this.id
  region                   = coalesce(each.value.region, var.region)
  ip_cidr_range            = each.value.cidr
  private_ip_google_access = each.value.private_google_access

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_firewall" "allow_internal" {
  project   = var.project_id
  name      = "${var.name}-allow-internal"
  network   = google_compute_network.this.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = [for s in var.subnets : s.cidr]
}

resource "google_compute_firewall" "allow_ssh" {
  project   = var.project_id
  name      = "${var.name}-allow-ssh"
  network   = google_compute_network.this.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.allowed_ssh_sources
  target_tags   = ["allow-ssh"]
}

resource "google_compute_firewall" "deny_all" {
  project   = var.project_id
  name      = "${var.name}-deny-all-ingress"
  network   = google_compute_network.this.name
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "this" {
  count   = var.enable_cloud_nat ? 1 : 0
  project = var.project_id
  name    = "${var.name}-router"
  network = google_compute_network.this.id
  region  = var.region
}

resource "google_compute_router_nat" "this" {
  count                              = var.enable_cloud_nat ? 1 : 0
  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
