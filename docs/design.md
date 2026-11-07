# Design decisions

## Use OIDC instead of stored keys

The runner receives a job-specific assertion. The cloud decides whether that asserted identity may act, then issues temporary credentials. There is no deployment password to rotate in GitLab. The main operational work moves to trust policy review, branch governance and auditing.

## Keep bootstrap separate from application deployment

Creating identities and assigning IAM permissions requires authority that an uploader should never have. The Terraform roots are administrator-run bootstrap examples. Pipeline jobs upload only release manifests. This avoids a circular design where a job can rewrite the policy that is meant to constrain it.

## Exercise a real, bounded operation

A login-only demonstration can hide missing data permissions. Uploading a small manifest tests both federation and target access. Unique pipeline/job keys keep retry behavior clear. The narrow example does not require a cluster, a production service, or expensive infrastructure.

## Share policy generation with the tests

The provider-free trust module produces exact AWS conditions, Azure federation fields and Google CEL conditions. Cloud roots consume those outputs. Tests render the same module, exercise negative identities, and verify the resource bindings with provider mocks. This reduces drift between a policy described in a test and the one Terraform deploys.

## Keep provider differences visible

The implementation does not claim all clouds have identical condition support or storage permissions. Azure's basic FIC has a smaller claim surface. Its built-in blob role is broader than the AWS upload-only policy. The threat model makes those tradeoffs explicit so reviewers can decide where custom roles or customized subjects are warranted.

## Separate policy correctness from integration evidence

A local model cannot prove JWT signing-key discovery or live IAM behavior. The optional denial jobs use real GitLab tokens and distinguish authorization rejection from configuration or network failure. Positive upload tests establish that the allowed path also works.

## Discussion points for a platform engineering interview

1. Why a feature branch must be rejected by cloud trust even if pipeline YAML is changed.
2. Why short-lived credentials still require runner isolation and log hygiene.
3. Why a manual job is not proof of human approval at the cloud API.
4. How separate accounts/projects, protected environments, reviewed templates, custom Azure roles and workload-specific targets could strengthen this design.
5. How to migrate an existing key-based deployment: establish federation, test allow/deny behavior, switch one environment, remove old variables, revoke old keys, and observe audit logs.

For a production platform, pin runner images by digest after verifying them in your approved registry, enforce reviewed CI components, maintain dependency updates, and replace the storage example with exactly scoped application deployment permissions. Keep bootstrap privileges and deployment privileges separate.
