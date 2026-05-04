#!/usr/bin/env bash
#
# Unit & integration tests for nathan (git-subcommit)
# Run: ./test.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBCOMMIT="$SCRIPT_DIR/git-subcommit"

assert_pass() {
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}PASS${NC} $1"
}
assert_fail() {
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} $1 — $2"
}

setup_repo() {
    local dir
    dir=$(mktemp -d /tmp/nathan-test.XXXXXX)
    cd "$dir"
    git init >/dev/null 2>&1
    git config user.name "Tester"
    git config user.email "test@test"
    echo "$dir"
}

# ── Test helpers ────────────────────────────────────────────────────────────

run_git() {
    git "$@" 2>/dev/null
}

commit_file() {
    echo "$2" > "$1" 2>/dev/null || echo "$2" >> "$1"
    git add "$1" 2>/dev/null
    git commit -m "$3" >/dev/null 2>&1
}

# ── Test: squash a branch preserves sub-commits ─────────────────────────────

test_squash_branch() {
    echo -e "${CYAN}▶ test_squash_branch${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "README.md" "# Project" "Initial commit"
    git checkout -b feature/xyz >/dev/null 2>&1
    commit_file "a.ts" "const a = 1" "feat: add a"
    commit_file "b.ts" "const b = 2" "feat: add b"
    commit_file "c.ts" "const c = 3" "feat: add c"
    git checkout main >/dev/null 2>&1

    "$SUBCOMMIT" squash feature/xyz >/dev/null 2>&1

    # Main should have exactly 2 commits (initial + squash)
    local main_count
    main_count=$(git rev-list --count main)
    if [[ "$main_count" -eq 2 ]]; then
        assert_pass "main has 2 commits (initial + squashed)"
    else
        assert_fail "main has 2 commits" "got $main_count"
    fi

    # Squashed commit should have a Sub-commit-ref trailer
    if git log -1 --format="%(trailers:key=Sub-commit-ref)" | grep -q "_sub/"; then
        assert_pass "squashed commit has Sub-commit-ref trailer"
    else
        assert_fail "squashed commit has Sub-commit-ref trailer" "missing"
    fi

    # Sub-commit ref should exist and have 3 commits
    local sub_ref
    sub_ref=$(git log -1 --format="%(trailers:key=Sub-commit-ref,valueonly)")
    if git rev-parse --verify "$sub_ref" >/dev/null 2>&1; then
        local sub_count
        sub_count=$(git rev-list --count "$sub_ref" 2>/dev/null)
        if [[ "$sub_count" -eq 4 ]]; then  # includes initial commit
            assert_pass "sub-ref has correct history"
        else
            assert_fail "sub-ref has correct history" "got $sub_count commits"
        fi
    else
        assert_fail "sub-ref exists" "not found: $sub_ref"
    fi

    # File state should match
    if [[ -f a.ts && -f b.ts && -f c.ts ]]; then
        assert_pass "files from sub-commits present on main"
    else
        assert_fail "files from sub-commits present on main" "missing files"
    fi

    rm -rf "$dir"
}

# ── Test: squash --range ───────────────────────────────────────────────────

test_squash_range() {
    echo -e "${CYAN}▶ test_squash_range${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    commit_file "f0.txt" "f0" "commit 0 (padding)"
    commit_file "f1.txt" "f1" "commit 1"
    commit_file "f2.txt" "f2" "commit 2"
    commit_file "f3.txt" "f3" "commit 3"

    local initial
    initial=$(git rev-parse HEAD~3)

    "$SUBCOMMIT" squash --range "${initial}..HEAD" >/dev/null 2>&1

    # Should have 2 commits on main (initial + squash)
    local count
    count=$(git rev-list --count HEAD)
    if [[ "$count" -eq 2 ]]; then
        assert_pass "squash --range reduces to 1 squashed commit"
    else
        assert_fail "squash --range reduces to 1 squashed commit" "got $count"
    fi

    # Sub-commit ref should exist
    local sub_ref
    sub_ref=$(git log -1 --format="%(trailers:key=Sub-commit-ref,valueonly)")
    if [[ -n "$sub_ref" ]]; then
        assert_pass "squash --range creates sub-commit ref"
    else
        assert_fail "squash --range creates sub-commit ref" "missing"
    fi

    rm -rf "$dir"
}

# ── Test: show sub-commits ─────────────────────────────────────────────────

