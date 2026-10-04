#!/usr/bin/env bash
# Hermetic test suite for the targets in ../Makefile.
#
# Every target runs in a throwaway copy of the repository, with recording stubs
# for `docker` and `npm` at the front of PATH. No daemon and no network are
# involved, and the repository the developer is standing in is never written to.
#
# Output is TAP-like: one `OK` / `NOT OK` line per assertion, then a per-target
# verdict. Exits non-zero if any assertion fails, and also if the Makefile grows
# a target that has no case here.
#
#   ./test/make-targets.sh            # everything
#   ./test/make-targets.sh pin        # only cases whose name contains "pin"
#   make test filter=pin              # the same, through the Makefile

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
filter=${1:-${MAKE_TEST_FILTER:-}}

# ------------------------------------------------------------- the test repo

tmp=$(mktemp -d "${TMPDIR:-/tmp}/make-targets.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

work=$tmp/work     # throwaway copy of the repository
stubs=$tmp/stubs   # recording `docker` and `npm`
log=$tmp/calls.log # every stub invocation, in order

image=pi-agent:latest # the Makefile default, baked into the `docker` stub

# Only what the Makefile reads: copying .git, agent sessions or .env would be
# slow at best and would leak local state into the assertions at worst.
mkdir -p "$work" "$work/test" "$stubs"
for f in Makefile Dockerfile docker-compose.yml docker-entrypoint.sh \
         README.md; do
    [ -e "$root/$f" ] && cp -p "$root/$f" "$work/$f"
done
cp -rp "$root/bin" "$work/bin"
cp -rp "$root/scripts" "$work/scripts"
cp -p "${BASH_SOURCE[0]}" "$work/test/make-targets.sh"

# `docker` records its arguments and succeeds, except for `image rm`, which
# fails the way it does when the image is already gone -- `clean` has to cope.
cat >"$stubs/docker" <<EOF
#!/usr/bin/env bash
printf 'docker %s\n' "\$*" >>"$log"
if [ "\$1 \$2" = "image rm" ]; then
    echo "Error response from daemon: No such image: $image" >&2
    exit 1
fi
exit 0
EOF

# `npm` records the lookup and reports the canned version below.
npm_version=9.9.9
cat >"$stubs/npm" <<EOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >>"$log"
echo "$npm_version"
EOF
chmod +x "$stubs/docker" "$stubs/npm"

# A stand-in for `compose`, used to check that image= actually reaches the
# recipe: it prints the PI_IMAGE the Makefile exports and nothing else. Single
# quotes on purpose -- the stub reads $PI_IMAGE when make runs it, not now.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PI_IMAGE"\n' >"$stubs/pi-compose"
chmod +x "$stubs/pi-compose"

: >"$log"

# Run make inside the copy, stubs first on PATH. Output goes to $out and the
# exit status to $status; the caller decides what to assert about either.
out=
status=0
run_make() {
    status=0
    printf '### make %s\n' "$*" >>"$log"
    out=$(cd "$work" && PATH="$stubs:$PATH" make --no-print-directory "$@" 2>&1) || status=$?
    return 0
}

# --------------------------------------------------------------- assertions

checks=0
failures=0
declare -a ran_targets=() failed_targets=()

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

assert_eq() { # assert_eq NAME EXPECTED ACTUAL DESCRIPTION
    if [ "$2" = "$3" ]; then ok "$1" "$4"; else nope "$1" "$4" "expected [$2], got [$3]"; fi
}

assert_ok() { # assert_ok NAME DESCRIPTION  -- $status from the last run_make
    if [ "$status" -eq 0 ]; then ok "$1" "$2"; else nope "$1" "$2" "exited $status: $out"; fi
}

assert_fails() { # assert_fails NAME DESCRIPTION
    if [ "$status" -ne 0 ]; then ok "$1" "$2"; else nope "$1" "$2" "expected a non-zero exit"; fi
}

assert_contains() { # assert_contains NAME HAYSTACK NEEDLE DESCRIPTION
    case "$2" in
        *"$3"*) ok "$1" "$4" ;;
        *) nope "$1" "$4" "[$3] not found in [$2]" ;;
    esac
}

assert_not_contains() { # assert_not_contains NAME HAYSTACK NEEDLE DESCRIPTION
    case "$2" in
        *"$3"*) nope "$1" "$4" "[$3] unexpectedly present in [$2]" ;;
        *) ok "$1" "$4" ;;
    esac
}

