#!/usr/bin/env bash
# Hermetic test suite for the self-hosted Supermemory wiring.
#
# Every assertion reads a file in this repository. No daemon, no network, no API
# key and no container is involved, so the suite is safe to run anywhere and says
# nothing about whether the engine actually works. That is the other suite's job,
# and it is not written yet: it needs a boot, a first-boot API key and a real
# round trip. What this file guards is the set of decisions that are expensive to
# get wrong and invisible once they are -- above all that no port is published.
#
# `.env` is deliberately never read. It holds a live key; the suite checks
# `.env.example` instead and asserts that `.env` stays out of version control.
#
# Output is TAP-like: one `OK` / `NOT OK` line per assertion, then a per-aspect
# verdict. Exits non-zero if any assertion fails.
#
#   ./test/supermemory.sh              # everything
#   ./test/supermemory.sh compose      # only aspects whose name contains "compose"
#   make test-memory filter=compose    # the same, through the Makefile

# SC2329 fires on every helper and aspect body below: they are all invoked
#   indirectly, through the aspect_functions array, which shellcheck cannot follow.
# SC2016 fires on needles that are deliberately single-quoted because they match
#   text containing a shell expansion that must not be expanded.
# shellcheck disable=SC2329,SC2016

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
filter=${1:-${MEMORY_TEST_FILTER:-}}

image_file=$root/Dockerfile.supermemory
compose=$root/docker-compose.yml
dockerignore=$root/.dockerignore
gitignore=$root/.gitignore
launcher=$root/bin/pi
contract=$root/agent/AGENTS.md
envexample=$root/.env.example

[ -f "$image_file" ] || { echo "missing $image_file" >&2; exit 1; }

# Assertions run against comment-free text. Every file here argues its choices in
# prose right next to the code, and a comment that says "no `ports:`" or "not
# `curl | bash`" is exactly the kind of sentence a substring match picks up. A
# test that reads the documentation as the behaviour is worse than no test.
strip_comments() { sed 's/[[:space:]]*#.*$//'; }

image=$(strip_comments <"$image_file")
compose_text=$(strip_comments <"$compose")
launcher_text=$(strip_comments <"$launcher")
# Deliberately not comment-stripped: agent/AGENTS.md is markdown, where a `#` is
# a heading rather than a comment, and its section headings are part of what the
# contract assertions check.

# The body of one service, from `  <name>:` up to the next service or the next
# top-level key. Scoping by indentation is what makes "no ports" a real assertion
# rather than a grep that could match some other service's block.
service_block() { # service_block NAME
    awk -v hdr="  $1:" '
        !inside && $0 == hdr { inside = 1; print; next }
        inside {
            if ($0 ~ /^  [A-Za-z0-9_-]+:/ || $0 ~ /^[A-Za-z0-9_-]+:/) exit
            print
        }
    ' "$compose" | strip_comments
}

pi_block=$(service_block pi)
memory_block=$(service_block supermemory)

# The line number of the first line matching REGEX, or empty when there is none.
# Written with a here-string and grep -m1 rather than a pipe: `grep -q` and `head`
# close the pipe on an early match, which under `set -o pipefail` turns a
# successful match into a SIGPIPE failure and, worse, a plain assignment into an
# exit under `set -e`.
line_of() { # line_of REGEX HAYSTACK
    grep -nE --max-count=1 "$1" <<<"$2" | cut -d: -f1
}

[ -n "$pi_block" ] || { echo "no pi service in $compose" >&2; exit 1; }
[ -n "$memory_block" ] || { echo "no supermemory service in $compose" >&2; exit 1; }

contract_text=$(cat "$contract")

# --------------------------------------------------------------- the harness

checks=0
failures=0
declare -a ran_aspects=() failed_aspects=()

ok() { # ok NAME DESCRIPTION
    checks=$((checks + 1))
    printf 'OK %d - %s\n' "$checks" "$2"
}

