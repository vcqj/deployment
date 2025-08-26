#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

echo "This script will add two GitHub Actions workflows to repos and push a 'gha-workflows' branch."
read -rp "GitHub username: " GH_USER
read -srp "GitHub Personal Access Token (PAT): " GH_PAT
echo
echo "Tip: paste repo URLs like https://github.com/org/repo or github.com/org/repo or org/repo (leave empty to quit)."

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

normalize_repo() {
  local input="$1" out
  # strip scheme
  input="${input#http://}"
  input="${input#https://}"
  # strip leading github.com/
  input="${input#github.com/}"
  # strip trailing .git or /
  input="${input%.git}"
  input="${input%/}"
  out="$input"
  # basic sanity: must be org/repo
  if [[ "$out" != */* ]]; then
    return 1
  fi
  printf '%s\n' "$out"
}

ensure_git_identity() {
  if ! git config user.name >/dev/null; then
    git config user.name "$GH_USER"
  fi
  if ! git config user.email >/dev/null; then
    git config user.email "${GH_USER}@users.noreply.github.com"
  fi
}

create_workflows() {
  mkdir -p .github
  mkdir -p .github/workflows

  # --- pr-docker-build-check.yml ---
  cat > .github/workflows/pr-docker-build-check.yml <<'YAML'
name: PR Docker build check

on:
  pull_request:
    branches: [ "main" ]
    types: [opened, synchronize, reopened, ready_for_review]

permissions:
  contents: read

jobs:
  pr-docker-build:
    name: PR Docker build check  # name of status check
    runs-on: ubuntu-latest

    if: ${{ !github.event.pull_request.draft }} # skip drafts

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Cache Docker layers
        uses: actions/cache@v4
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ github.sha }}
          restore-keys: |
            ${{ runner.os }}-buildx-

      - name: Build image (no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile
          platforms: linux/amd64      # keep single arch for speed in PRs
          push: false                 # PR check: build only
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache-new,mode=max

      - name: Move cache
        run: |
          rm -rf /tmp/.buildx-cache
          mv /tmp/.buildx-cache-new /tmp/.buildx-cache
YAML

  # --- docker-build-push.yml ---
  cat > .github/workflows/docker-build-push.yml <<'YAML'
name: Build & Push Docker Image

on:
  push:
    branches: [ "main" ]
    tags: [ "v*" ]

permissions:
  contents: read
  packages: write   # needed for GHCR with GITHUB_TOKEN

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

  DOCKERFILE: Dockerfile
  CONTEXT: .
  # Set default platforms; change to linux/amd64 only if qemu is slow/not needed
  PLATFORMS: linux/amd64,linux/arm64

jobs:
  docker:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # ---- Login to registry ----
      # GHCR login (uses GITHUB_TOKEN)
      - name: Login to GHCR
        if: env.REGISTRY == 'ghcr.io'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # ---- Derive tags and labels ----
      - name: Docker meta
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch,enable=${{ github.ref == 'refs/heads/main' }}
            type=ref,event=tag
            type=sha,format=long
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      # ---- Cache layers (GitHub cache) ----
      - name: Cache Docker layers
        uses: actions/cache@v4
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ github.sha }}
          restore-keys: |
            ${{ runner.os }}-buildx-

      # ---- Build (and push only on push/tag) ----
      - name: Build & Push
        uses: docker/build-push-action@v6
        with:
          context: ${{ env.CONTEXT }}
          file: ${{ env.DOCKERFILE }}
          platforms: ${{ env.PLATFORMS }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache-new,mode=max

      # Workaround to move cache (keeps cache size bounded between runs)
      - name: Move cache
        run: |
          rm -rf /tmp/.buildx-cache
          mv /tmp/.buildx-cache-new /tmp/.buildx-cache

      # ---- Optional: output digest for traceability ----
      - name: Image digest
        if: github.event_name != 'pull_request'
        run: echo "DIGEST=${{ steps.meta.outputs.tags }} -> ${{ steps.buildx.outputs.digest || 'see action logs' }}"
YAML
}

while true; do
  echo
  read -rp "Repo (empty to quit): " INPUT || true
  [[ -z "${INPUT:-}" ]] && { echo "Done."; break; }

  if ! OWNER_REPO="$(normalize_repo "$INPUT")"; then
    echo "⚠️  Expected something like: github.com/org/repo or org/repo"
    continue
  fi

  OWNER="${OWNER_REPO%%/*}"
  REPO="${OWNER_REPO##*/}"

  CLONE_URL="https://${GH_USER}:${GH_PAT}@github.com/${OWNER}/${REPO}.git"
  echo "→ Working on ${OWNER}/${REPO} ..."
  cd "$WORKDIR"

  if ! git clone --quiet "$CLONE_URL"; then
    echo "❌ Could not clone https://github.com/${OWNER}/${REPO} (check permissions/token). Skipping."
    continue
  fi

  cd "$REPO"
  ensure_git_identity

  # Create/switch to branch
  BRANCH="gha-workflows"
  if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git checkout "$BRANCH"
  else
    git checkout -b "$BRANCH"
  fi

  # Create files
  create_workflows

  # Prove files exist
  echo "Created files:"
  ls -la .github/workflows || true

  # Stage, commit, push
  git add .github/workflows
  if git diff --cached --quiet; then
    echo "ℹ️  No changes to commit (files may already exist)."
  else
    git commit -m "Add CI: PR build check and build+push to GHCR"
  fi

  # Push (branch may be new or updated)
  git push -u origin "$BRANCH"
  echo "✅ Pushed branch '$BRANCH' to ${OWNER}/${REPO}"
done

