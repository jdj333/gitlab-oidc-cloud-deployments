terraform {
  required_version = ">= 1.9, < 2.0"
}

variable "gitlab_project_path" {
  type        = string
  description = "Exact GitLab namespace/project path; this is not the GitHub mirror path."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$", var.gitlab_project_path))
    error_message = "Use an exact namespace/project path without wildcards."
  }
}

variable "gitlab_project_id" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.gitlab_project_id))
    error_message = "Supply the numeric GitLab project ID."
  }
}

variable "gitlab_namespace_id" {
  type = string
  validation {
    condition     = can(regex("^[1-9][0-9]*$", var.gitlab_namespace_id))
    error_message = "Supply the numeric GitLab namespace ID."
  }
}

locals {
  issuer   = "https://gitlab.com"
  branches = { dev = "develop", prod = "main" }
  subjects = { for env, branch in local.branches : env => "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch}" }
}

output "branches" { value = local.branches }
output "subjects" { value = local.subjects }
output "issuer" { value = local.issuer }

# These objects are consumed directly by the cloud resources and offline tests.
# Additional AWS GitLab claim keys below are supported for GitLab.com only.
output "aws_conditions" {
  value = { for env, subject in local.subjects : env => {
    StringEquals = {
      "gitlab.com:aud"             = "sts.amazonaws.com"
      "gitlab.com:sub"             = subject
      "gitlab.com:project_id"      = var.gitlab_project_id
      "gitlab.com:namespace_id"    = var.gitlab_namespace_id
      "gitlab.com:ref_protected"   = "true"
      "gitlab.com:pipeline_source" = "push"
    }
  } }
}

output "azure_federation" {
  value = { for env, subject in local.subjects : env => {
    issuer   = local.issuer
    subject  = subject
    audience = ["api://AzureADTokenExchange"]
  } }
}

output "gcp_conditions" {
  value = { for env, subject in local.subjects : env => join(" && ", [
    "assertion.namespace_id == '${var.gitlab_namespace_id}'",
    "assertion.project_id == '${var.gitlab_project_id}'",
    "assertion.sub == '${subject}'",
    "assertion.ref_protected == 'true'",
    "assertion.pipeline_source == 'push'"
  ]) }
}

output "gcp_audience" { value = "https://gitlab.com" }
