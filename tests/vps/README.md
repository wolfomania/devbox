# VPS tests

These tests provision a real, throwaway EC2 instance, install devbox on it,
verify the result and terminate the instance. They exist because devbox targets
a fresh VPS, and a container cannot honestly stand in for one: `/proc/meminfo`
is not namespaced, so the low-memory swap path never triggers, and `swapon`
either fails or, under `--privileged`, modifies the host.

Use the Docker tests for fast iteration. Use these before a release, and any
time a change touches `lib/swap.sh`, `lib/paths.sh` or the bootstrap.

## Running

```sh
./tests/vps/run.sh                       # default scenario, current working tree
./tests/vps/run.sh --scenario minimal    # core + Python only, about 2 minutes
./tests/vps/run.sh --scenario root       # install as root rather than via sudo
./tests/vps/run.sh --source github --ref main   # exercise the curl | sh bootstrap
./tests/vps/run.sh --keep                # leave the box up to debug it
```

With `--keep`, connect to the surviving instance with:

```sh
aws ssm start-session --target i-...
```

## How it works

1. Resolves the current Ubuntu 24.04 AMI from the SSM public parameter store,
   so no AMI id is ever hardcoded.
2. Launches one `t3.small` tagged `Project=devbox-test`.
3. Waits for the SSM agent to register, which takes about 20 seconds.
4. Ships the working tree as a base64 tarball through `ssm send-command`
   (about 29 KB, well under the 100 KB parameter limit), or skips this step
   entirely under `--source github`.
5. Runs `install.sh` as the scenario's user.
6. Runs `assert.sh` on the box.
7. Terminates the instance.

There is no SSH, no key pair and no inbound security group rule. Everything
goes over SSM, which needs only outbound 443 from the instance.

## What the assertions check

`assert.sh` deliberately does **not** trust `install.sh --list`. The installer's
own probe sources `~/.config/devbox/env.sh` by hand before checking, so it
reports a tool as present even when the shell wiring a real user depends on is
broken. Instead it checks, as the target user:

- every expected command resolves in a **login** shell (`~/.profile`)
- every expected command resolves in an **interactive** shell (`~/.bashrc`)
  — these are separate hooks and fail independently
- the managed `env.sh` exists and at least one profile sources it
- re-running with the same flags is a no-op
- installing as a non-root user left nothing behind in `/root`

## AWS setup

Two IAM roles are needed. Neither their names nor the region are secret; they
are recorded here so the harness can be reproduced in another account.

**Target role** — assumed by the temporary test instances so the harness can
reach them over SSM:

```sh
aws iam create-role --role-name devbox-test-target \
  --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
    "Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name devbox-test-target \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name devbox-test-target
aws iam add-role-to-instance-profile --instance-profile-name devbox-test-target \
  --role-name devbox-test-target
```

**Caller policy** — `iam-policy.json` in this directory. Attach it to whatever
role the harness runs as. On the machine this was built for, that is the
instance profile already on the dev box:

```sh
aws iam create-policy --policy-name devbox-test-harness \
  --policy-document file://tests/vps/iam-policy.json
aws iam attach-role-policy --role-name <your-dev-box-role> \
  --policy-arn arn:aws:iam::<account>:policy/devbox-test-harness
```

The policy is deliberately narrow. It can only launch instances tagged
`Project=devbox-test`, no larger than `t3.medium`, with a root volume of at
most 40 GiB, and it can only terminate instances already carrying that tag. It
cannot touch anything else in the account. The ARNs in it are region-scoped to
`eu-central-1`; edit them to run elsewhere.

## Credentials

None are stored and none belong in this repository. The AWS CLI reads
short-lived credentials from the instance profile via IMDS. If you run the
harness somewhere without an instance profile, use any standard credential
source — an SSO profile, or an assumed role — but never a static access key.

## Configuration

| Variable | Default |
|---|---|
| `DVB_TEST_REGION` | `eu-central-1` |
| `DVB_TEST_PROFILE` | `devbox-test-target` |
| `DVB_TEST_TAG` | `devbox-test` |
| `DVB_TEST_TYPE` | `t3.small` |

## Safety

IAM has no condition key for instance count, so the three-instance cap is
enforced by the harness, which refuses to launch when three are already
running. Two independent mechanisms stop a box from outliving its test:

- the harness traps `EXIT`, `INT` and `TERM` and terminates the instance
- each instance runs `shutdown -h +45` from user-data, and is launched with
  `--instance-initiated-shutdown-behavior terminate`, so it destroys itself
  even if the harness is killed with `SIGKILL`

To sweep anything that somehow survives both:

```sh
aws ec2 describe-instances \
  --filters Name=tag:Project,Values=devbox-test \
            Name=instance-state-name,Values=pending,running \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

## Cost

A `t3.small` in eu-central-1 is about $0.023/hour. The `minimal` scenario takes
just over two minutes, so a run costs well under a cent.
