# Setup and verification

## 1. Create a GitLab execution project

Import or mirror the source from GitHub into a GitLab.com project you control. Record the exact **GitLab** project path, numeric project ID, and numeric namespace ID. The example identifiers are placeholders and do not identify a real deployment project.

Use the default GitLab ID token subject format. If the project has a customized subject, update the shared trust module and its tests together. Google subjects have a length limit; long namespace paths may require a deliberately customized shorter subject and corresponding policy changes.

Protect `main` and `develop`; prohibit direct pushes by untrusted users. Require review of pipeline, script, and Terraform changes. Restrict who can supply pipeline variables so predefined CI variables cannot be overridden. Disable debug tracing for credential jobs.

Use isolated, ephemeral Linux container runners with Bash and no attached cloud instance role or inherited credentials. Protect the production runner and production environments (`aws/prod`, `azure/prod`, `gcp/prod`). Restrict allowed deployers and configure required deployment approvals where your GitLab tier supports them. A manual job is not a substitute for a protected environment or approval policy.

## 2. Prepare dedicated storage

Choose only the clouds you need. The Terraform roots create federation and identity resources, not deployment storage.

| Cloud | Existing prerequisites |
| --- | --- |
| AWS | Two private S3 buckets in the selected commercial AWS region, Block Public Access enabled, SSE-S3 encryption. SSE-KMS requires separately reviewed key permissions and script changes. |
| Azure | Existing identity resource group and two distinct private blob containers. Disable shared-key access where compatible. Storage accounts and IDs must match the tfvars values. |
| Google Cloud | Existing project, two private buckets, uniform bucket-level access and public access prevention. The root enables IAM, IAM Credentials, STS, and Storage APIs. |

The roots reject identical dev and prod storage targets. Use separate accounts, subscriptions, or Google projects for stronger production isolation in a real platform; this compact demonstration uses separate identities and storage within each cloud root.

## 3. Bootstrap federation with an administrator

Authenticate locally through your organization's normal SSO or administrator workflow. Bootstrap needs permission to create identity providers/identities and grant the listed roles. Deployment identities intentionally cannot modify their own trust policy, bootstrap infrastructure, or Terraform state.

For one cloud:

```bash
cp terraform/aws/terraform.tfvars.example terraform/aws/terraform.tfvars
# Edit the copied file with your GitLab identifiers and existing target names.
terraform -chdir=terraform/aws init
terraform -chdir=terraform/aws plan -out=bootstrap.tfplan
# Review all IAM resources and targets before applying the saved plan.
terraform -chdir=terraform/aws apply bootstrap.tfplan
terraform -chdir=terraform/aws output -json gitlab_variables
```

Use `terraform/azure` or `terraform/gcp` for the other clouds. Terraform state and plans are ignored by Git. Before team use, configure encrypted remote state with locking and tightly restricted access. Do not put bootstrap state credentials into the deployment jobs.

An AWS account can already have the `gitlab.com` provider. Import it before planning instead of trying to create a duplicate:

```bash
terraform -chdir=terraform/aws import aws_iam_openid_connect_provider.gitlab arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/gitlab.com
```

Review its existing audiences before applying: this root owns its configured audience list. If other teams share the provider, manage the provider centrally and adapt this root to reference it rather than overwriting shared settings.

On Azure, the required resource providers must already be registered. This root disables automatic subscription-wide provider registration. Wait for identity and RBAC propagation before testing.

On Google Cloud, the WIF provider output uses the **numeric project number** in its resource name; use that output verbatim. Keep each environment pool dedicated to this trust configuration.

## 4. Configure GitLab variables

Add the values from `gitlab_variables` under Settings → CI/CD → Variables. These are identifiers and target names, not credentials. Mark them protected and use the exact environment scopes below. Create separate dev and prod rows for each key.

| Environment scopes | Keys |
| --- | --- |
| `aws/dev`, `aws/prod` | `AWS_ROLE_ARN`, `AWS_REGION`, `AWS_BUCKET` |
| `azure/dev`, `azure/prod` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_ACCOUNT_NAME`, `AZURE_CONTAINER` |
| `gcp/dev`, `gcp/prod` | `GCP_PROJECT_ID`, `GCP_WORKLOAD_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `GCP_BUCKET` |

