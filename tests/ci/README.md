# CI tests

`run.sh` runs the VPS tier on the machine it runs on, with the checks `tests/vps/run.sh` makes on EC2.
`.github/workflows/vps.yml` runs it on GitHub's hosted runners, each job on a fresh `ubuntu-24.04` VM.

## Running

Run it only on a machine you can throw away. It installs software as root and changes the system.

```sh
export DVB_TEST_DISPOSABLE=1
./tests/ci/run.sh --modules                # every module, one at a time
./tests/ci/run.sh --modules docker,swap    # only these
./tests/ci/run.sh --modules --shard 2/4    # modules 2, 6, 10, ... of the manifest
./tests/ci/run.sh --scenario minimal       # install.sh as the scenario's user, then assert.sh
```

- Scenarios are the files in `tests/vps/scenarios/`.
- The tree is copied to `/opt/devbox-src` first, as the EC2 harness does.
- A scenario user the machine lacks, such as `ubuntu` on a runner, is created with passwordless sudo.
- Each module's output goes to `$DVB_TEST_LOGS`, default `/tmp/devbox-logs`.
- `GITHUB_TOKEN`, when set, is passed to the modules for GitHub API calls.

## The workflow

- 4 jobs split every module with `--shard`.
- 4 jobs run the `default`, `minimal`, `full` and `root` scenarios.
- Runs on pull requests that touch the provisioner or these tests, and on demand from the Actions tab.
- Failed jobs upload the module logs as an artifact.

## Limits

A runner is not a fresh VPS:

- The runner image comes with many tools installed. A module whose tool is already there is still installed, with a note.
- The runner has 16 GB of memory, so `swap` finds enough memory and creates no swapfile. `./tests/vps/run.sh --modules swap` covers that path.
