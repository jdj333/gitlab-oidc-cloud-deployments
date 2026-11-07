mock_provider "google" {}

variables {
  project_id          = "example-platform-sandbox"
  gitlab_project_path = "example-platform/gitlab-oidc-cloud-deployments"
  gitlab_project_id   = "12345678"
  gitlab_namespace_id = "123456"
  deployment_buckets = {
    dev  = "example-gitlab-releases-dev"
    prod = "example-gitlab-releases-prod"
  }
}

run "scoped_federation" {
  command = apply
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      google_iam_workload_identity_pool_provider.gitlab[env].attribute_condition == module.trust.gcp_conditions[env] &&
      google_iam_workload_identity_pool_provider.gitlab[env].oidc[0].issuer_uri == module.trust.issuer &&
      toset(google_iam_workload_identity_pool_provider.gitlab[env].oidc[0].allowed_audiences) == toset([module.trust.gcp_audience]) &&
      google_iam_workload_identity_pool_provider.gitlab[env].workload_identity_pool_id == google_iam_workload_identity_pool.gitlab[env].workload_identity_pool_id
    ])
    error_message = "Provider must enforce the tested condition inside its environment pool."
  }
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      google_storage_bucket_iam_member.release_upload[env].bucket == var.deployment_buckets[env] &&
      google_storage_bucket_iam_member.release_upload[env].role == "roles/storage.objectCreator" &&
      google_storage_bucket_iam_member.release_upload[env].member == "serviceAccount:${google_service_account.deploy[env].email}" &&
      google_service_account_iam_member.federation[env].role == "roles/iam.workloadIdentityUser" &&
      google_service_account_iam_member.federation[env].member == "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.gitlab[env].name}/attribute.project_id/${var.gitlab_project_id}"
    ])
    error_message = "Only this environment pool may impersonate its bucket-scoped uploader."
  }
}
run "reject_shared_storage" {
  command = plan
  variables { deployment_buckets = { dev = "shared-bucket", prod = "shared-bucket" } }
  expect_failures = [var.deployment_buckets]
}

# Realistic computed IDs keep mocked downstream resource validation meaningful.
override_resource {
  target = google_service_account.deploy["dev"]
  values = {
    name  = "projects/example-platform-sandbox/serviceAccounts/gl-12345678-dev@example-platform-sandbox.iam.gserviceaccount.com"
    email = "gl-12345678-dev@example-platform-sandbox.iam.gserviceaccount.com"
  }
}
override_resource {
  target = google_iam_workload_identity_pool.gitlab["dev"]
  values = {
    name = "projects/123456789012/locations/global/workloadIdentityPools/gl-12345678-dev"
  }
}
override_resource {
  target = google_service_account.deploy["prod"]
  values = {
    name  = "projects/example-platform-sandbox/serviceAccounts/gl-12345678-prod@example-platform-sandbox.iam.gserviceaccount.com"
    email = "gl-12345678-prod@example-platform-sandbox.iam.gserviceaccount.com"
  }
}
override_resource {
  target = google_iam_workload_identity_pool.gitlab["prod"]
  values = {
    name = "projects/123456789012/locations/global/workloadIdentityPools/gl-12345678-prod"
  }
}
