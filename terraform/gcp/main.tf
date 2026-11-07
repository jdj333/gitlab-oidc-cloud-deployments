terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" { project = var.project_id }

variable "project_id" { type = string }
variable "gitlab_project_path" { type = string }
variable "gitlab_project_id" { type = string }
variable "gitlab_namespace_id" { type = string }
variable "deployment_buckets" {
  type = map(string)
  validation {
    condition     = toset(keys(var.deployment_buckets)) == toset(["dev", "prod"]) && length(toset(values(var.deployment_buckets))) == 2 && alltrue([for b in values(var.deployment_buckets) : can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", b))])
    error_message = "Provide two distinct, exact existing bucket names keyed dev and prod."
  }
}

module "trust" {
  source              = "../trust"
  gitlab_project_path = var.gitlab_project_path
  gitlab_project_id   = var.gitlab_project_id
  gitlab_namespace_id = var.gitlab_namespace_id
}

resource "google_project_service" "required" {
  for_each           = toset(["iam.googleapis.com", "iamcredentials.googleapis.com", "sts.googleapis.com", "storage.googleapis.com"])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Separate pools keep an additional provider in dev from authenticating to prod.
resource "google_iam_workload_identity_pool" "gitlab" {
  for_each                  = module.trust.branches
  workload_identity_pool_id = "gl-${var.gitlab_project_id}-${each.key}"
  display_name              = "GitLab ${each.key}"
  depends_on                = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "gitlab" {
  for_each                           = module.trust.branches
  workload_identity_pool_id          = google_iam_workload_identity_pool.gitlab[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = "gitlab"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.project_id" = "assertion.project_id"
  }
  attribute_condition = module.trust.gcp_conditions[each.key]
  oidc {
    issuer_uri        = module.trust.issuer
    allowed_audiences = [module.trust.gcp_audience]
  }
}

resource "google_service_account" "deploy" {
  for_each     = module.trust.branches
  account_id   = "gl-${var.gitlab_project_id}-${each.key}"
  display_name = "GitLab ${each.key} release uploader"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "federation" {
  for_each           = module.trust.branches
  service_account_id = google_service_account.deploy[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.gitlab[each.key].name}/attribute.project_id/${var.gitlab_project_id}"
}

resource "google_storage_bucket_iam_member" "release_upload" {
  for_each = var.deployment_buckets
  bucket   = each.value
  role     = "roles/storage.objectCreator"
  member   = "serviceAccount:${google_service_account.deploy[each.key].email}"
}

output "gitlab_variables" {
  value = { for env, identity in google_service_account.deploy : env => {
    GCP_PROJECT_ID        = var.project_id
    GCP_SERVICE_ACCOUNT   = identity.email
    GCP_WORKLOAD_PROVIDER = google_iam_workload_identity_pool_provider.gitlab[env].name
    GCP_BUCKET            = var.deployment_buckets[env]
  } }
}