assert_file() { # assert_file NAME PATH DESCRIPTION
    if [ -e "$2" ]; then ok "$1" "$3"; else nope "$1" "$3" "$2 does not exist"; fi
}

assert_no_file() { # assert_no_file NAME PATH DESCRIPTION
    if [ -e "$2" ]; then nope "$1" "$3" "$2 still exists"; else ok "$1" "$3"; fi
}

# ------------------------------------------------------------------- harness

declare -a case_names=() case_descriptions=() case_functions=()

case_add() { # case_add NAME DESCRIPTION FUNCTION
    case_names+=("$1")
    case_descriptions+=("$2")
    case_functions+=("$3")
}

run_case() { # run_case INDEX
    local i=$1
    local name=${case_names[i]}
    local target=${case_names[i]%%/*}
    local before=$failures
    ran_targets+=("$target")
    printf '# %s\n' "$name"
    local ok_status=0
    "${case_functions[i]}" || ok_status=$?
    if [ "$ok_status" -ne 0 ]; then
        # An assertion helper returning non-zero means it never got to assert.
        nope "$name" "case ${case_descriptions[i]} aborted" \
            "the case body returned $ok_status"
    fi
    [ "$failures" -eq "$before" ] || failed_targets+=("$target")
}

# --------------------------------------------------------------------- cases

# --- help -------------------------------------------------------------------

help_list() {
    run_make help
    assert_ok "help/runs" "help succeeds"
    assert_contains "help/usage" "$out" "Usage: make" "help prints a usage line"
    local t
    for t in build install uninstall update pin clean test; do
        assert_contains "help/lists-$t" "$out" "$t" "help lists $t"
    done
    local v
    for v in image install_dir compose pi_package dockerfile version filter; do
        assert_contains "help/var-$v" "$out" "$v" "help lists the $v variable"
    done
    assert_contains "help/current-value" "$out" "(now: $image)" \
        "help shows the current value of image"
}

case_add "help/lists-targets" "help lists every target and variable" help_list

help_is_default() {
    out=$(cd "$work" && PATH="$stubs:$PATH" make --no-print-directory 2>&1) || status=$?
    assert_ok "help/default-goal" "a bare make runs help"
    assert_contains "help/default-goal/usage" "$out" "Usage: make" "and prints the help"
}

case_add "help/default-goal" "help is the default goal" help_is_default

help_rejects_unknown() {
    run_make no-such-target
    assert_fails "help/unknown-fails" "an unknown target fails"
    assert_contains "help/unknown-names-it" "$out" "no-such-target" \
        "and the error names the target"
}

case_add "help/unknown-target" "an unknown target fails loudly" help_rejects_unknown

# --- build ------------------------------------------------------------------

build_calls_compose() {
    : >"$log"
    run_make build
    assert_ok "build/succeeds" "build succeeds"
    assert_contains "build/compose-build" "$(cat "$log")" "docker compose build pi" \
        "build runs compose build for the pi service"
}

case_add "build/compose-build" "build runs compose build for the pi service" \
    build_calls_compose

build_honours_image() {
    run_make build image=my-pi:dev compose=pi-compose
    assert_ok "build/image-override/succeeds" "build succeeds with image="
    assert_contains "build/image-override/exported" "$out" "my-pi:dev" \
        "the override reaches the recipe as PI_IMAGE"
    run_make build compose=pi-compose
    assert_contains "build/image-override/default" "$out" "$image" \
        "without an override the default image is used"
}

case_add "build/image-override" "build accepts image=" build_honours_image

# --- shell ------------------------------------------------------------------

shell_takes_a_service_argument() {
    : >"$log"
    run_make shell pi
    assert_ok "shell/succeeds" "make shell pi succeeds instead of failing on a missing rule"
    assert_contains "shell/named-service" "$(cat "$log")" "docker compose exec pi sh" \
        "the service argument reaches compose"
    : >"$log"
    run_make shell
    assert_contains "shell/default-service" "$(cat "$log")" "docker compose exec pi sh" \
        "a bare shell picks the same service"
}

case_add "shell/takes-a-service" "shell accepts a service as a plain argument" \
    shell_takes_a_service_argument

pi_is_a_placeholder() {
    run_make pi
    assert_ok "pi/succeeds" "a bare service word is not an error"
    assert_eq "pi/silent" "" "$out" "and the placeholder target does nothing"
}

case_add "pi/is-a-placeholder" "a service word is not treated as a missing target" \
    pi_is_a_placeholder

# --- install ----------------------------------------------------------------

install_links() {
    run_make install install_dir="$tmp/home/bin"
    assert_ok "install/succeeds" "install succeeds"
    assert_file "install/creates-link" "$tmp/home/bin/pi" "install creates the symlink"
    assert_contains "install/points-at-launcher" "$(readlink "$tmp/home/bin/pi")" \
        "$work/bin/pi" "the symlink points at the repository launcher"
    assert_contains "install/reports" "$out" "installed $tmp/home/bin/pi" \
        "install reports the path it linked"
}

case_add "install/creates-symlink" "install symlinks pi into install_dir" install_links

install_is_idempotent() {
    run_make install install_dir="$tmp/home/bin"
    assert_ok "install/is-idempotent/first-run" "the first install succeeds"
    run_make install install_dir="$tmp/home/bin"
    assert_ok "install/is-idempotent/second-run" "a second install succeeds"
    assert_contains "install/is-idempotent/noop" "$out" "already links to" \
        "a second install reports the existing link instead of relinking"
}

case_add "install/is-idempotent" "install is a no-op when the link is current" \
    install_is_idempotent

install_replaces_foreign_link() {
    mkdir -p "$tmp/other"
    ln -s /bin/ls "$tmp/other/pi"
    run_make install install_dir="$tmp/other"
    assert_ok "install/replace-succeeds" "install replaces a stale symlink"
    assert_contains "install/replace-repoints" "$(readlink "$tmp/other/pi")" \
        "$work/bin/pi" "and the link now points at the launcher"
}

case_add "install/replaces-foreign-link" "install repoints a link that goes elsewhere" \
    install_replaces_foreign_link

# --- uninstall --------------------------------------------------------------

uninstall_removes_ours() {
    run_make install install_dir="$tmp/home/bin"
    assert_file "uninstall/removes-our-link/installed" "$tmp/home/bin/pi" \
        "install put a symlink in place"
    run_make uninstall install_dir="$tmp/home/bin"
    assert_ok "uninstall/removes-our-link/succeeds" "uninstall removes the link install made"
    assert_no_file "uninstall/removes-our-link/gone" "$tmp/home/bin/pi" "the symlink is gone"
}

case_add "uninstall/removes-our-link" "uninstall removes the link install made" \
    uninstall_removes_ours

uninstall_missing_is_fine() {
    run_make uninstall install_dir="$tmp/empty"
    assert_ok "uninstall/absent-succeeds" "uninstall succeeds when nothing is installed"
    assert_contains "uninstall/absent-says-so" "$out" "nothing to remove" \
        "uninstall explains that there was nothing to do"
}

case_add "uninstall/absent-is-ok" "uninstall succeeds when nothing is installed" \
    uninstall_missing_is_fine

uninstall_refuses_regular_file() {
    mkdir -p "$tmp/real"
    : >"$tmp/real/pi"
    run_make uninstall install_dir="$tmp/real"
    assert_fails "uninstall/file-fails" "uninstall refuses to delete a regular file"
    assert_file "uninstall/file-kept" "$tmp/real/pi" "the regular file survived"
    assert_contains "uninstall/file-reason" "$out" "not a symlink" \
        "uninstall says why it refused"
}

case_add "uninstall/refuses-regular-file" "uninstall keeps a real file" \
    uninstall_refuses_regular_file

uninstall_refuses_foreign_symlink() {
    mkdir -p "$tmp/foreign"
    ln -s /bin/ls "$tmp/foreign/pi"
    run_make uninstall install_dir="$tmp/foreign"
    assert_fails "uninstall/foreign-fails" "uninstall refuses a symlink that is not ours"
    assert_file "uninstall/foreign-kept" "$tmp/foreign/pi" "the foreign symlink survived"
    assert_contains "uninstall/foreign-reason" "$out" "points elsewhere" \
        "uninstall says why it refused"
}

case_add "uninstall/refuses-foreign-link" "uninstall keeps a symlink that is not ours" \
    uninstall_refuses_foreign_symlink

# --- pin --------------------------------------------------------------------

pin_requires_version() {
    run_make pin
    assert_fails "pin/missing-version-fails" "pin without a version fails"
    assert_contains "pin/missing-version-hint" "$out" "make pin version=" \
        "pin shows how to call it properly"
}

case_add "pin/requires-a-version" "pin without version= fails with a hint" \
    pin_requires_version

pin_writes_dockerfile() {
    run_make pin version=2.3.4
    assert_ok "pin/succeeds" "pin succeeds"
    assert_contains "pin/writes-arg" "$(cat "$work/Dockerfile")" "ARG PI_VERSION=2.3.4" \
        "the Dockerfile now pins the requested version"
    assert_contains "pin/confirms" "$out" "pinned PI_VERSION=2.3.4" "pin confirms the version"
    assert_eq "pin/no-tempfile-left" "" "$(find "$work" -maxdepth 1 -name 'tmp.*' -print)" \
        "pin leaves no temporary file behind"
}

case_add "pin/writes-the-dockerfile" "pin rewrites ARG PI_VERSION" pin_writes_dockerfile

pin_touches_one_line() {
    cp -p "$work/Dockerfile" "$tmp/Dockerfile.before"
    run_make pin version=0.0.1
    assert_ok "pin/second-succeeds" "pin runs again"
    assert_eq "pin/one-line-changed" "1" \
        "$(diff "$tmp/Dockerfile.before" "$work/Dockerfile" | grep -c '^<')" \
        "exactly one line changed"
    assert_contains "pin/rest-intact" "$(cat "$work/Dockerfile")" "FROM" \
        "the rest of the Dockerfile is intact"
}

case_add "pin/touches-only-the-version" "pin changes only the version line" \
    pin_touches_one_line

pin_needs_the_arg_line() {
    printf 'FROM scratch\n' >"$work/other.Dockerfile"
    run_make pin version=1.0.0 dockerfile=other.Dockerfile
    assert_fails "pin/no-arg-fails" "pin fails without an ARG PI_VERSION line"
    assert_contains "pin/no-arg-reason" "$out" "ARG PI_VERSION=" "pin names the missing line"
    assert_eq "pin/no-arg-untouched" "FROM scratch" "$(cat "$work/other.Dockerfile")" \
        "the file is left alone"
}

case_add "pin/needs-the-arg-line" "pin needs an ARG PI_VERSION line" \
    pin_needs_the_arg_line

# --- update -----------------------------------------------------------------

update_pins_latest() {
    printf 'ARG PI_VERSION=1.0.0\n' >"$work/Dockerfile"
    : >"$log"
    run_make update
    assert_ok "update/succeeds" "update succeeds"
    assert_contains "update/asks-npm" "$(cat "$log")" \
        "npm view @earendil-works/pi-coding-agent version" "update asks npm for the latest"
    assert_contains "update/writes-arg" "$(cat "$work/Dockerfile")" \
        "ARG PI_VERSION=$npm_version" "the Dockerfile pins what npm reported"
    assert_contains "update/hints-at-build" "$out" "make build" "update suggests a rebuild"
}

case_add "update/pins-the-latest" "update pins the version npm reports" update_pins_latest

update_fails_when_npm_fails() {
    printf '#!/usr/bin/env bash\nprintf "npm %%s\\n" "$*" >>%s\nexit 1\n' "$log" \
        >"$stubs/npm"
    chmod +x "$stubs/npm"
    local version_before; version_before=$(grep '^ARG PI_VERSION=' "$work/Dockerfile")
    run_make update
    assert_fails "update/offline-fails" "update stops when npm cannot be reached"
    assert_contains "update/offline-reason" "$out" "could not query npm" \
        "update says npm was the problem"
    assert_eq "update/offline-untouched" "$version_before" \
        "$(grep '^ARG PI_VERSION=' "$work/Dockerfile")" "the Dockerfile is left alone"
}

case_add "update/fails-when-npm-fails" "update stops when npm is unreachable" \
    update_fails_when_npm_fails

# --- clean ------------------------------------------------------------------

clean_drops_everything() {
    : >"$log"
    run_make clean
    local calls; calls=$(cat "$log")
    assert_contains "clean/compose-down" "$calls" "docker compose down --remove-orphans" \
        "clean tears the compose project down"
    assert_contains "clean/image-rm" "$calls" "docker image rm $image" \
        "clean removes the image"
    assert_ok "clean/succeeds" "clean succeeds even when the image is already gone"
    assert_file "clean/keeps-checked-in-files" "$work/bin/pi" "clean keeps the sources"
}

case_add "clean/drops-image-and-network" "clean stops containers and removes the image" \
    clean_drops_everything

clean_honours_image() {
    : >"$log"
    run_make clean image=my-pi:dev
    assert_ok "clean/override-succeeds" "clean succeeds with image="
    assert_contains "clean/override-image-rm" "$(cat "$log")" "docker image rm my-pi:dev" \
        "the image override reaches the stub"
    assert_not_contains "clean/override-no-default" "$(cat "$log")" \
        "docker image rm $image" "and the default image is left alone"
}

case_add "clean/image-override" "clean removes the image named by image=" clean_honours_image

# --- test -------------------------------------------------------------------

test_target_runs_the_suite() {
    run_make -n test
    assert_ok "test/target-exists" "make has a test target"
    assert_contains "test/dry-run" "$out" "test/make-targets.sh" \
        "the test target runs this suite"
}

case_add "test/target-exists" "make test runs this suite" test_target_runs_the_suite

test_filter_narrows_the_run() {
    out=$(cd "$work" && PATH="$stubs:$PATH" make --no-print-directory \
        test filter=pin/requires 2>&1) || status=$?
    assert_ok "test/filter-succeeds" "a filtered run succeeds"
    assert_contains "test/filter-narrows/ran-pin" "$out" "# pin/requires-a-version" \
        "the filtered run includes the matching case"
    assert_not_contains "test/filter-narrows/skipped-clean" "$out" \
        "clean/drops-image-and-network" "the filtered run skips the other targets"
    assert_eq "test/filter-narrows/verdict" "1" \
        "$(printf '%s\n' "$out" | grep -c '^# pin: ' || true)" \
        "and reports a verdict for pin"
    assert_eq "test/filter-narrows/single-verdict" "0" \
        "$(printf '%s\n' "$out" | grep -c '^# clean: ' || true)" \
        "a target with no matching case gets no verdict"
}

case_add "test/filter-narrows" "filter= runs only the matching cases" test_filter_narrows_the_run

test_filter_can_match_nothing() {
    out=$(cd "$work" && PATH="$stubs:$PATH" make --no-print-directory \
        test filter=no-such-case 2>&1) || status=$?
    assert_ok "test/filter-empty/succeeds" "a filter matching nothing succeeds"
    assert_eq "test/filter-empty/no-cases" "0" \
        "$(printf '%s\n' "$out" | grep -c '^# [a-z][a-z0-9-]*/' || true)" "and runs no cases"
    assert_contains "test/filter-empty/only-coverage" "$out" "1..1" \
        "only the coverage check is left"
    assert_eq "test/filter-empty/no-verdicts" "0" \
        "$(printf '%s\n' "$out" | grep -c '^# [a-z][a-z0-9-]*: ' || true)" \
        "and no target gets a verdict"
}

case_add "test/filter-empty" "a filter matching nothing is a no-op" \
    test_filter_can_match_nothing

# ----------------------------------------------------------------- run them

i=0
for name in "${case_names[@]}"; do
    if [ -z "$filter" ] || [[ $name == *"$filter"* ]]; then
        run_case "$i"
    fi
    i=$((i + 1))
done

# ------------------------------------------------------- target coverage

# The suite is only useful while it stays exhaustive, so ask make itself which
# targets exist and fail on any that no case names.
missing=
for t in $(cd "$root" && make -qp 2>/dev/null | awk -F: '/^[a-z][a-z0-9-]*:/ { print $1 }' | sort -u); do
    case " ${case_names[*]} " in
        *" $t/"*) ;;
        *) missing="$missing $t" ;;
    esac
done
if [ -z "$missing" ]; then
    ok "coverage/every-target-has-a-case" "every target in the Makefile has a case"
else
    nope "coverage/every-target-has-a-case" "every target in the Makefile has a case" \
        "no case for:$missing"
    failed_targets+=(coverage)
fi

# ------------------------------------------------------------------ summary

# One verdict per target that ran, in Makefile order, with the failing ones
# called out. `sort -u` collapses the repeated entries a target collects.
for t in $(cd "$root" && make -qp 2>/dev/null | awk -F: '/^[a-z][a-z0-9-]*:/ { print $1 }' | sort -u); do
    grep -qx "$t" <(printf '%s\n' "${ran_targets[@]+"${ran_targets[@]}"}") || continue
    if grep -qx "$t" <(printf '%s\n' "${failed_targets[@]+"${failed_targets[@]}"}"); then
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