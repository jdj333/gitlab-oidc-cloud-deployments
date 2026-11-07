#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
terraform_bin="${TERRAFORM_BIN:-terraform}"
"$terraform_bin" fmt -check -recursive terraform tests/fixtures
# Provider-free fixture: apply creates only local output state, never cloud resources.
"$terraform_bin" -chdir=tests/fixtures init -backend=false -input=false -no-color >/dev/null
"$terraform_bin" -chdir=tests/fixtures apply -auto-approve -input=false -no-color >/dev/null
mkdir -p .test-output
"$terraform_bin" -chdir=tests/fixtures output -json > .test-output/trust.json
python3 -m unittest discover -s tests -v
for file in scripts/*.sh; do bash -n "$file"; done
