terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" { region = var.region }

variable "region" { type = string }
variable "gitlab_project_path" { type = string }
variable "gitlab_project_id" { type = string }
variable "gitlab_namespace_id" { type = string }
variable "deployment_buckets" {
  description = "Existing dedicated S3 bucket names for dev and prod (SSE-S3 encryption)."
  type        = map(string)
  validation {
    condition     = toset(keys(var.deployment_buckets)) == toset(["dev", "prod"]) && length(toset(values(var.deployment_buckets))) == 2 && alltrue([for b in values(var.deployment_buckets) : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "Provide two distinct, exact S3 bucket names keyed dev and prod."
  }
}

module "trust" {
  source              = "../trust"
  gitlab_project_path = var.gitlab_project_path
  gitlab_project_id   = var.gitlab_project_id
  gitlab_namespace_id = var.gitlab_namespace_id
}

# Import an existing GitLab.com provider into this address if the account has one.
# IAM retrieves the certificate chain for supported trusted root CAs.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url            = module.trust.issuer
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "deploy" {
  for_each             = module.trust.branches
  name                 = "gitlab-${var.gitlab_project_id}-${each.key}-deploy"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.gitlab.arn }
      Condition = module.trust.aws_conditions[each.key]
    }]
  })
}

resource "aws_iam_role_policy" "release_upload" {
  for_each = module.trust.branches
  name     = "release-upload"
  role     = aws_iam_role.deploy[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = ["arn:aws:s3:::${var.deployment_buckets[each.key]}/releases/*"]
    }]
  })
}

output "gitlab_variables" {
  value = { for env, role in aws_iam_role.deploy : env => {
    AWS_ROLE_ARN = role.arn
    AWS_REGION   = var.region
    AWS_BUCKET   = var.deployment_buckets[env]
  } }
}
