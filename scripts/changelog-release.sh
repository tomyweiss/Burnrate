#!/usr/bin/env bash
# Changelog helpers for release.sh and package.sh --release.

CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT/Sources/Tokens/Resources/CHANGELOG.md}"

changelog_section_exists() {
  local version="$1"
  [[ -f "$CHANGELOG_FILE" ]] || return 1
  grep -qE "^## ${version}([[:space:]]|$)" "$CHANGELOG_FILE"
}

extract_changelog_section() {
  local version="$1"
  awk -v ver="$version" '
    $0 ~ "^## " ver "([[:space:]]|$)" { found=1; next }
    found && /^## / { exit }
    found && /^- / { print }
  ' "$CHANGELOG_FILE"
}

previous_release_tag() {
  local version="$1"
  local tag="v${version}"
  git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | awk -v t="$tag" '$0==t {getline; print; exit}'
}

draft_changelog_bullets() {
  local version="$1"
  local tag="v${version}"
  local prev_tag range commits

  prev_tag="$(previous_release_tag "$version")"

  if [[ -n "$prev_tag" ]]; then
    if git rev-parse "$tag" >/dev/null 2>&1; then
      range="${prev_tag}..${tag}"
    else
      range="${prev_tag}..HEAD"
    fi
    commits="$(git log "$range" --pretty=format:'- %s (%h)' --no-merges --reverse 2>/dev/null || true)"
    if [[ -n "$commits" ]]; then
      printf '%s\n' "$commits"
      return 0
    fi
  else
    commits="$(git log --pretty=format:'- %s (%h)' --no-merges --reverse -50 2>/dev/null || true)"
    if [[ -n "$commits" ]]; then
      printf '%s\n' "$commits"
      return 0
    fi
  fi

  echo "- Maintenance and improvements"
}

insert_changelog_section() {
  local version="$1"
  local body="$2"
  local tmp

  if [[ ! -f "$CHANGELOG_FILE" ]]; then
  cat > "$CHANGELOG_FILE" <<EOF
# Changelog

## ${version}

${body}

EOF
    return 0
  fi

  tmp="$(mktemp)"
  {
    echo "# Changelog"
    echo ""
    echo "## ${version}"
    echo ""
    printf '%s\n' "$body"
    echo ""
    tail -n +3 "$CHANGELOG_FILE"
  } > "$tmp"
  mv "$tmp" "$CHANGELOG_FILE"
}

changelog_section_has_bullets() {
  local version="$1"
  [[ -n "$(extract_changelog_section "$version")" ]]
}

approve_changelog_for_release() {
  local version="$1"

  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Missing changelog file: $CHANGELOG_FILE" >&2
    return 1
  fi

  if changelog_section_exists "$version"; then
    echo "Found existing changelog section for ${version}."
  else
    echo "No changelog section for ${version} — drafting from git commits…"
    insert_changelog_section "$version" "$(draft_changelog_bullets "$version")"
  fi

  while true; do
    echo ""
    echo "Opening ${CHANGELOG_FILE} for review…"
    "${EDITOR:-${VISUAL:-nano}}" "$CHANGELOG_FILE"

    if ! changelog_section_exists "$version"; then
      echo "Changelog is missing a '## ${version}' section." >&2
      read -r -p "Edit again? [Y/n] " reply
      if [[ "$reply" =~ ^[Nn]$ ]]; then
        echo "Aborted."
        return 1
      fi
      continue
    fi

    if ! changelog_section_has_bullets "$version"; then
      echo "Changelog section for ${version} has no bullet items." >&2
      read -r -p "Edit again? [Y/n] " reply
      if [[ "$reply" =~ ^[Nn]$ ]]; then
        echo "Aborted."
        return 1
      fi
      continue
    fi

    echo ""
    echo "── Changelog for ${version} ──"
    extract_changelog_section "$version"
    echo "────────────────────────────"

    read -r -p "Approve changelog for release? [y]es / [e]dit / [n]abort: " reply
    case "$reply" in
      y|Y|yes|YES) return 0 ;;
      e|E|edit|EDIT) continue ;;
      *)
        echo "Aborted."
        return 1
        ;;
    esac
  done
}

write_release_notes_from_changelog() {
  local version="$1"
  local notes_file="$2"
  local section

  section="$(extract_changelog_section "$version")"
  if [[ -z "$section" ]]; then
    return 1
  fi

  {
    echo "## What's new in ${version}"
    echo
    echo "$section"
    echo
  } > "$notes_file"
  return 0
}