test_show() {
    echo -e "${CYAN}▶ test_show${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "x.ts" "x" "feat: add x"
    commit_file "y.ts" "y" "fix: fix y"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    local output
    output=$("$SUBCOMMIT" show HEAD 2>&1)
    if echo "$output" | grep -q "feat: add x"; then
        assert_pass "show displays sub-commit messages"
    else
        assert_fail "show displays sub-commit messages" "missing 'feat: add x' in output"
    fi
    if echo "$output" | grep -q "fix: fix y"; then
        assert_pass "show displays all sub-commits"
    else
        assert_fail "show displays all sub-commits" "missing 'fix: fix y'"
    fi
    if echo "$output" | grep -q "Sub-commit-ref:"; then
        assert_pass "show displays sub-commit-ref"
    else
        assert_fail "show displays sub-commit-ref" "missing"
    fi

    rm -rf "$dir"
}

# ── Test: show on commit without sub-commits ────────────────────────────────

test_show_no_subcommits() {
    echo -e "${CYAN}▶ test_show_no_subcommits${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    local output
    output=$("$SUBCOMMIT" show HEAD 2>&1)
    if echo "$output" | grep -q "does not reference"; then
        assert_pass "show on plain commit says no sub-commits"
    else
        assert_fail "show on plain commit says no sub-commits" "unexpected output"
    fi

    rm -rf "$dir"
}

# ── Test: unfold creates working branch ─────────────────────────────────────

