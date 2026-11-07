#!/usr/bin/env bash
# Sourced only by the deployment scripts. No token is printed or persisted as an artifact.
set +x
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
require() { local key; for key in "$@"; do [[ -n "${!key:-}" ]] || fail "Missing required variable: $key"; done; }
require DEPLOY_ENV CI_COMMIT_BRANCH CI_COMMIT_SHA CI_PROJECT_ID CI_PIPELINE_ID CI_JOB_ID GITLAB_OIDC_TOKEN
[[ "${CI_DEBUG_TRACE:-false}" != "true" ]] || fail "Debug tracing is forbidden for credential jobs."
[[ "${CI_PIPELINE_SOURCE:-}" == "push" ]] || fail "Only push pipelines may deploy."
[[ "${CI_COMMIT_REF_PROTECTED:-}" == "true" ]] || fail "Deployment requires a protected branch."
[[ -z "${CI_COMMIT_TAG:-}" ]] || fail "Tag deployments are not allowed."
case "${DEPLOY_ENV}:${CI_COMMIT_BRANCH}" in
  dev:develop|prod:main) ;;
  *) fail "Branch is not authorized for this environment." ;;
esac
[[ "$CI_COMMIT_SHA" =~ ^[a-f0-9]{40,64}$ ]] || fail "Invalid commit SHA."
for key in CI_PROJECT_ID CI_PIPELINE_ID CI_JOB_ID; do
  [[ "${!key}" =~ ^[0-9]+$ ]] || fail "Invalid numeric CI identifier."
done
# Reject injected static credentials; never silently fall back to runner credentials.
for key in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AZURE_CLIENT_SECRET AZURE_STORAGE_KEY AZURE_STORAGE_SAS_TOKEN AZURE_STORAGE_CONNECTION_STRING GOOGLE_APPLICATION_CREDENTIALS; do
  [[ -z "${!key:-}" ]] || fail "Remove static or ambient credential variable: $key"
done
umask 077
AUTH_DIR=$(mktemp -d)
cleanup() { rm -rf -- "$AUTH_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s' "$GITLAB_OIDC_TOKEN" > "$AUTH_DIR/oidc.token"
export RELEASE_KEY="releases/${CI_PIPELINE_ID}/${CI_JOB_ID}.json"
printf '{"commit":"%s","project_id":"%s","pipeline_id":"%s","job_id":"%s","environment":"%s"}\n' \
  "$CI_COMMIT_SHA" "$CI_PROJECT_ID" "$CI_PIPELINE_ID" "$CI_JOB_ID" "$DEPLOY_ENV" > "$AUTH_DIR/release.json"
