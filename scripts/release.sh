#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

YES=0
DRY_RUN=0
NEXT_VERSION_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --next-version) NEXT_VERSION_ONLY=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: bash scripts/release.sh [--yes|-y] [--dry-run] [--next-version]" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_runnable() {
  require_cmd "$1"
  if ! "$1" version &>/dev/null && ! "$1" --version &>/dev/null; then
    echo "$1 is on PATH but failed to run." >&2
    if [[ "$1" == "gh" ]]; then
      echo "If you use asdf, add 'github-cli <version>' to .tool-versions in the repo root." >&2
    fi
    exit 1
  fi
}

source "$ROOT/scripts/changelog-release.sh"

if [[ "$NEXT_VERSION_ONLY" -eq 1 ]]; then
  compute_next_release_version
  exit 0
fi

require_cmd git
require_runnable gh
require_cmd minisign

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "main" ]]; then
  echo "Must be on main (current: $BRANCH)" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  git pull --ff-only origin main
fi

VERSION="$(compute_next_release_version)"
TAG="v${VERSION}"
HEAD_SHA="$(git rev-parse --short HEAD)"
LATEST_TAG="$(previous_release_tag "$VERSION")"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally." >&2
  exit 1
fi

if git ls-remote --tags origin "refs/tags/${TAG}" | grep -q .; then
  echo "Tag $TAG already exists on origin." >&2
  exit 1
fi

echo "Next release: $TAG"
echo "Tag target:   $HEAD_SHA (main)"
if [[ -n "$LATEST_TAG" ]]; then
  echo "Previous tag: $LATEST_TAG"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  if changelog_ready_on_main "$VERSION"; then
    echo "Changelog: ready on main (## ${VERSION})"
    print_changelog_section "$VERSION"
    echo
    echo "After your feature PR merges, release with:"
    echo "  bash scripts/release.sh --yes"
  else
    echo "Changelog: missing — add this section to your feature PR before merge:"
    echo
    echo "## ${VERSION}"
    echo
    echo "- Describe the change (optional commit hash)"
    echo
    echo "Then merge the PR and run:"
    echo "  bash scripts/release.sh --yes"
    echo
    echo "Fallback (separate changelog PR): run without --yes to draft and open a PR."
  fi
  echo
  echo "Dry run — would then:"
  echo "  1. git tag -a $TAG -m \"Release $TAG\""
  echo "  2. git push origin $TAG"
  echo "  3. VERSION=$VERSION CHANGELOG_APPROVED=1 bash scripts/package.sh --release"
  exit 0
fi

approve_changelog_for_release "$VERSION" "$YES" || exit 1

git fetch origin main
ORIGIN_MAIN="$(git rev-parse origin/main)"

if ! git diff --quiet -- "$CHANGELOG_FILE"; then
  RELEASE_BRANCH="cursor/changelog-${VERSION}"
  if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}"; then
    echo "Branch ${RELEASE_BRANCH} already exists. Check it out or delete it first." >&2
    exit 1
  fi
  git checkout -b "$RELEASE_BRANCH"
  git add "$CHANGELOG_FILE"
  git commit -m "Changelog for ${TAG}"
  git push -u origin HEAD
  gh pr create \
    --title "Changelog for ${TAG}" \
    --body "$(cat <<EOF
## Summary
- Add approved changelog section for ${TAG}

## Release follow-up
After merge:

\`\`\`bash
git checkout main && git pull --ff-only origin main && bash scripts/release.sh --yes
\`\`\`

Prefer adding the changelog section in the feature PR next time (\`bash scripts/release.sh --dry-run\` shows the version).
EOF
)"
  git checkout main
  git reset --hard origin/main
  echo "Opened PR for changelog. Merge it, then re-run: bash scripts/release.sh --yes"
  exit 0
fi

if [[ "$(git rev-parse HEAD)" != "$ORIGIN_MAIN" ]]; then
  echo "main must match origin/main before tagging (protected branch — push changelog via PR first)." >&2
  if [[ -n "$(git log "$ORIGIN_MAIN"..HEAD --oneline)" ]]; then
    echo "Local commits ahead of origin:" >&2
    git log "$ORIGIN_MAIN"..HEAD --oneline >&2
  fi
  exit 1
fi

if ! changelog_section_exists "$VERSION"; then
  echo "Changelog is missing a '## ${VERSION}' section." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain -- . ':(exclude)scripts/release.sh')" ]]; then
  echo "Working tree is not clean. Commit or stash changes before releasing." >&2
  exit 1
fi

if [[ "$YES" -eq 0 ]]; then
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

CHANGELOG_APPROVED=1 VERSION="$VERSION" bash "$ROOT/scripts/package.sh" --release

echo "Release complete: $TAG"