test_unfold() {
    echo -e "${CYAN}▶ test_unfold${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "a.txt" "a" "sub: a"
    commit_file "b.txt" "b" "sub: b"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1

    local branch
    branch=$(git branch --show-current)
    if [[ "$branch" == _work/* ]]; then
        assert_pass "unfold creates _work/* branch"
    else
        assert_fail "unfold creates _work/* branch" "got '$branch'"
    fi

    # Should see sub-commits in log
    if git log --oneline | grep -q "sub: a"; then
        assert_pass "unfolded branch has sub-commit messages"
    else
        assert_fail "unfolded branch has sub-commit messages" "missing"
    fi

    rm -rf "$dir"
}

# ── Test: drop a sub-commit from unfolded branch ────────────────────────────

test_drop_subcommit() {
    echo -e "${CYAN}▶ test_drop_subcommit${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "keep1.txt" "k1" "feat: keep1"
    commit_file "drop.txt"  "d"  "feat: drop-me"
    commit_file "keep2.txt" "k2" "feat: keep2"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1

    # Drop the commit containing "drop"
    GIT_SEQUENCE_EDITOR="sed -i '/drop/d'" git rebase -i HEAD~3 >/dev/null 2>&1

    # Verify drop-me is gone
    if ! git log --oneline | grep -q "drop-me"; then
        assert_pass "drop sub-commit removed 'drop-me' commit"
    else
        assert_fail "drop sub-commit removed 'drop-me' commit" "still present"
    fi

    if git log --oneline | grep -q "keep1" && git log --oneline | grep -q "keep2"; then
        assert_pass "drop sub-commit keeps other commits intact"
    else
        assert_fail "drop sub-commit keeps other commits intact" "some commits lost"
    fi

    rm -rf "$dir"
}

# ── Test: add a new sub-commit ──────────────────────────────────────────────

test_add_subcommit() {
    echo -e "${CYAN}▶ test_add_subcommit${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "orig1.txt" "o1" "feat: original"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1

    # Add a new sub-commit
    commit_file "added.txt" "new" "feat: newly-added"
    if git log --oneline | grep -q "newly-added"; then
        assert_pass "add sub-commit creates new commit"
    else
        assert_fail "add sub-commit creates new commit" "missing"
    fi

    # Original should still be there
    if git log --oneline | grep -q "original"; then
        assert_pass "add sub-commit preserves original commits"
    else
        assert_fail "add sub-commit preserves original commits" "original lost"
    fi

    rm -rf "$dir"
}

# ── Test: edit a sub-commit (amend) ─────────────────────────────────────────

test_edit_subcommit() {
    echo -e "${CYAN}▶ test_edit_subcommit${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "edit.txt" "original content" "feat: to-edit"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1

    # Amend the sub-commit
    echo "amended content" > edit.txt
    git add edit.txt
    git commit --amend -m "feat: EDITED" >/dev/null 2>&1

    if git log -1 --format="%s" | grep -q "EDITED"; then
        assert_pass "edit sub-commit amends message"
    else
        assert_fail "edit sub-commit amends message" "message not changed"
    fi

    rm -rf "$dir"
}

# ── Test: resquash updates main ─────────────────────────────────────────────

test_resquash() {
    echo -e "${CYAN}▶ test_resquash${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "orig.txt" "orig" "feat: original"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    local old_main_head
    old_main_head=$(git rev-parse main)

    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1
    commit_file "new.txt" "new" "feat: added-after-unfold"

    local sub_id
    sub_id=$(git branch --show-current | sed 's/_work\///')
    "$SUBCOMMIT" resquash "$sub_id" >/dev/null 2>&1

    local new_main_head
    new_main_head=$(git rev-parse main)

    if [[ "$old_main_head" != "$new_main_head" ]]; then
        assert_pass "resquash changes main HEAD"
    else
        assert_fail "resquash changes main HEAD" "HEAD unchanged"
    fi

    if [[ -f new.txt ]]; then
        assert_pass "resquash includes new sub-commit content"
    else
        assert_fail "resquash includes new sub-commit content" "new.txt missing"
    fi

    # Main should still have 2 commits
    local count
    count=$(git rev-list --count main)
    if [[ "$count" -eq 2 ]]; then
        assert_pass "resquash keeps main linear (no extra commits)"
    else
        assert_fail "resquash keeps main linear" "got $count commits"
    fi

    rm -rf "$dir"
}

# ── Test: list sub-commit refs ──────────────────────────────────────────────

test_list() {
    echo -e "${CYAN}▶ test_list${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"

    # Create two squashes
    git checkout -b feat1 >/dev/null 2>&1
    commit_file "f1.txt" "f1" "feat: one"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat1 >/dev/null 2>&1

    git checkout -b feat2 >/dev/null 2>&1
    commit_file "f2.txt" "f2" "feat: two"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat2 >/dev/null 2>&1

    local output
    output=$("$SUBCOMMIT" list 2>&1)

    local ref_count
    ref_count=$(echo "$output" | grep -c "_sub/")
    if [[ "$ref_count" -ge 2 ]]; then
        assert_pass "list shows all sub-commit refs"
    else
        assert_fail "list shows all sub-commit refs" "got $ref_count refs"
    fi

    rm -rf "$dir"
}

# ── Test: list with no sub-commits ──────────────────────────────────────────

test_list_empty() {
    echo -e "${CYAN}▶ test_list_empty${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"

    local output
    output=$("$SUBCOMMIT" list 2>&1)
    if echo "$output" | grep -q "(none)"; then
        assert_pass "list shows (none) when no sub-commits"
    else
        assert_fail "list shows (none) when no sub-commits" "unexpected output"
    fi

    rm -rf "$dir"
}

# ── Test: dirty working tree rejected ───────────────────────────────────────

test_dirty_tree_rejected() {
    echo -e "${CYAN}▶ test_dirty_tree_rejected${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "a.txt" "a" "sub: a"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    # Dirty the tree
    echo "dirty" > dirty.txt

    local output
    set +e
    output=$("$SUBCOMMIT" unfold HEAD 2>&1)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]] && echo "$output" | grep -qi "dirty"; then
        assert_pass "dirty working tree rejected by unfold"
    else
        assert_fail "dirty working tree rejected by unfold" "rc=$rc output=$output"
    fi

    rm -rf "$dir"
}

# ── Test: squash nonexistent branch ─────────────────────────────────────────

test_squash_nonexistent_branch() {
    echo -e "${CYAN}▶ test_squash_nonexistent_branch${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"

    set +e
    local output
    output=$("$SUBCOMMIT" squash nonexistent 2>&1)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        assert_pass "squashing nonexistent branch fails"
    else
        assert_fail "squashing nonexistent branch fails" "unexpected success"
    fi

    rm -rf "$dir"
}

# ── Test: unfold without sub-commit-ref ─────────────────────────────────────

test_unfold_no_ref() {
    echo -e "${CYAN}▶ test_unfold_no_ref${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "a plain commit"

    set +e
    local output
    output=$("$SUBCOMMIT" unfold HEAD 2>&1)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]] && echo "$output" | grep -q "no Sub-commit-ref"; then
        assert_pass "unfold on plain commit fails with clear message"
    else
        assert_fail "unfold on plain commit fails with clear message" "rc=$rc output=$output"
    fi

    rm -rf "$dir"
}

# ── Test: resquash from non-_work branch without id ─────────────────────────

test_resquash_no_id() {
    echo -e "${CYAN}▶ test_resquash_no_id${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"

    set +e
    local output
    output=$("$SUBCOMMIT" resquash 2>&1)
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
        assert_pass "resquash without id or _work/* branch fails"
    else
        assert_fail "resquash without id or _work/* branch fails" "unexpected success"
    fi

    rm -rf "$dir"
}

# ── Test: sub-commit refs survive git gc (reachability) ─────────────────────

test_gc_safety() {
    echo -e "${CYAN}▶ test_gc_safety${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    commit_file "base.txt" "base" "initial"
    git checkout -b feat >/dev/null 2>&1
    commit_file "a.txt" "a" "sub: a"
    git checkout main >/dev/null 2>&1
    "$SUBCOMMIT" squash feat >/dev/null 2>&1

    # Delete the original feature branch
    git branch -D feat >/dev/null 2>&1

    # sub-commit ref should still exist
    local sub_ref
    sub_ref=$(git log -1 --format="%(trailers:key=Sub-commit-ref,valueonly)")
    if git rev-parse --verify "$sub_ref" >/dev/null 2>&1; then
        assert_pass "sub-commit ref survives feature branch deletion"
    else
        assert_fail "sub-commit ref survives feature branch deletion" "ref missing"
    fi

    # Run git gc — sub-commits should stay reachable
    git reflog expire --expire=now --all >/dev/null 2>&1
    git gc --prune=now --aggressive >/dev/null 2>&1

    if git rev-parse --verify "$sub_ref" >/dev/null 2>&1; then
        assert_pass "sub-commit ref survives git gc"
    else
        assert_fail "sub-commit ref survives git gc" "garbage collected!"
    fi

    rm -rf "$dir"
}

# ── Test: end-to-end flow in demo.sh style ──────────────────────────────────

test_e2e_full_flow() {
    echo -e "${CYAN}▶ test_e2e_full_flow${NC}"
    local dir
    dir=$(setup_repo)
    cd "$dir"

    # Setup
    mkdir -p src
    echo "# Project" > README.md
    git add . && git commit -m "Initial commit" >/dev/null 2>&1

    git checkout -b feature/e2e >/dev/null 2>&1
    commit_file "src/a.ts" "a" "feat: add a"
    commit_file "src/b.ts" "b" "feat: add b"
    commit_file "src/c.ts" "c" "feat: add c"
    git checkout main >/dev/null 2>&1

    # Squash
    "$SUBCOMMIT" squash feature/e2e >/dev/null 2>&1
    if [[ $(git rev-list --count main) -eq 2 ]]; then
        assert_pass "e2e: main has 2 commits after squash"
    else
        assert_fail "e2e: main has 2 commits" "got $(git rev-list --count main)"
    fi

    # Unfold
    "$SUBCOMMIT" unfold HEAD >/dev/null 2>&1
    if [[ "$(git branch --show-current)" == _work/* ]]; then
        assert_pass "e2e: unfold creates _work/* branch"
    else
        assert_fail "e2e: unfold creates _work/* branch" "got $(git branch --show-current)"
    fi

    # Drop middle commit
    GIT_SEQUENCE_EDITOR="sed -i '/add b/d'" git rebase -i HEAD~3 >/dev/null 2>&1
    if ! git log --oneline | grep -q "add b"; then
        assert_pass "e2e: dropped middle sub-commit"
    else
        assert_fail "e2e: dropped middle sub-commit" "still there"
    fi

    # Add new commit
    commit_file "src/d.ts" "d" "feat: add d"
    if git log --oneline | grep -q "add d"; then
        assert_pass "e2e: added new sub-commit"
    else
        assert_fail "e2e: added new sub-commit" "missing"
    fi

    # Resquash
    local sub_id
    sub_id=$(git branch --show-current | sed 's/_work\///')
    "$SUBCOMMIT" resquash "$sub_id" >/dev/null 2>&1

    # Verify final state
    if [[ $(git rev-list --count main) -eq 2 ]]; then
        assert_pass "e2e: main still has 2 commits after resquash"
    else
        assert_fail "e2e: main still has 2 commits" "got $(git rev-list --count main)"
    fi

    local show_out
    show_out=$("$SUBCOMMIT" show HEAD 2>&1)
    if echo "$show_out" | grep -q "add a" && echo "$show_out" | grep -q "add c" && echo "$show_out" | grep -q "add d"; then
        assert_pass "e2e: show reflects mutations (a,c,d present, b dropped)"
    else
        assert_fail "e2e: show reflects mutations" "expected a,c,d"
    fi
    if ! echo "$show_out" | grep -q "add b"; then
        assert_pass "e2e: dropped commit not in show output"
    else
        assert_fail "e2e: dropped commit not in show output" "b still present"
    fi

    # Working tree should be clean on main
    if git diff-index --quiet HEAD --; then
        assert_pass "e2e: working tree clean on main"
    else
        assert_fail "e2e: working tree clean on main" "dirty"
    fi

    rm -rf "$dir"
}

# ── Run all tests ───────────────────────────────────────────────────────────

main() {
    echo ""
    echo "════════════════════════════════════════════"
    echo "  nathan (git-subcommit) test suite"
    echo "════════════════════════════════════════════"
    echo ""

    test_squash_branch
    test_squash_range
    test_show
    test_show_no_subcommits
    test_unfold
    test_drop_subcommit
    test_add_subcommit
    test_edit_subcommit
    test_resquash
    test_list
    test_list_empty
    test_dirty_tree_rejected
    test_squash_nonexistent_branch
    test_unfold_no_ref
    test_resquash_no_id
    test_gc_safety
    test_e2e_full_flow

    echo ""
    echo "════════════════════════════════════════════"
    echo -e "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, $((PASS + FAIL)) total"
    echo "════════════════════════════════════════════"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
