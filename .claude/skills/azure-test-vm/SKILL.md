---
name: azure-test-vm
description: Spin up a disposable Azure Linux VM, copy this repo onto it, run commands or tests as root, and delete it. Use when a change must be verified on a real VM (systemd, kernel, networking, packages, install scripts, multi-arch) rather than in this sandbox.
---

# Disposable Azure test VMs

`scripts/azure-test-vm.sh` creates throwaway Ubuntu 24.04 VMs in Azure and drives them through
Azure Run Command. There is no SSH and no public IP: every interaction goes through the script.

## Before you start

- Check the tools are there: `command -v az && test -n "$AZURE_CLIENT_SECRET"`. If `az` is missing,
  the cloud environment's setup script didn't run; tell the user rather than installing ad hoc.
- Run `scripts/azure-test-vm.sh ls` first. Reuse a VM you created earlier in this session
  instead of creating another one.

## Workflow

```bash
VM="t-$(date +%H%M%S)"
scripts/azure-test-vm.sh up "$VM" free          # ~1 min; prints "created <name> (<size>)"
scripts/azure-test-vm.sh push "$VM" . /opt/work  # copies the repo incl. uncommitted edits, excl. .gitignored
scripts/azure-test-vm.sh run "$VM" 'cd /opt/work && ./your-test-command'
scripts/azure-test-vm.sh down "$VM"              # ALWAYS, also after failures
```

- `run` / `runf` exit with the remote command's exit code, so you can judge pass/fail from it.
- `runf <vm> <local-file>` runs a local script file on the VM.

## Sizes

| Alias | Size | Arch | RAM | Cost |
|---|---|---|---|---|
| `free` (default) | Standard_B2pts_v2 | arm64 | 1 GB | free tier |
| `free-x64` | Standard_B2ats_v2 | x86_64 | 1 GB | free tier |
| `4g` | Standard_B2pls_v2 | arm64 | 4 GB | ~$0.034/hr |
| `4g-x64` | Standard_B2als_v2 | x86_64 | 4 GB | ~$0.039/hr |

Start with `free`. Use `4g` only if the work needs more than 1 GB of RAM. Use the x64 sizes only
when the work needs x86_64. Nothing else is allowed: Azure Policy rejects any other size, region,
or a disk over 64 GB with `RequestDisallowedByPolicy`, so don't try to get around it.

## Rules

1. **Always delete what you create.** Run `down` as soon as the test ends, pass or fail. Before
   finishing your turn, run `ls` and confirm none of your VMs remain. Every new cloud session
   deletes VMs older than 3 h as a backstop, but don't rely on it.
2. **At most 2 VMs at once.** The subscription has a 4 vCPU quota and each VM has 2 vCPUs.
3. **One `run` at a time per VM.** Run Command doesn't run in parallel on the same VM.
4. **Output is truncated to the last ~4 KB.** For verbose commands, write the log on the VM and
   print the tail: `run "$VM" 'cd /opt/work && make test > /tmp/t.log 2>&1; rc=$?; tail -n 60 /tmp/t.log; exit $rc'`.
5. **Each `run` takes ~20-40 s of overhead.** Batch several steps into one command or one script
   (`runf`) rather than many small calls.
6. **`push` moves ~150 KB per ~30 s.** Fine for source trees under ~1-2 MB compressed. For a
   public repo, `git clone` inside the VM is faster; the VM has outbound internet.
7. Long commands: Bash has a 10 min default timeout here. For longer tests, run the command in the
   background on the VM (`nohup ... > /tmp/t.log 2>&1 &`) and check it with later `run` calls.

## Errors

- `AllocationFailed`: Azure has no capacity for that size right now. Try the other arch at the same
  RAM (`free` <-> `free-x64`, `4g` <-> `4g-x64`), then retry later. Delete the failed VM with `down`.
  The x64 sizes have often been out of capacity in swedencentral.
- `QuotaExceeded` / `OperationNotAllowed` on cores: too many VMs. Run `ls` and `down` the extras.
- `service principal login failed`: the secret expired or was revoked. Tell the user; you can't fix it.
- `RequestDisallowedByPolicy`: you asked for something the guardrails forbid. Use an allowed size.
- `AuthorizationFailed`: the identity can only manage VMs in `devbox-test-rg`. That's expected; don't try other resources.
