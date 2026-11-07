# Trust boundaries and security model

## What the cloud enforces

The provider verifies the GitLab signature, issuer, audience and token validity. The configuration then narrows which GitLab identity can obtain cloud credentials. Issuer discovery and signing keys stay at GitLab.com; this repository does not publish its own key endpoint.

| Claim/control | AWS configuration | Azure configuration | Google configuration |
| --- | --- | --- | --- |
| Exact issuer and audience | OIDC provider and StringEquals audience | Federated credential | OIDC provider |
| Exact project path and branch/type | StringEquals subject | Exact subject | Attribute condition |
| Numeric project and namespace IDs | Additional GitLab.com condition keys | Not checked by this basic FIC | Attribute condition |
| Protected ref | StringEquals `true` | GitLab controls and script guard | Attribute condition |
| Push pipeline | StringEquals `push` | GitLab controls and script guard | Attribute condition |
| Manual production approval | GitLab configuration | GitLab configuration | GitLab configuration |

The subject includes `ref_type:branch`, so a tag named `main` is a different identity. A fork has a different project subject. Development and production trust different branch subjects and receive separate identities.

Azure FIC equality does not independently enforce project ID, protected-ref status, or pipeline source in the default subject used here. A recreated project at the same path could match the Azure subject. Revoke federation before renaming, transferring, or deleting its project. A stricter deployment can use a reviewed custom GitLab subject containing stable IDs and additional claims, then update the FIC, shared module and tests together.

## What pipeline rules cannot guarantee

A person who can modify trusted branch code can change pipeline rules or invoke a token exchange directly. Rules, script guards, enable flags, and protected variables are defense in depth. Cloud identity policies remain the authorization boundary.

None of these policies proves that a particular script, filename, GitLab environment, human approval, or pipeline stage ran. Any job with the accepted cloud identity claims can attempt authentication. Protect trusted branches, CI definitions, deployment environments, runner configuration and bootstrap credentials. Review changes to pipeline includes as code. The cloud does not enforce GitLab's manual production click.

## Credential handling

Each cloud job requests only its own audience. No ID tokens are requested by validation jobs. AWS static credential variables are rejected and metadata/container credential fallbacks are disabled. Azure and Google use fresh temporary configuration directories. Generated files use `umask 077`, live outside the checkout, and are cleaned on normal exit, errors, INT and TERM.

SIGKILL or runner loss can bypass shell cleanup, so runners must be ephemeral. Azure CLI receives the assertion as an argument because its login command requires that form; an isolated runner prevents another tenant reading the process arguments. Do not enable runner debug/service tracing or capture process environments. Job logs may contain non-secret identity and target names.

AWS credentials are explicitly exchanged for 900 seconds; the role permits at most one hour for other accepted callers. Google requests 900-second service account tokens in the deployment script, but that request is not an IAM-enforced universal maximum. Azure token expiry is provider-controlled. Removing a local file or ending a job does not revoke an issued bearer token.

## Permission boundaries

AWS only grants PutObject for an environment's `releases/*`; overwriting an existing object there is possible. Azure's container-scoped built-in role includes read, write and delete. Google objectCreator permits creation and cannot replace or delete objects. No deployment identity receives IAM administration or bootstrap state access.

These grants do not cancel other permissions assigned outside this repository. Audit existing IAM bindings, resource policies, organizational policies and network access. Encryption, storage public access controls, retention, logging and lifecycle policies belong to the preexisting storage setup.

Each Google environment gets its own pool because a pool-level principal binding can match identities from any provider added to that pool. Restrict who may create or modify providers and impersonation grants.

## Test evidence and limits

- Python tests evaluate Terraform-rendered predicates, including unauthorized branches, tags, forks, audiences and missing claims. The CEL evaluator deliberately accepts only this repository's equality conjunction grammar. It is not Google's CEL engine or a JWT verifier.
- Terraform tests mock cloud providers and verify that resources consume those predicates and environment-scoped permissions. This validates configuration, not cloud-side acceptance.
- CI-rule and shell-guard tests check scheduling and early rejection. Tests never pass synthetic JWTs off as valid signed assertions.
- Opt-in live probes exercise real token endpoints. Only recognized policy denial errors count as a pass. They never attempt a data-plane deployment.

Run a positive deployment and the live negative probes in a sandbox before relying on the configuration for real workloads. Record cloud audit events alongside pipeline results. No live cloud setup or deployment is implied by a green GitHub validation badge.

## Official references

- [GitLab ID tokens and claim reference](https://docs.gitlab.com/ci/secrets/id_token_authentication/)
- [GitLab AWS federation](https://docs.gitlab.com/ci/cloud_services/aws/)
- [GitLab Azure federation](https://docs.gitlab.com/ci/cloud_services/azure/)
- [Google deployment pipeline federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [Azure CLI data authorization](https://learn.microsoft.com/en-us/azure/storage/blobs/authorize-data-operations-cli)
- [Terraform Azure federated identity credential](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential)
- [Terraform Google workload identity provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider)
