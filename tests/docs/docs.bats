#!/usr/bin/env bats
# README.md, read statically: links to the case-study site, prerequisites, memory budget and demo scenarios.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
README=README.md
DOCS_SITE=https://naqa92-portfolio-projects.github.io/harbor-docs/

fail() {
  echo "$*" >&2
  return 1
}

# Lines of the Markdown section of $1 whose heading matches the extended regexp $2 (case-insensitive), up to the
# next heading of the same or a higher level.
section() {
  awk -v re="$2" '
    /^#+[[:space:]]/ {
      level = length($1)
      if (inside && level <= inside_level) inside = 0
      if (!inside && tolower($0) ~ tolower(re)) { inside = 1; inside_level = level }
    }
    inside { print }
  ' "$REPO_ROOT/$1"
}

@test "README links to the French and English case-study site" {
  [ -s "$REPO_ROOT/$README" ] || fail "$README does not exist or is empty"
  grep -qF "($DOCS_SITE)" "$REPO_ROOT/$README" || grep -qF "<$DOCS_SITE>" "$REPO_ROOT/$README" ||
    fail "$README does not link to $DOCS_SITE"
  grep -qF "${DOCS_SITE}en/" "$REPO_ROOT/$README" || fail "$README does not link to ${DOCS_SITE}en/"
}

@test "README relative links point to existing files" {
  missing=()
  while read -r target; do
    path="${target%%#*}"
    [ -z "$path" ] || [ -e "$REPO_ROOT/$path" ] || missing+=("$target")
  done < <(grep -oE '\]\([^)]+\)' "$REPO_ROOT/$README" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^[a-z]+:')
  [ "${#missing[@]}" -eq 0 ] || fail "$README links to missing files: ${missing[*]}"
}

@test "README documents the prerequisites and the memory budget measurement" {
  problems=()

  prerequisites="$(section "$README" 'prérequis')"
  if [ -z "$prerequisites" ]; then
    problems+=("no heading naming the prerequisites (Prérequis)")
  else
    for pattern in 'devbox' 'docker' '(^|[^a-z])gh([^a-z]|$)|github cli' 'dhi_token' 'dhi_username' '\.env' '16 ?gib'; do
      grep -qiE -- "$pattern" <<<"$prerequisites" || problems+=("the prerequisites section does not mention /$pattern/")
    done
  fi

  memory="$(section "$README" 'mémoire')"
  if [ -z "$memory" ]; then
    problems+=("no heading naming the memory budget (mémoire)")
  else
    for pattern in 'kubectl top nodes' 'working set' 'page cache' '12 ?gib'; do
      grep -qiE -- "$pattern" <<<"$memory" || problems+=("the memory section does not mention /$pattern/")
    done
  fi
  grep -qE 'task up' "$REPO_ROOT/$README" || problems+=("$README does not say how to start the platform (task up)")

  [ "${#problems[@]}" -eq 0 ] || fail "$README: $(printf '%s; ' "${problems[@]}")"
}

@test "README lists every demo scenario with its expected reaction" {
  problems=()
  # scenario | extended regexp its README table row must match (case-insensitive)
  scenarios=(
    'unsigned|workload-image-signature'
    'foreign-signer|workload-image-signature'
    'non-golden-base|workload-golden-base([^-]|$)'
    'deprecated-base|workload-golden-base-deprecated'
    'eol-base|workload-golden-base([^-]|$)'
    'direct-dockerhub|workload-registry'
    'root|pod security.*restricted'
    'runtime-shell|kubescape'
    'vex|dependency-track.*completed'
  )
  tasks="$(yq -r '.tasks | keys | .[]' "$REPO_ROOT/Taskfile.yml")"
  demo="$(section "$README" 'démo')"
  [ -n "$demo" ] || fail "$README has no heading naming the demo scenarios (démo)"
  for entry in "${scenarios[@]}"; do
    scenario="${entry%%|*}"
    grep -qx "demo:$scenario" <<<"$tasks" || problems+=("Taskfile.yml defines no task demo:$scenario")
    row="$(grep -E "^\| \`demo:$scenario\` " <<<"$demo" || true)"
    if [ -z "$row" ]; then
      problems+=("no table row for demo:$scenario")
    else
      grep -qiE -- "${entry#*|}" <<<"$row" || problems+=("the demo:$scenario row does not match /${entry#*|}/")
    fi
  done
  grep -qE 'NAMESPACE=' <<<"$demo" || problems+=("the demo section does not show the NAMESPACE variable")
  grep -qiE 'sort en 0' <<<"$demo" && grep -qiE 'non-zéro' <<<"$demo" ||
    problems+=("the demo section does not state that a scenario exits 0 when the platform reacts and non-zero otherwise")
  awk -v RS= '/tier-required/ { gsub(/\n/, " "); print }' <<<"$demo" | grep -qiE 'refusé.*sort en 0' ||
    problems+=("the demo section does not say a pod in a namespace without harborlab.io/tier is denied by tier-required and the task exits 0")

  [ "${#problems[@]}" -eq 0 ] || fail "$(printf '%s; ' "${problems[@]}")"
}
