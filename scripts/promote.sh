#!/usr/bin/env bash
# promote.sh — Manually promote a specific image tag from dev to production.
#
# This script exists for ad-hoc promotions or local demos.
# In normal CI/CD flow the Harness pipeline owns this update automatically.
#
# Usage:
#   ./scripts/promote.sh <image-tag>
#
# Example:
#   ./scripts/promote.sh 42

set -euo pipefail

IMAGE_TAG="${1:-}"

if [[ -z "${IMAGE_TAG}" ]]; then
  echo "Usage: $0 <image-tag>" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD_KUSTOMIZATION="${REPO_ROOT}/gitops/overlays/production/kustomization.yaml"
PROD_ENV_PATCH="${REPO_ROOT}/gitops/overlays/production/env-patch.yaml"

echo "→ Promoting gitops-demo:${IMAGE_TAG} to production"

# Update the image tag in the production kustomization
cd "${REPO_ROOT}/gitops/overlays/production"
kustomize edit set image "docker.io/your-org/gitops-demo:${IMAGE_TAG}"

# Also keep APP_VERSION env var in sync so the app reports the right version
sed -i.bak "s/value: \".*\"  # Kept in sync/value: \"${IMAGE_TAG}\"  # Kept in sync/" \
  "${PROD_ENV_PATCH}" && rm -f "${PROD_ENV_PATCH}.bak"

echo "→ Staging changes"
git -C "${REPO_ROOT}" add \
  gitops/overlays/production/kustomization.yaml \
  gitops/overlays/production/env-patch.yaml

echo "→ Committing"
git -C "${REPO_ROOT}" commit -m "chore(prod): promote gitops-demo to ${IMAGE_TAG}"

echo "→ Pushing"
git -C "${REPO_ROOT}" push origin HEAD

echo ""
echo "Done. Argo CD will detect the change and sync production automatically."
echo "Monitor the sync at: Harness → GitOps → Applications → gitops-demo-production"
