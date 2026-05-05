# nathan

**Sub-commit management on top of git.**

AI generates lots of granular commits. Squashing them all loses history. Merging with `--no-ff` still floods `git log` unless you always pass `--first-parent`. nathan gives you the best of both:

- **main stays clean** — one squashed commit per logical change
- **micro-commits are preserved** — stored on namespaced `_sub/<id>` branches
- **mutation is possible at any time** — checkout, edit, drop, add, re-squash

---

## How it works

```
main:      P1 ──── S1 ──────── P2 ──── S2
                  /                /
_sub/id1:   a1─a2─a3             /
_sub/id2:                   b1─b2─b3

S1 = squash(a1, a2, a3)     message carries "Sub-commit-ref: _sub/id1"
S2 = squash(b1, b2, b3)     message carries "Sub-commit-ref: _sub/id2"
```

Each squashed commit on main carries a git **trailer** pointing to a `_sub/<id>` branch.
That branch is a normal git branch — just namespaced — containing the original micro-commits.

Because the `_sub/*` refs exist, the micro-commits are **reachable** and won't get garbage-collected.
They can be pushed, fetched, and shared just like regular branches.

---

## Real workflow

### 1. Squash a feature branch (initial capture)

```bash
# You have a branch with AI-generated commits
git checkout -b feature/auth
# ... AI makes: a1, a2, a3
git commit -m "fix: add password hashing"
git commit -m "feat: add login endpoint"
git commit -m "fix: session management"

# Squash it onto main, preserving sub-commits
git checkout main
git subcommit squash feature/auth
# → Creates _sub/20240504-120000-abc
# → Squashes a1+a2+a3 into one commit on main
# → Commit message includes: Sub-commit-ref: refs/heads/_sub/20240504-120000-abc
```

### 2. See what's inside a squashed commit

```bash
git subcommit show HEAD
# ═╤═ Squashed commit: f3a1b2c Add authentication system
#  ║  Sub-commit-ref:  refs/heads/_sub/20240504-120000-abc
#  ║
#  ║  Sub-commits:
#  ║    • a1b2c3d fix: add password hashing
#  ║    • d4e5f6a feat: add login endpoint
#  ║    • g7h8i9j fix: session management
#  ║
# ═╧═ git subcommit unfold HEAD    # to edit sub-commits
```

### 3. Modify sub-commits (drop, add, edit)

```bash
# Unfold: checkout the sub-commits as a working branch
git subcommit unfold HEAD
# → Creates _work/20240504-120000-abc
# → You are now on that branch with all 3 sub-commits

# Normal git! Drop the second commit:
git rebase -i HEAD~3
# → Delete the "feat: add login endpoint" line → save → exit

# Or add a new commit:
echo "new feature" >> file && git add file && git commit -m "feat: password reset"

# Or edit an existing one:
git rebase -i HEAD~3
# → Mark one as "edit" → amend → rebase --continue

# All normal git. Nothing special.
```

### 4. Re-squash back onto main

```bash
git subcommit resquash
# → Updates the _sub/ ref to point to your modified chain
# → Creates a new squashed commit replacing the old one
# → Rebases any commits that were on main after the old squash

git log --oneline main
# f3a1b2c Add authentication system   ← old (replaced)
# g4h5i6j Add authentication system   ← new (rebased)
```

### 5. Adopt an existing commit (migrate to sub-commit structure)

```bash
# Take a regular commit (no Sub-commit-ref) and migrate it
# This happens transparently — the commit message gains the trailer,
# child commits are automatically rebased.
git subcommit adopt HEAD
# → Creates _sub/<id> from HEAD
# → Replaces HEAD with same tree + message + Sub-commit-ref trailer
# → If HEAD has children, they are rebased onto the new commit

# Now you can treat it like any squashed commit:
git subcommit show HEAD
git subcommit unfold HEAD    # edit sub-commits
git subcommit resquash       # re-squash
```

This is useful when you have an existing commit that wasn't created
via `git subcommit squash` but you want to start managing its
micro-commits with nathan. Run `adopt`, then `unfold`, add more
commits, and `resquash`.

### 6. Push / share

```bash
# Push sub-commit refs alongside regular refs
git subcommit push origin

# Collaborators fetch them
git subcommit fetch origin
```

---

## All commands

| Command | Purpose |
|---|---|
| `git subcommit squash <branch>` | Squash a branch, save sub-commits to `_sub/<id>` |
| `git subcommit squash --range HEAD~3..` | Squash last N commits on current branch |
| `git subcommit adopt <commit>` | Migrate a plain commit to the sub-commit structure |
| `git subcommit show <commit>` | Show sub-commit log inside a squashed commit |
| `git subcommit unfold <commit>` | Checkout sub-commits as `_work/<id>` for editing |
| `git subcommit resquash [<id>]` | Re-squash after mutating sub-commits |
| `git subcommit log <commit>` | Full `git log` of sub-commits |
| `git subcommit list` | List all sub-commit refs |
| `git subcommit push [remote]` | Push `_sub/*` refs |
| `git subcommit fetch [remote]` | Fetch `_sub/*` refs |

---

## Key properties

- **Zero lock-in.** Squashed commits are ordinary commits. Sub-commit refs are ordinary branches. Anyone who clones the repo without the tool just sees clean history. Trailer metadata is just text in the commit message.

- **GC-safe.** `refs/heads/_sub/*` keeps sub-commits reachable. They won't be garbage-collected.

- **Rebase-compatible.** If main is rebased, squashed commit hashes change, but the `Sub-commit-ref` trailer still points to the correct `_sub/<id>` (the id is timestamp-based, not hash-based).

- **Normal git inside sub-commits.** `git log`, `git diff`, `git rebase -i`, `git cherry-pick` — all work fine inside `_sub/*` or `_work/*` branches.

- **No merge commits.** Unlike the `--no-ff` merge approach, main stays truly linear.

---

## Comparison to other approaches

| Approach | Clean main? | Preserves micro-commits? | Editable later? | No tooling needed? |
|---|---|---|---|---|
| Plain squash | ✅ | ❌ | ❌ | ✅ |
| `--no-ff` merge | ✅ (with `--first-parent`) | ✅ | ⚠️ branch must be kept | ✅ |
| nathan | ✅ | ✅ | ✅ | ❌ (needs this script) |
| Plain history | ❌ | ✅ | ✅ | ✅ |

---

## Installation

```bash
# Copy to PATH
cp git-subcommit /usr/local/bin/git-subcommit
chmod +x /usr/local/bin/git-subcommit

# Verify
git subcommit --help
```

---

## Edge cases handled

| Scenario | How it works |
|---|---|
| Sub-commit ref not pushed | `git subcommit show` warns; `unfold` fails with explanation |
| Working tree dirty during adopt/resquash | Refuses; tells you to stash |
| Commit already has Sub-commit-ref | `adopt` refuses with clear message; use `unfold` instead |
| Root commit (no parent) | `adopt` creates the sub-ref from the root commit; `show`/`log` handle it gracefully |
| Commits on main after the squashed commit | Rebased automatically onto new squash |
| Rebase conflicts during resquash | Drops into interactive rebase resolution |
| Multiple sub-commit refs | `git subcommit list` shows all with their squashed commit |
| Orphaned sub-refs (squashed commit deleted) | Listed as orphaned in `list`, can be manually attached |
