terraform { required_version = ">= 1.9, < 2.0" }
module "trust" {
  source              = "../../terraform/trust"
  gitlab_project_path = "example-platform/gitlab-oidc-cloud-deployments"
  gitlab_project_id   = "12345678"
  gitlab_namespace_id = "123456"
}
output "trust" { value = module.trust }
