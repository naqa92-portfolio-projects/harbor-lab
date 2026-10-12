#!/usr/bin/env bats
# Operator documentation in README.md: node restart recovery, repository prerequisites and the CI gap of
# GITHUB_TOKEN pull requests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
README=README.md

fail() {
  echo "$*" >&2
  return 1
}

# Statements of README.md, NUL-separated: each table row alone, each other paragraph as one unit.
readme_units() {
  awk 'function flush() { if (unit != "") printf "%s%c", unit, 0; unit = "" }
       /^\|/ { flush(); printf "%s%c", $0, 0; next }
       /^[[:space:]]*$/ { flush(); next }
       { unit = (unit == "" ? $0 : unit "\n" $0) }
       END { flush() }' "$REPO_ROOT/$README"
}

# README units matching every extended regex given (case-insensitive), NUL-separated.
readme_units_matching() {
  local unit pattern matched
  while IFS= read -r -d '' unit; do
    matched=true
    for pattern in "$@"; do
      grep -qiE "$pattern" <<<"$unit" || matched=false
    done
    if [ "$matched" = true ]; then printf '%s\0' "$unit"; fi
  done < <(readme_units)
}

@test "README documents recovering a stopped node with task down and task up" {
  # The paragraph that names the recovery also names the event it recovers from.
  paragraph="$(awk 'BEGIN { RS = "" } /task down && task up|task down && devbox run -- task up|task down; task up/' "$REPO_ROOT/$README")"
  [ -n "$paragraph" ] || fail "$README never documents 'task down && task up'"
  grep -qiE 'docker (stop|start|restart)|arrêté|redémarrage' <<<"$paragraph" ||
    fail "$README documents 'task down && task up' without the node stop or restart it recovers from: $paragraph"
}

@test "README prerequisites require a ruleset on main blocking deletion and force-pushes, and nothing more" {
  prerequisites="$(awk '/^## Prérequis/ { in_section = 1; next } /^## / { in_section = 0 } in_section' "$REPO_ROOT/$README")"
  [ -n "$prerequisites" ] || fail "$README has no Prérequis section"
  requirement="$(grep -iE 'ruleset' <<<"$prerequisites" | grep -E '\bmain\b' | grep -iE 'suppression' | grep -iE 'force[- ]push')"
  [ -n "$requirement" ] ||
    fail "$README prerequisites do not require a ruleset on main blocking deletion and force-pushes"
  if grep -qiE 'revues? obligatoires?|checks? obligatoires?' <<<"$requirement"; then
    fail "$README ruleset prerequisite requires reviews or status checks: $requirement"
  fi
}

@test "README binds the signing identity to whoever has write access, which the ruleset does not restrict" {
  statement="$(readme_units_matching 'identité' 'signature' "droit d.écriture" 'propriétaire' 'ne restreint pas' |
    tr '\0' '\n')"
  [ -n "$statement" ] ||
    fail "$README never states that the signing identity is bound to whoever has write access to the repository (the owner), which the ruleset does not restrict"
}

@test "README states that pull requests opened with GITHUB_TOKEN run no pull_request CI" {
  statement="$(readme_units_matching 'GITHUB_TOKEN' 'pull request' 'aucune CI `?pull_request' | tr '\0' '\n')"
  [ -n "$statement" ] ||
    fail "$README never states that pull requests opened with GITHUB_TOKEN run no pull_request CI"
  if grep -qiE 'checks? obligatoires? bloqu' <<<"$statement"; then
    fail "$README still says required status checks block GITHUB_TOKEN pull requests: $statement"
  fi
}