nope() { # nope NAME DESCRIPTION DETAIL
    checks=$((checks + 1))
    failures=$((failures + 1))
    printf 'NOT OK %d - %s\n' "$checks" "$2"
    printf '#   %s\n' "$3"
}

assert_contains() { # assert_contains NAME HAYSTACK NEEDLE DESCRIPTION
    case "$2" in
        *"$3"*) ok "$1" "$4" ;;
        *) nope "$1" "$4" "[$3] not found" ;;
    esac
}

assert_not_contains() { # assert_not_contains NAME HAYSTACK NEEDLE DESCRIPTION
    case "$2" in
        *"$3"*) nope "$1" "$4" "[$3] unexpectedly present" ;;
        *) ok "$1" "$4" ;;
    esac
}

assert_matches() { # assert_matches NAME HAYSTACK REGEX DESCRIPTION
    if grep -Eq "$3" <<<"$2"; then
        ok "$1" "$4"
    else
        nope "$1" "$4" "no line matching /$3/"
    fi
}

assert_before() { # assert_before NAME FIRST_REGEX SECOND_REGEX HAYSTACK DESCRIPTION
    local a b
    a=$(line_of "$2" "$4")
    b=$(line_of "$3" "$4")
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
        ok "$1" "$5"
    else
        nope "$1" "$5" "expected /$2/ (line ${a:-none}) before /$3/ (line ${b:-none})"
    fi
}

assert_eq() { # assert_eq NAME EXPECTED ACTUAL DESCRIPTION
    if [ "$2" = "$3" ]; then ok "$1" "$4"; else nope "$1" "$4" "expected [$2], got [$3]"; fi
}

assert_file() { # assert_file NAME PATH DESCRIPTION
    if [ -e "$2" ]; then ok "$1" "$3"; else nope "$1" "$3" "$2 does not exist"; fi
}

declare -a aspect_names=() aspect_descriptions=() aspect_functions=()

aspect_add() { # aspect_add NAME DESCRIPTION FUNCTION
    aspect_names+=("$1")
    aspect_descriptions+=("$2")
    aspect_functions+=("$3")
}

run_aspect() { # run_aspect INDEX
    local i=$1
    local name=${aspect_names[i]}
    local before=$failures
    ran_aspects+=("$name")
    printf '# %s\n' "$name"
    local aspect_status=0
    "${aspect_functions[i]}" || aspect_status=$?
    if [ "$aspect_status" -ne 0 ]; then
        nope "$name" "aspect ${aspect_descriptions[i]} aborted" \
            "the aspect body returned $aspect_status"
    fi
    [ "$failures" -eq "$before" ] || failed_aspects+=("$name")
}

# -------------------------------------------------------------------- aspects

# --- image -------------------------------------------------------------------

image_pins_a_version() {
    assert_matches "image/has-arg" "$image" \
        '^ARG SUPERMEMORY_VERSION=[0-9]+\.[0-9]+\.[0-9]+' \
        "image pins an explicit SUPERMEMORY_VERSION"
    assert_not_contains "image/no-latest" "$image" 'SUPERMEMORY_VERSION=latest' \
        "and the pin is not 'latest'"
}

image_verifies_the_download() {
    # The point of not running `curl | bash`: the build says what it fetched and
    # proves it. An unpinned download that is never checked is the thing to
    # catch, whether it arrives as a pipe or a bare curl.
    assert_not_contains "image/no-pipe-to-shell" "$image" '| bash' \
        "image does not pipe the upstream installer into a shell"
    assert_contains "image/fetches-manifest" "$image" 'manifest.json' \
        "image fetches the release manifest"
    assert_contains "image/checks-checksum" "$image" 'sha256sum -c' \
        "image verifies the binary against the manifest checksum"
    assert_contains "image/rejects-bad-checksum" "$image" "[0-9a-f]{64}\$'" \
        "image constrains the checksum to 64 hex characters"
    assert_contains "image/fails-on-bad-checksum" "$image" "|| { \\" \
        "and exits the build when that check fails"
    assert_before "image/checksum-before-use" 'sha256sum -c' 'chmod 0755' "$image" \
        "image checks the checksum before making the binary executable"
}

