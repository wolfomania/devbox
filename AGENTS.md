# devbox

Several agents may be working in this directory at the same time.

## Worktrees and pull requests

Workflow per request: worktree and remote branch -> work -> pull request -> rebase merge -> cleanup.

- Create a worktree on a new branch from `origin/main`.
- Push the branch to `origin` when the worktree is created.
- Work, commit, and push only in that worktree.
- Open a GitHub pull request before merging.
- Never land a request on `main` locally.
- Merge the pull request with rebase. No approval is required.
- Remove the worktree and the local branch after the merge.
- Leave the shared checkout on `main`, clean and pulled.

```sh
git fetch origin
git worktree add ../devbox-<task> -b <task> origin/main
cd ../devbox-<task>
git push -u origin <task>
# work, commit, push
git rebase origin/main && git push --force-with-lease
gh pr create --base main --head <task> --title "<type>: <summary>" --body "<changes>"
gh pr merge <task> --rebase --delete-branch
```

After the merge:

```sh
cd ../devbox
git worktree remove ../devbox-<task>
git branch -D <task>
git pull --ff-only
```

## Commits

- Commit as soon as one change works, then build the next change on top of it.
- One commit does one thing. Split anything larger.
- Never save up a batch of finished work for a single commit at the end.

## Tests

Three tiers. Run the first before every commit, the second after touching a
module or the libraries it uses, the third before a release and for the
modules a container cannot hold.

| Tier | Command | Needs | Time |
|---|---|---|---|
| Selection screen | `python3 tests/tui/test_selection.py` | python3 | ~15s |
| Prompt between installs | `python3 tests/shell/test_prompt.py` | python3 | ~1s |
| One module per container | `./tests/modules/run.sh` | docker | ~10 min |
| One module per real box | `./tests/vps/run.sh --modules` | aws cli, an EC2 instance | ~20 min, costs money |
| Whole-install scenarios | `./tests/vps/run.sh --scenario minimal` | aws cli, an EC2 instance | ~10 min, costs money |

Every module runs on its own, which is what the last three tiers do:

```sh
./modules/lang/go.sh check      # print the installed version, or exit 1
./modules/lang/go.sh install    # install it, then exit
./modules/lang/go.sh version    # print the version it is pinned to
```

`tests/module-case.sh <id>` is one module's whole test: `check` must fail,
`install` must succeed, `check` must then print a version. It installs software
for real, so it refuses to run outside a container unless the box is marked
`DVB_TEST_DISPOSABLE=1`.

Bundle parts are tested the same way and named by file:
`./tests/modules/run.sh ripgrep`.

Both module runners read the manifest and the parts directory, so a new module
or a new part needs no new test. Four modules are handled differently:

- `docker` needs a real machine. `./tests/vps/run.sh --modules docker` covers it.
- `swap` needs a real machine too, for the same reason: `/proc/meminfo` is not
  namespaced and `swapon` in a container touches the host.
  `./tests/vps/run.sh --modules swap` covers it.
- `firewall` runs in its container with `NET_ADMIN`, so ufw changes the
  container's own network namespace and never the host's.
- `latex` is 2.4 GB and is skipped unless you ask: `./tests/modules/run.sh --all`.

Both screen tests are driven through a real pty, because what broke them was
the bytes a terminal sends: an arrow key for the selection screen, and a `q`
with no newline behind it for the prompt between installs. `tests/tui/drive.py` can also
be used by hand:

```sh
python3 tests/tui/drive.py DOWN DOWN SPACE ENTER
```

## Backlog

- `docs/direction.md`: chosen product direction and 6-month roadmap.
- `docs/backlog.md`: candidate modules in priority order.
- `docs/matrix-os-gaps.md`: box-setup features from Matrix OS that devbox lacks.
- `docs/private/` is git-ignored. Never commit it or quote it in public files.
