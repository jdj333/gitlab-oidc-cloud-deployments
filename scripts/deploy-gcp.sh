#!/usr/bin/env bash
set +x
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
require GCP_WORKLOAD_PROVIDER GCP_SERVICE_ACCOUNT GCP_PROJECT_ID GCP_BUCKET
export CLOUDSDK_CONFIG="$AUTH_DIR/gcloud"
unset CLOUDSDK_AUTH_ACCESS_TOKEN CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
# The provider name uses a numeric Google Cloud project NUMBER, not project ID.
gcloud iam workload-identity-pools create-cred-config "$GCP_WORKLOAD_PROVIDER" \
  --service-account="$GCP_SERVICE_ACCOUNT" --service-account-token-lifetime-seconds=900 \
  --credential-source-file="$AUTH_DIR/oidc.token" --output-file="$AUTH_DIR/credentials.json" --quiet
gcloud auth login --cred-file="$AUTH_DIR/credentials.json" --quiet
unset GITLAB_OIDC_TOKEN
gcloud storage cp "$AUTH_DIR/release.json" "gs://$GCP_BUCKET/$RELEASE_KEY" --project="$GCP_PROJECT_ID" --quiet
printf 'Uploaded release manifest to gs://%s/%s\n' "$GCP_BUCKET" "$RELEASE_KEY"