image_reports_a_bad_binary_at_build_time() {
    assert_matches "image/tests-entry-point" "$image" \
        '^RUN test -x /usr/local/bin/supermemory-server' \
        "image asserts the entry point is executable, as the agent image does"
    assert_contains "image/entry-point" "$image" \
        'ENTRYPOINT ["/usr/local/bin/supermemory-server"]' \
        "image runs the binary it verified"
}

image_sets_its_own_environment() {
    assert_contains "image/data-dir" "$image" 'SUPERMEMORY_DATA_DIR=/var/lib/supermemory' \
        "image sets the data directory"
    assert_contains "image/creates-data-dir" "$image" 'mkdir -p "$SUPERMEMORY_DATA_DIR"' \
        "image creates it, so the volume mounts onto something that exists"
    assert_contains "image/telemetry" "$image" 'SUPERMEMORY_DISABLE_TELEMETRY=1' \
        "image disables telemetry"
    # A published port is exactly what this image must not ask for, so it should
    # not advertise one either. EXPOSE binds nothing, but naming the port here as
    # well makes the intent harder to misread.
    assert_not_contains "image/no-expose" "$image" 'EXPOSE' \
        "image advertises no port"
}

image_covers_both_architectures() {
    assert_contains "image/amd64" "$image" 'amd64) platform=linux-x64' \
        "image maps amd64 onto the x64 release asset"
    assert_contains "image/arm64" "$image" 'arm64) platform=linux-arm64' \
        "image maps arm64 onto the arm64 release asset"
}

aspect_add "image" "the memory image pins, verifies and runs what it downloaded" \
    image_pins_a_version
aspect_add "image" "" image_verifies_the_download
aspect_add "image" "" image_reports_a_bad_binary_at_build_time
aspect_add "image" "" image_sets_its_own_environment
aspect_add "image" "" image_covers_both_architectures

# --- compose: the service ----------------------------------------------------

compose_service_exists() {
    assert_file "compose/file" "$compose" "the compose file is present"
    assert_matches "compose/service" "$compose_text" '^  supermemory:$' \
        "compose defines a supermemory service"
    assert_matches "compose/builds-own-image" "$memory_block" \
        'dockerfile: Dockerfile\.supermemory' \
        "the service builds from Dockerfile.supermemory"
}

compose_publishes_no_ports() {
    # The load-bearing assertion in this file. The pinned release binds every
    # interface and its implicit local authentication is unsafe off the compose
    # network, per Supermemory's own self-hosting docs. A `ports:` line here
    # would put an unauthenticated memory engine on the host's interfaces.
    assert_not_contains "compose/no-ports" "$memory_block" 'ports:' \
        "the memory service publishes no host port"
    assert_not_contains "compose/no-network-mode" "$memory_block" 'network_mode' \
        "and does not opt out of the compose network"
    assert_not_contains "compose/no-extra-hosts" "$memory_block" 'extra_hosts' \
        "and adds no host gateway route"
}

compose_starts_with_the_agent() {
    # A profiled service is left out of `compose run pi`, and then the agent's
    # lookup of "supermemory" fails outright rather than degrading.
    assert_not_contains "compose/no-profiles" "$memory_block" 'profiles:' \
        "the memory service is not behind a profile"
    assert_contains "compose/pi-depends-on" "$pi_block" 'depends_on:' \
        "the agent service depends on it"
    assert_contains "compose/depends-on-memory" "$pi_block" 'supermemory:' \
        "on the memory service by name"
    assert_contains "compose/condition" "$pi_block" 'condition: service_started' \
        "waiting only for start, so a cold embedding download never blocks a launch"
    assert_not_contains "compose/not-health-gated" "$pi_block" 'service_healthy' \
        "and the agent is not gated on the healthcheck"
}

