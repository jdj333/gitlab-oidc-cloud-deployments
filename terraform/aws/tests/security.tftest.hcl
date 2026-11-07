mock_provider "aws" {}

variables {
  region              = "us-west-2"
  gitlab_project_path = "example-platform/gitlab-oidc-cloud-deployments"
  gitlab_project_id   = "12345678"
  gitlab_namespace_id = "123456"
  deployment_buckets = {
    dev  = "example-gitlab-releases-dev"
    prod = "example-gitlab-releases-prod"
  }
}

run "scoped_roles" {
  command = apply
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      jsondecode(aws_iam_role.deploy[env].assume_role_policy).Statement[0].Condition == module.trust.aws_conditions[env]
    ])
    error_message = "Cloud resources must consume the tested trust conditions without widening them."
  }
  assert {
    condition = alltrue([for env in ["dev", "prod"] :
      jsondecode(aws_iam_role.deploy[env].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.deploy[env].assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.gitlab.arn &&
      jsondecode(aws_iam_role_policy.release_upload[env].policy).Statement[0].Action == ["s3:PutObject"] &&
      jsondecode(aws_iam_role_policy.release_upload[env].policy).Statement[0].Resource == ["arn:aws:s3:::${var.deployment_buckets[env]}/releases/*"]
    ])
    error_message = "Only the GitLab provider and each environment's upload prefix may be authorized."
  }
}
run "reject_shared_storage" {
  command = plan
  variables { deployment_buckets = { dev = "shared-bucket", prod = "shared-bucket" } }
  expect_failures = [var.deployment_buckets]
}
