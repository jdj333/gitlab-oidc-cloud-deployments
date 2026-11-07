#!/usr/bin/env bash
set +x
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
require AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_ACCOUNT_NAME AZURE_CONTAINER
export AZURE_CONFIG_DIR="$AUTH_DIR/azure"
# The CLI requires the assertion as an argument. Use an isolated, ephemeral runner.
az login --service-principal --username "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" \
  --federated-token "$GITLAB_OIDC_TOKEN" --allow-no-subscriptions --output none
unset GITLAB_OIDC_TOKEN
az storage blob upload --auth-mode login --account-name "$AZURE_ACCOUNT_NAME" \
  --container-name "$AZURE_CONTAINER" --name "$RELEASE_KEY" --file "$AUTH_DIR/release.json" \
  --overwrite false --only-show-errors --output none
printf 'Uploaded release manifest to Azure container %s/%s\n' "$AZURE_CONTAINER" "$RELEASE_KEY"