compose_has_a_provider() {
    # No TTY in a container means no first-boot wizard, so extraction has to be
    # configured from the environment or the engine cannot answer a single query.
    assert_contains "compose/base-url" "$memory_block" 'OPENAI_BASE_URL:' \
        "the engine is pointed at an OpenAI-compatible endpoint"
    assert_contains "compose/api-key" "$memory_block" 'OPENAI_API_KEY:' \
        "with a key taken from the host environment"
    assert_contains "compose/model" "$memory_block" 'OPENAI_MODEL:' \
        "and a model, which is overridable from .env"
}

compose_keeps_state_in_a_volume() {
    assert_matches "compose/named-volume" "$compose_text" '^volumes:$' \
        "compose declares a top-level volumes section"
    assert_contains "compose/mounts-data-dir" "$memory_block" \
        'supermemory:/var/lib/supermemory' \
        "the engine's state lives in a named volume, not a bind into the repository"
    assert_contains "compose/data-dir-matches" "$memory_block" \
        'SUPERMEMORY_DATA_DIR: /var/lib/supermemory' \
        "and the data directory agrees with the mount point"
}

compose_forwards_the_key_to_the_agent() {
    assert_contains "compose/forwards-key" "$pi_block" 'SUPERMEMORY_API_KEY' \
        "the agent container receives SUPERMEMORY_API_KEY"
}

aspect_add "compose" "the memory service is defined, isolated and startable" \
    compose_service_exists
aspect_add "compose" "" compose_publishes_no_ports
aspect_add "compose" "" compose_starts_with_the_agent
aspect_add "compose" "" compose_has_a_provider
aspect_add "compose" "" compose_keeps_state_in_a_volume
aspect_add "compose" "" compose_forwards_the_key_to_the_agent

# --- context and state -------------------------------------------------------

context_includes_the_memory_dockerfile() {
    # The build context is an allowlist, so the new Dockerfile is excluded until
    # it is named. Without this the supermemory build fails on a missing file,
    # which reads like a broken build rather than a broken ignore rule.
    assert_matches "context/un-excluded" "$(cat "$dockerignore")" \
        '^!Dockerfile\.supermemory$' \
        ".dockerignore un-excludes Dockerfile.supermemory"
    assert_not_contains "context/no-env" "$(cat "$dockerignore")" '!.env' \
        ".dockerignore still keeps .env out of the context"
}

state_stays_out_of_version_control() {
    local ignore
    ignore=$(cat "$gitignore")
    assert_matches "state/env-ignored" "$ignore" '^\.env$' \
        ".env is gitignored"
    assert_matches "state/envexample-kept" "$ignore" '^!\.env\.example$' \
        ".env.example is explicitly kept"
    assert_file "state/envexample-exists" "$envexample" ".env.example exists"
    assert_not_contains "state/envexample-no-key" "$(cat "$envexample")" 'sk-or-v1-' \
        ".env.example holds no live provider key"
}

hygiene_committed_files_hold_no_secret() {
    # A superset of the two above: whatever the layout, no committed file may
    # carry a credential. Reads only files git already tracks or ignores.
    local f leaked=
    for f in "$image_file" "$compose" "$envexample" "$contract" "$launcher"; do
        if grep -Eq '(sk-or-v1-|sk-ant-|sk-[A-Za-z0-9]{20,}|sm_[A-Za-z0-9]{20,})' "$f"; then
            leaked="$leaked $(basename "$f")"
        fi
    done
    assert_eq "hygiene/no-secrets" "" "$leaked" \
        "no committed file carries a credential"
}

aspect_add "context" "the build context reaches the memory Dockerfile and nothing else" \
    context_includes_the_memory_dockerfile
aspect_add "state" "local keys stay out of the repository and the image" \
    state_stays_out_of_version_control
