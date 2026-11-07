# GitLab OIDC cloud deployments

[![Validation](https://github.com/jdj333/gitlab-oidc-cloud-deployments/actions/workflows/validate.yml/badge.svg)](https://github.com/jdj333/gitlab-oidc-cloud-deployments/actions/workflows/validate.yml)

A platform engineering reference implementation for deploying from **GitLab CI/CD to AWS, Azure, and Google Cloud using temporary credentials**. No stored AWS access keys, Azure client secrets, or Google service account keys.

Each job exchanges a GitLab ID token for a cloud identity, then uploads a release manifest into dedicated environment storage. The example demonstrates the complete authentication and authorization path without granting infrastructure administration to the deployment job.

**GitHub hosts the source and runs offline validation. GitLab runs the deployment pipeline after you import or mirror this repository. All cloud deployment jobs are disabled by default.**

## What this demonstrates

| Capability | Implementation |
| --- | --- |
| Modern GitLab OIDC | Job-specific `id_tokens`, explicit audiences, no legacy job JWTs |
| Restricted federation | Exact project and branch subjects; additional claims where supported |
| Environment isolation | Separate dev/prod identities, storage targets, and deployment locks |
| Temporary credentials | AWS STS, Azure federated login, Google workload federation |
| CI/CD governance | Protected branch gates, manual production jobs, cloud-side authorization |
| Negative security testing | Terraform-generated trust predicates, mocked resources, optional live rejection probes |
| Operational readiness | Setup guide, variable table, threat model, troubleshooting, provider lock files |

## Access model

| Environment | Branch | Pipeline | Deployment |
| --- | --- | --- | --- |
| Development | protected `develop` | Push | Automatic after checks, if enabled |
| Production | protected `main` | Push | Manual after checks, if enabled |
| Feature branches, tags, forks, merge requests | Other identities | Validation | No deployment access through the intended trust policy |

| Cloud | Token audience | Identity | Data permissions |
| --- | --- | --- | --- |
| AWS | `sts.amazonaws.com` | IAM role per environment | `s3:PutObject` on that bucket's `releases/*` |
| Azure | `api://AzureADTokenExchange` | Managed identity per environment | Storage Blob Data Contributor on one container |
| Google Cloud | `https://gitlab.com` | WIF pool and service account per environment | `roles/storage.objectCreator` on one bucket |

Azure's built-in data role also permits reading and deleting blobs within that container. It grants no subscription administration. AWS can replace objects within its upload prefix; Google objectCreator cannot replace or delete existing objects. The scripts use a pipeline/job-specific object name.

## Try the checks without cloud credentials

Prerequisites: Terraform 1.9+, Python 3.12+, Bash. The workflow uses Terraform 1.9.8 and committed provider lock files.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
bash scripts/test.sh

for cloud in aws azure gcp; do
  terraform -chdir=terraform/$cloud init -backend=false -input=false -lockfile=readonly
  terraform -chdir=terraform/$cloud validate
  terraform -chdir=terraform/$cloud test
 done
```

The policy test fixture contains **no cloud resources or providers**. Its local `apply` only renders outputs. Python tests evaluate those exact output predicates. Terraform cloud tests use **mock providers** to check resource wiring and reject shared environment storage. Neither command creates cloud infrastructure.

These are policy and configuration tests, not proof of a successful cloud token exchange. See [live negative tests](docs/setup.md#live-negative-tests) for a real signed-token check.

## Deploy the example

Follow [the setup guide](docs/setup.md). Start with one cloud and development. It covers storage prerequisites, bootstrap permissions, Terraform plans, GitLab variable scopes, branch protections, and the optional real unauthorized-branch probes.

The deployment manifest contains only commit, project, pipeline, job, and environment identifiers. Auth files are created outside the checkout with restrictive permissions and removed when the script exits. No token is a job artifact.

## Where to read the code

| Path | Purpose |
| --- | --- |
| [`.gitlab-ci.yml`](.gitlab-ci.yml) | Tests plus six gated deployment jobs |
| [`terraform/trust`](terraform/trust) | Shared trust predicates consumed by tests and all three cloud roots |
| [`terraform/aws`](terraform/aws) | OIDC provider, environment roles, S3 upload permissions |
| [`terraform/azure`](terraform/azure) | Managed identities, federated credentials, container role assignments |
| [`terraform/gcp`](terraform/gcp) | Environment pools, OIDC providers, impersonation and bucket permissions |
| [`scripts`](scripts) | Temporary login, upload, cleanup, real denial probe |
| [`tests`](tests) | Allowed and denied claim cases, CI gates, shell guards, error classification |
| [Threat model](docs/security.md) | Guarantees, provider differences, and remaining risks |
| [Design notes](docs/design.md) | Tradeoffs and interview discussion points |

## Boundaries

This configuration targets **GitLab.com** with its default subject format. AWS's additional GitLab condition keys are not portable to self-managed issuers. Azure's basic federated credential checks issuer, audience, and subject; it does not enforce arbitrary GitLab claims. GitLab protections therefore matter, and pipeline rules alone are not a security boundary. The [threat model](docs/security.md) explains these limits.

Created by [James Jenkins](https://github.com/jdj333) as a DevOps and platform engineering portfolio project.
