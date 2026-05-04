#!/usr/bin/env bash
#
# Demo: full nathan (git-subcommit) workflow in a fresh repo
# Run: ./demo.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

say() { echo -e "${CYAN}▸ $*${NC}"; }
ok()  { echo -e "${GREEN}✓ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(mktemp -d /tmp/nathan-demo.XXXXXX)"
trap 'rm -rf "$DEMO_DIR"' EXIT

say "Setting up demo repo in $DEMO_DIR"
cd "$DEMO_DIR"
git init
git config user.name "Demo"
git config user.email "demo@example.com"

# ── Step 1: Create initial commit on main ───────────────────────────────────

say "Step 1: Create base commit on main"
echo "# My Project" > README.md
git add README.md
git commit -m "Initial commit"
ok "Base commit created"

# ── Step 2: Simulate AI generating micro-commits on a feature branch ───────
# Each commit touches a DIFFERENT file —  so dropping any one won't conflict

say "Step 2: AI generates micro-commits on feature/auth"

git checkout -b feature/auth

mkdir -p src

echo "## Auth" >> README.md
git add README.md
git commit -m "docs: add auth section stub"

echo 'export const hashPassword = (pw: string) => "hashed:" + pw;' > src/hash.ts
git add src/hash.ts
git commit -m "feat: add password hashing"

echo 'export const login = async (u: string, p: string) => ({ token: "abc" });' > src/login.ts
git add src/login.ts
git commit -m "feat: add login endpoint"

echo 'export const logout = () => localStorage.removeItem("token");' > src/logout.ts
git add src/logout.ts
git commit -m "feat: add logout"

echo 'export const validateSession = (t: string) => t === "abc";' > src/session.ts
git add src/session.ts
git commit -m "fix: add session validation"

echo 'export const refreshToken = () => "new-token";' > src/refresh.ts
git add src/refresh.ts
git commit -m "feat: add token refresh"

say "Feature branch log (6 commits above main):"
git log --oneline main..HEAD
ok "Feature branch ready"

# ── Step 3: Squash onto main ───────────────────────────────────────────────

say "Step 3: Squash feature/auth onto main with sub-commit preservation"
git checkout main
"$SCRIPT_DIR/git-subcommit" squash feature/auth
ok "Squashed onto main"

say "Main branch log (2 commits — clean!):"
git log --oneline

# ── Step 4: Show sub-commits ───────────────────────────────────────────────

say "Step 4: Show what's inside the squashed commit"
"$SCRIPT_DIR/git-subcommit" show HEAD

# ── Step 5: Unfold, drop logout, add password reset ────────────────────────

say "Step 5: Unfold sub-commits, drop 'logout', add 'password reset'"

"$SCRIPT_DIR/git-subcommit" unfold HEAD

say "Dropping 'feat: add logout' via rebase (no conflicts — separate files)..."
# Use GIT_SEQUENCE_EDITOR to drop the line containing 'logout'
GIT_SEQUENCE_EDITOR="sed -i '/logout/d'" git rebase -i HEAD~6
ok "Dropped logout commit"

say "Adding a new sub-commit..."
echo 'export const resetPassword = (email: string) => "reset-link-sent";' > src/reset.ts
git add src/reset.ts
git commit -m "feat: add password reset"
ok "Added password reset commit"

say "Modified sub-commits (5 total, logout gone, reset added):"
git log --oneline main..

# ── Step 6: Re-squash ─────────────────────────────────────────────────────

say "Step 6: Re-squash back onto main"

# Get the sub id from the branch name
SUB_ID=$(git branch --show-current | sed 's/_work\///')
"$SCRIPT_DIR/git-subcommit" resquash "$SUB_ID"
ok "Re-squashed"

say "Final main branch (still 2 commits, clean!):"
git log --oneline

say "Sub-commits inside HEAD (logout gone, password reset added):"
"$SCRIPT_DIR/git-subcommit" show HEAD

# ── Step 7: Show sub-refs ─────────────────────────────────────────────────

say "Step 7: List all sub-commit refs"
"$SCRIPT_DIR/git-subcommit" list

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DEMO COMPLETE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  main branch:     2 clean commits"
echo "  sub-commits:     5 micro-commits preserved under _sub/*"
echo "  mutations:       dropped 'logout', added 'password reset'"
echo "  tool:            no merge commits, pure linear history"
echo ""
echo "  Explore:  cd $DEMO_DIR && git log --all --oneline --graph"
echo "═══════════════════════════════════════════════════════"
