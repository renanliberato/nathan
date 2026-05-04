---
name: git-subcommit
description: Edit squashed commits on main by unfolding micro-commits into a working branch, mutating them with normal git operations (rebase -i, amend, cherry-pick, commit), then re-squashing. Use when the user mentions "git subcommit", "subcommit", "unfold", "resquash", wants to edit a squashed commit, drop/add/edit individual commits inside a squashed commit, or says "edit the commit on main hash using git subcommit".
---

# Git Subcommit (nathan)

## Overview

`git subcommit` is a custom git tool (part of project **nathan**) that preserves micro-commit history inside squashed commits on main. A squashed commit carries a `Sub-commit-ref` trailer pointing to a `_sub/<id>` branch containing the original micro-commits.

Available at `/usr/local/bin/git-subcommit`. Installed in this repo as `./git-subcommit`.

## Core Concepts

```
main:      P1 ──── S1 ──────── P2 ──── S2
                  /                /
_sub/id1:   a1─a2─a3             /
_sub/id2:                   b1─b2─b3
```

- **`_sub/<id>`** — branch preserving the original micro-commit chain (GC-safe, pushable)
- **`_work/<id>`** — working branch created by `unfold` for editing micro-commits
- **`Sub-commit-ref:`** — git trailer in the squashed commit message linking to `_sub/<id>`

## Commands

| Command | Purpose |
|---|---|
| `git subcommit squash <branch>` | Squash a branch onto current, save micro-commits to `_sub/<id>` |
| `git subcommit squash --range <start>..` | Squash a range of commits on current branch |
| `git subcommit show <commit>` | Show micro-commit log inside a squashed commit |
| `git subcommit unfold <commit>` | Check out micro-commits as `_work/<id>` for editing |
| `git subcommit resquash [<id>]` | Re-squash mutated micro-commits back onto main |
| `git subcommit log <commit>` | Full `git log` of micro-commits |
| `git subcommit list` | List all `_sub/*` refs |
| `git subcommit push [remote]` | Push all `_sub/*` refs |
| `git subcommit fetch [remote]` | Fetch all `_sub/*` refs |

## Workflows

### Workflow A: Squash a Feature Branch (ingest micro-commits)

```bash
# 1. Create feature branch with granular commits
git checkout -b feature/my-feature
# ... make commits ...

# 2. Squash onto main, preserving micro-commits
git checkout main
git subcommit squash feature/my-feature
```

### Workflow B: Edit a Squashed Commit on Main (unfold → mutate → resquash)

Use this when the user says "edit the commit on main hash using git subcommit".

```bash
# 1. Inspect what's inside the squashed commit
git subcommit show <hash>          # see micro-commits

# 2. Unfold — creates _work/<id> branch with micro-commits checked out
git subcommit unfold <hash>

# 3. Mutate micro-commits using normal git operations:
#    Drop a commit:
GIT_SEQUENCE_EDITOR="sed -i '' '/<pattern-to-drop>/d'" git rebase -i HEAD~<N>
#    Add a new sub-commit:
echo "code" > file && git add file && git commit -m "feat: description"
#    Amend the tip sub-commit:
echo "new content" > file && git add file && git commit --amend -m "new message"
#    Interactive rebase to reorder / squash / edit:
git rebase -i HEAD~<N>

# 4. Detect sub id from the _work/* branch:
SUB_ID=$(git branch --show-current | sed 's/_work\///')

# 5. Re-squash back onto main:
git subcommit resquash "$SUB_ID"

# 6. Verify:
git log --oneline main             # main stays clean
git subcommit show HEAD            # see updated micro-commits
```

### Workflow C: Drop a Specific Sub-Commit

```bash
git subcommit unfold <hash>
GIT_SEQUENCE_EDITOR="sed -i '' '/drop-me/d'" git rebase -i HEAD~<N>
SUB_ID=$(git branch --show-current | sed 's/_work\///')
git subcommit resquash "$SUB_ID"
```

### Workflow D: Add a New Sub-Commit

```bash
git subcommit unfold <hash>
echo "content" > newfile && git add newfile && git commit -m "feat: new thing"
SUB_ID=$(git branch --show-current | sed 's/_work\///')
git subcommit resquash "$SUB_ID"
```

### Workflow E: Squash Last N Commits on Current Branch

```bash
git subcommit squash --range HEAD~N..
```

### Workflow F: Verify / Investigate

```bash
git subcommit list                  # all _sub/* refs with their squashed commits
git subcommit show <hash>           # micro-commits inside a squashed commit
git subcommit log <hash>            # full git log of micro-commits
```

## Guardrails

> **Safety rules the agent MUST follow before any subcommit operation:**

1. **Check state first** — Run `git status --short --branch` and `git log --oneline --decorate -n 12` before rewriting history.
2. **Working tree must be clean** — `git subcommit` commands (squash, unfold, resquash) reject dirty trees. Stash or commit changes first: `git stash --include-untracked`.
3. **Backup the branch** — Before resquashing, consider creating a backup ref: `git branch backup/_before-resquash main` or similar.
4. **Same branch safety** — After unfold, you are on a `_work/<id>` branch. Do not switch back to main while you have pending mutations. The `resquash` command handles the switch automatically.
5. **Resquash resquash** — After resquash, `git subcommit show HEAD` to verify the result. If wrong, restore from the backup ref.
6. **Rebase conflicts** — If `resquash` encounters conflicts during rebase of subsequent commits, resolve each conflict, `git add` the resolved files, `git rebase --continue`. Do not skip or abort without user approval.
7. **Remote branches** — Rewriting squashed commits changes hashes. If main is published, warn the user about `--force-with-lease` before proceeding.
8. **Commit exists but no hash given** — If user says "edit the commit on main" without a hash, resolve to `main` (the tip of main). If they specify a hash, use that exact hash.
