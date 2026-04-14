output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "gke_cluster_name" {
  value = google_container_cluster.awx.name
}

output "gke_location" {
  value = var.region
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "ingress_ip_address" {
  value = google_compute_global_address.awx_ingress_ip.address
}

output "ingress_ip_name" {
  value = google_compute_global_address.awx_ingress_ip.name
}

output "cloud_sql_private_ip" {
  value = google_sql_database_instance.awx.private_ip_address
}

output "cloud_sql_database" {
  value = google_sql_database.awx.name
}

output "cloud_sql_user" {
  value = google_sql_user.awx.name
}

output "postgres_password_secret_id" {
  value = google_secret_manager_secret.postgres_password.secret_id
}

output "awx_admin_password_secret_id" {
  value = google_secret_manager_secret.awx_admin_password.secret_id
}
