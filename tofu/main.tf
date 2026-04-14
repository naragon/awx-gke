resource "google_project" "awx" {
  name            = var.project_name
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id != "" ? var.org_id : null
  folder_id       = var.folder_id != "" ? var.folder_id : null

  lifecycle {
    precondition {
      condition     = (var.org_id != "" && var.folder_id == "") || (var.org_id == "" && var.folder_id != "")
      error_message = "Exactly one of org_id or folder_id must be provided."
    }
  }
}

resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false

  depends_on = [google_project.awx]
}

resource "google_compute_network" "vpc" {
  name                    = "awx-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.services]
}

resource "google_compute_subnetwork" "gke" {
  name          = "awx-gke-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/20"

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

resource "google_compute_router" "nat_router" {
  name    = "awx-nat-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "awx-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.nat_router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_global_address" "private_service_range" {
  name          = "awx-private-service-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "awx-gke-nodes"
  display_name = "AWX GKE Node Service Account"
}

resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_resource_metadata" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "awx" {
  name                = "awx-gke"
  project             = var.project_id
  location            = var.region
  network             = google_compute_network.vpc.id
  subnetwork          = google_compute_subnetwork.gke.id
  remove_default_node_pool = true
  initial_node_count  = 1
  deletion_protection = false

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  depends_on = [
    google_project_service.services,
    google_compute_router_nat.nat
  ]
}

resource "google_container_node_pool" "primary" {
  name       = "awx-primary-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.awx.name

  autoscaling {
    min_node_count = var.gke_node_min_count
    max_node_count = var.gke_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.gke_node_machine_type
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = var.labels
  }

  depends_on = [google_container_cluster.awx]
}

resource "google_sql_database_instance" "awx" {
  name             = "awx-postgres"
  project          = var.project_id
  region           = var.region
  database_version = var.postgres_version

  settings {
    tier              = var.postgres_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 20

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    user_labels = var.labels
  }

  deletion_protection = false

  depends_on = [
    google_project_service.services,
    google_service_networking_connection.private_vpc_connection
  ]
}

resource "google_sql_database" "awx" {
  name     = "awx"
  project  = var.project_id
  instance = google_sql_database_instance.awx.name
}

resource "random_password" "postgres_password" {
  length  = 24
  special = false
}

resource "google_sql_user" "awx" {
  name     = "awx"
  project  = var.project_id
  instance = google_sql_database_instance.awx.name
  password = random_password.postgres_password.result
}

resource "random_password" "awx_admin_password" {
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "postgres_password" {
  project   = var.project_id
  secret_id = "awx-postgres-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = random_password.postgres_password.result
}

resource "google_secret_manager_secret" "awx_admin_password" {
  project   = var.project_id
  secret_id = "awx-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "awx_admin_password" {
  secret      = google_secret_manager_secret.awx_admin_password.id
  secret_data = random_password.awx_admin_password.result
}

resource "google_compute_global_address" "awx_ingress_ip" {
  name    = "awx-ingress-ip"
  project = var.project_id
}
