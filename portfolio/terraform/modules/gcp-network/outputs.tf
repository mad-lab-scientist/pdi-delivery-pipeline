output "network_id" {
  value = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "subnet_ids" {
  value       = { for k, s in google_compute_subnetwork.this : k => s.id }
  description = "Map of subnet name to self link."
}

output "cloud_nat_name" {
  value = var.enable_cloud_nat ? google_compute_router_nat.this[0].name : null
}
