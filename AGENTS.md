# devbox

Several agents may be working in this directory at the same time.

## Worktrees

Every request follows the same workflow: new worktree -> work -> rebase -> delete worktree.

- Do your work in your own git worktree, never in the shared checkout.
- Commit and push from that worktree.
- Once the request is implemented, bring work back to `main` by rebasing, not merging.
- Push the changes.
- Remove the worktree.
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
or a new part needs no new test. Three modules are handled differently:

- `docker` needs a real machine. `./tests/vps/run.sh --modules docker` covers it.
- `swap` needs a real machine too, for the same reason: `/proc/meminfo` is not
  namespaced and `swapon` in a container touches the host.
  `./tests/vps/run.sh --modules swap` covers it.
- `latex` is 2.4 GB and is skipped unless you ask: `./tests/modules/run.sh --all`.

Both screen tests are driven through a real pty, because what broke them was
the bytes a terminal sends: an arrow key for the selection screen, and a `q`
with no newline behind it for the prompt between installs. `tests/tui/drive.py` can also
be used by hand:

```sh
python3 tests/tui/drive.py DOWN DOWN SPACE ENTER
```
