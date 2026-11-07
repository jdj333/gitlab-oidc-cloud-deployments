mock_provider "azurerm" {}

variables {
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "rg-gitlab-identities"
  location            = "westus2"
  gitlab_project_path = "example-platform/gitlab-oidc-cloud-deployments"
  gitlab_project_id   = "12345678"
  gitlab_namespace_id = "123456"
  deployment_storage = {
    dev = {
      account_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-releases/providers/Microsoft.Storage/storageAccounts/examplereleasesdev"
      account_name = "examplereleasesdev"
      container    = "releases-dev"
    }
    prod = {
      account_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-releases/providers/Microsoft.Storage/storageAccounts/examplereleasesprod"
      account_name = "examplereleasesprod"
      container    = "releases-prod"
    }
  }
}

run "scoped_identities" {
  command = apply
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      azurerm_federated_identity_credential.gitlab[env].subject == module.trust.subjects[env] &&
      azurerm_federated_identity_credential.gitlab[env].issuer == module.trust.issuer &&
      toset(azurerm_federated_identity_credential.gitlab[env].audience) == toset(["api://AzureADTokenExchange"]) &&
      azurerm_federated_identity_credential.gitlab[env].parent_id == azurerm_user_assigned_identity.deploy[env].id
    ])
    error_message = "Federation must bind the exact subject to its environment identity."
  }
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      azurerm_role_assignment.release_upload[env].role_definition_name == "Storage Blob Data Contributor" &&
      azurerm_role_assignment.release_upload[env].scope == "${var.deployment_storage[env].account_id}/blobServices/default/containers/${var.deployment_storage[env].container}" &&
      azurerm_role_assignment.release_upload[env].principal_id == azurerm_user_assigned_identity.deploy[env].principal_id
    ])
    error_message = "No subscription-level grants or cross-environment principals."
  }
}
run "reject_shared_storage" {
  command = plan
  variables {
    deployment_storage = {
      dev  = { account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-releases/providers/Microsoft.Storage/storageAccounts/sharedstorage", account_name = "sharedstorage", container = "shared" }
      prod = { account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-releases/providers/Microsoft.Storage/storageAccounts/sharedstorage", account_name = "sharedstorage", container = "shared" }
    }
  }
  expect_failures = [var.deployment_storage]
}

# Realistic computed IDs keep mocked downstream resource validation meaningful.
override_resource {
  target = azurerm_user_assigned_identity.deploy["dev"]
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-gitlab-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/gitlab-12345678-dev"
    principal_id = "00000000-0000-0000-0000-000000000001"
    client_id    = "10000000-0000-0000-0000-000000000001"
    tenant_id    = "20000000-0000-0000-0000-000000000000"
  }
}
override_resource {
  target = azurerm_user_assigned_identity.deploy["prod"]
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-gitlab-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/gitlab-12345678-prod"
    principal_id = "00000000-0000-0000-0000-000000000002"
    client_id    = "10000000-0000-0000-0000-000000000002"
    tenant_id    = "20000000-0000-0000-0000-000000000000"
  }
}
