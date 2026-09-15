# devbox

Several agents may be working in this directory at the same time.

## Worktrees

- Do your work in your own git worktree, never in the shared checkout.
- Commit and push from that worktree.
- Bring work back to `main` by rebasing, not merging.
- Leave the shared checkout on `main` and clean.

```sh
git worktree add ../devbox-<task> -b <task>
cd ../devbox-<task>
# work, commit
git push -u origin <task>
git rebase main && git push --force-with-lease
```

Remove the worktree when the branch has landed:

```sh
git worktree remove ../devbox-<task>
```

## Commits

- Commit as soon as one change works, then build the next change on top of it.
- One commit does one thing. Split anything larger.
- Never save up a batch of finished work for a single commit at the end.
