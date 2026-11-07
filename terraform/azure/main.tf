terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
}

variable "subscription_id" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "gitlab_project_path" { type = string }
variable "gitlab_project_id" { type = string }
variable "gitlab_namespace_id" { type = string }
variable "deployment_storage" {
  description = "Existing storage accounts and distinct dedicated containers, keyed dev and prod."
  type = map(object({
    account_id   = string
    account_name = string
    container    = string
  }))
  validation {
    condition = toset(keys(var.deployment_storage)) == toset(["dev", "prod"]) && length(toset([
      for s in values(var.deployment_storage) : "${s.account_id}/${s.container}"
      ])) == 2 && alltrue([for s in values(var.deployment_storage) :
      can(regex("^[a-z0-9]{3,24}$", s.account_name)) && can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", s.container)) && endswith(s.account_id, "/storageAccounts/${s.account_name}")
    ])
    error_message = "Provide dev and prod with distinct container scopes and matching exact account IDs/names."
  }
}

module "trust" {
  source              = "../trust"
  gitlab_project_path = var.gitlab_project_path
  gitlab_project_id   = var.gitlab_project_id
  gitlab_namespace_id = var.gitlab_namespace_id
}

resource "azurerm_user_assigned_identity" "deploy" {
  for_each            = module.trust.branches
  name                = "gitlab-${var.gitlab_project_id}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "gitlab" {
  for_each            = module.trust.azure_federation
  name                = "gitlab-${each.key}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.deploy[each.key].id
  issuer              = each.value.issuer
  subject             = each.value.subject
  audience            = each.value.audience
}

# Container data access only: never Contributor or Owner at subscription scope.
# This built-in role includes read/write/delete within that one container.
resource "azurerm_role_assignment" "release_upload" {
  for_each             = var.deployment_storage
  scope                = "${each.value.account_id}/blobServices/default/containers/${each.value.container}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

output "gitlab_variables" {
  value = { for env, identity in azurerm_user_assigned_identity.deploy : env => {
    AZURE_CLIENT_ID    = identity.client_id
    AZURE_TENANT_ID    = identity.tenant_id
    AZURE_ACCOUNT_NAME = var.deployment_storage[env].account_name
    AZURE_CONTAINER    = var.deployment_storage[env].container
  } }
}