aspect_add "hygiene" "" hygiene_committed_files_hold_no_secret

# --- launcher ----------------------------------------------------------------

launcher_builds_both_images() {
    assert_contains "launcher/has-memory-image" "$launcher_text" 'SUPERMEMORY_IMAGE' \
        "the launcher knows the memory image name"
    assert_matches "launcher/builds-memory" "$launcher_text" 'build pi supermemory' \
        "and builds it alongside the agent image"
    assert_matches "launcher/inspects-memory" "$launcher_text" \
        'docker image inspect "\$memory_image"' \
        "so a fresh clone does not fail on a missing image"
    assert_contains "launcher/exports-memory-image" "$launcher_text" \
        'SUPERMEMORY_IMAGE="$memory_image"' \
        "and exports it so compose resolves the same name"
}

launcher_stays_posix() {
    # bin/pi runs on whatever /bin/sh is, which is not always bash. A bashism
    # added for the memory image would break the launcher on every other host.
    if command -v shellcheck >/dev/null 2>&1; then
        local out
        if out=$(shellcheck --shell=sh --severity=warning "$launcher" 2>&1); then
            ok "launcher/posix-clean" "the launcher is POSIX-clean under shellcheck"
        else
            nope "launcher/posix-clean" "the launcher is POSIX-clean under shellcheck" \
                "$out"
        fi
    else
        ok "launcher/posix-clean" "the launcher is POSIX-clean (shellcheck absent, skipped)"
    fi
}

aspect_add "launcher" "bin/pi builds and exports both images without leaving POSIX sh" \
    launcher_builds_both_images
aspect_add "launcher" "" launcher_stays_posix

# --- contract ----------------------------------------------------------------

contract_documents_the_endpoint() {
    # Self-hosted Supermemory ships no MCP server, so this file is the whole
    # interface the agent has. If it drifts from the compose service name, the
    # agent has no way to find out except by failing at runtime.
    assert_contains "contract/endpoint" "$contract_text" 'http://supermemory:6767' \
        "AGENTS.md gives the agent the engine's address"
    assert_contains "contract/tag-rule" "$contract_text" 'containerTag' \
        "and the scoping rule every read and write must follow"
    assert_contains "contract/ingest" "$contract_text" '/v3/documents' \
        "and the ingest endpoint"
    assert_contains "contract/recall" "$contract_text" '/v4/search' \
        "and the recall endpoint"
    assert_contains "contract/degrade" "$contract_text" 'do not retry in a loop' \
        "and what to do while the engine is still warming up"
    # The memory section was added to a file that already existed. Losing a
    # heading while inserting one is the easy mistake here.
    assert_contains "contract/keeps-environment" "$contract_text" '## Environment' \
        "the environment section survived the edit"
    assert_contains "contract/keeps-working-agreement" "$contract_text" \
        '## Working agreement' \
        "the working agreement survived the edit"
}

aspect_add "contract" "AGENTS.md tells the agent how to reach memory, and how to fail" \
    contract_documents_the_endpoint

# ------------------------------------------------------------------- run them

i=0
while [ "$i" -lt "${#aspect_names[@]}" ]; do
    if [ -z "$filter" ] || [[ ${aspect_names[i]} == *"$filter"* ]]; then
        run_aspect "$i"
    fi
    i=$((i + 1))
done

failed=$(printf '%s\n' "${failed_aspects[@]+"${failed_aspects[@]}"}")
for t in $(printf '%s\n' "${ran_aspects[@]+"${ran_aspects[@]}"}" | sort -u); do
    if grep -qx "$t" <<<"$failed"; then
        printf '# %s: FAILED\n' "$t"
    else
        printf '# %s: OK\n' "$t"
    fi
done

printf '1..%d\n' "$checks"
if [ "$failures" -eq 0 ]; then
    printf '# all %d checks passed\n' "$checks"
    exit 0
fi
printf '# %d of %d checks failed\n' "$failures" "$checks"
exit 1