Do not create `GITLAB_OIDC_TOKEN` yourself; GitLab generates it for the job. Remove stored AWS access keys, Azure client secrets/storage keys, and Google credential JSON from these jobs.

Set `ENABLE_AWS_DEPLOY`, `ENABLE_AZURE_DEPLOY`, or `ENABLE_GCP_DEPLOY` to `true` as **project variables with scope `*`**, only after that cloud is ready. They are used in `rules`, so they must not be environment-scoped. Leave unused providers disabled.

Lint `.gitlab-ci.yml` in GitLab's Pipeline Editor with the local include available. Run a protected `develop` push. Confirm the manifest reaches only development storage, inspect cloud audit logs, and then run a protected `main` push and manually start the desired production job.

AWS asks STS for 900-second credentials. Google service account impersonation requests 900 seconds. Azure determines its access-token lifetime; the job does not promise a 15-minute Azure token. GitLab job timeouts limit job duration, not the lifetime of already-issued cloud tokens.

## Live negative tests

These optional tests exchange a **real signed GitLab token** from an unauthorized branch. They do not upload, delete, or deploy anything. No live tests run until explicitly enabled.

1. Keep the configured cloud trust pointed at `main` and `develop` only.
2. Add these **unprotected, non-secret, scope `*`** variables, using production identity outputs:

| Cloud | Probe variables |
| --- | --- |
| AWS | `PROBE_AWS_ROLE_ARN`, `ENABLE_AWS_DENY_PROBE=true` |
| Azure | `PROBE_AZURE_TENANT_ID`, `PROBE_AZURE_CLIENT_ID`, `ENABLE_AZURE_DENY_PROBE=true` |
| Google Cloud | `PROBE_GCP_WORKLOAD_PROVIDER`, `ENABLE_GCP_DENY_PROBE=true` |

3. Create and push `oidc-deny-probe` from the current reviewed source. The `.gitlab/deny-probe.yml` include offers manual rejection-test jobs only on that branch.
4. Run the probes. Expected cloud authorization rejections pass. Network errors and unrelated HTTP errors fail. Recognized federation rejection codes can also result from policy misconfiguration, so establish a successful baseline with the exact target identity first. Receiving credentials also fails; credentials are discarded without being logged.
5. Retain the job result and provider audit event as evidence, then disable the probe flags and delete the test branch.

AWS checks for STS AccessDenied on AssumeRoleWithWebIdentity. Azure checks the subject-mismatch code AADSTS700213. Google checks attribute-condition rejection. Error formats can change; an unknown error fails closed and needs investigation. A rejection alone does not prove that an authorized branch works; first run an authorized positive test using the exact same target identity.

Do not loosen a trust policy merely to make a failed probe green. Use the local negative tests to identify the intended boundary, then inspect the cloud policy and GitLab claims without printing the complete token.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Deployment job is absent | Global enable flag, push pipeline, protected branch, exact branch name, no tag |
| Missing variable | Exact cloud/environment scope; protected variable availability |
| AWS AccessDenied | Provider ARN, audience, exact subject, project/namespace IDs, protected-ref and pipeline-source claims |
| Azure AADSTS700213 | Exact GitLab subject and matching managed identity; propagation delay |
| Azure blob authorization fails | Container scope, identity principal, RBAC propagation, storage networking, `--auth-mode login` |
| Google token exchange fails | Issuer/audience, numeric project number, attribute condition, GitLab ID values |
| Google impersonation fails | workloadIdentityUser binding, matching environment pool, IAM Credentials API |
| Google upload fails | objectCreator grant, correct bucket, unique destination, networking |
| Expired credentials | Job timeout and retry with a fresh job/token; never substitute a stored key |

## Teardown

Disable deployment and probe flags first. Review `terraform plan -destroy` separately in each configured root, then remove its federation identities and grants when ready. Dedicated deployment storage is outside these roots and remains intact. Removing trust prevents new exchanges; already-issued cloud credentials can remain valid until expiry or provider-specific revocation takes effect.
