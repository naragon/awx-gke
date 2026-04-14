variable "bootstrap_project_id" {
  description = "Existing bootstrap project used by provider auth context"
  type        = string
}

variable "create_project" {
  description = "Whether to create project_id in this stack"
  type        = bool
  default     = false
}

variable "project_id" {
  description = "Target GCP project ID (created or existing)"
  type        = string
  default     = "sandragon-awx"
}

variable "project_name" {
  description = "Target project display name (used only if create_project=true)"
  type        = string
  default     = "sandragon-awx"
}

variable "billing_account" {
  description = "Billing account ID (required only if create_project=true)"
  type        = string
  default     = ""
}

variable "org_id" {
  description = "Organization ID (required if folder_id is empty)"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID (required if org_id is empty)"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gke_node_machine_type" {
  description = "Machine type for AWX node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "gke_node_min_count" {
  type    = number
  default = 1
}

variable "gke_node_max_count" {
  type    = number
  default = 3
}

variable "postgres_version" {
  description = "Cloud SQL PostgreSQL major version (AWX operator default is currently PostgreSQL 15)"
  type        = string
  default     = "POSTGRES_15"
}

variable "postgres_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192"
}

variable "master_ipv4_cidr_block" {
  description = "Control plane CIDR for private GKE cluster"
  type        = string
  default     = "172.16.0.16/28"
}

variable "labels" {
  description = "Common labels"
  type        = map(string)
  default = {
    environment = "prod"
    project     = "awx"
    managed_by  = "opentofu"
  }
}

