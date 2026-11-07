#!/usr/bin/env bash
set +x
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
require AWS_ROLE_ARN AWS_REGION AWS_BUCKET
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_WEB_IDENTITY_TOKEN_FILE AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_CREDENTIALS_FULL_URI
export AWS_EC2_METADATA_DISABLED=true AWS_PAGER=""
export AWS_CONFIG_FILE="$AUTH_DIR/aws-config" AWS_SHARED_CREDENTIALS_FILE="$AUTH_DIR/aws-credentials"
: > "$AWS_CONFIG_FILE"
: > "$AWS_SHARED_CREDENTIALS_FILE"
# Explicit 15-minute STS exchange. Capture output without logging credentials.
credentials=$(aws sts assume-role-with-web-identity \
  --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "gitlab-${CI_PROJECT_ID}-${CI_JOB_ID}" \
  --web-identity-token "file://$AUTH_DIR/oidc.token" \
  --duration-seconds 900 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
IFS=$'\t' read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$credentials"
require AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset credentials GITLAB_OIDC_TOKEN
aws sts get-caller-identity --query Arn --output text
aws s3api put-object --bucket "$AWS_BUCKET" --key "$RELEASE_KEY" \
  --body "$AUTH_DIR/release.json" --server-side-encryption AES256 --output json >/dev/null
printf 'Uploaded release manifest to s3://%s/%s\n' "$AWS_BUCKET" "$RELEASE_KEY"
