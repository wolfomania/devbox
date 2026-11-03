#!/usr/bin/env bash
# Disposable Azure test VMs, driven by the restricted `devbox-test-harness` service principal.
# Azure twin of the AWS devbox-test-harness setup (EC2 + SSM -> VM + Run Command).
#
# Usage:
#   scripts/azure-test-vm.sh up   [name] [size]        create VM (default size: free); prints name
#   scripts/azure-test-vm.sh push <name> [src] [dest]  copy a local dir to the VM (default: . -> /opt/work)
#   scripts/azure-test-vm.sh run  <name> <cmd...>      run shell command as root; exits with its exit code
#   scripts/azure-test-vm.sh runf <name> <file>        run a local script file as root; same exit code rule
#   scripts/azure-test-vm.sh ls                        list test VMs
#   scripts/azure-test-vm.sh down <name>               delete VM + its NIC and OS disk
#   scripts/azure-test-vm.sh reap [hours]              delete VMs older than N hours (default 3, 0 = all)
#
# Sizes (alias or full name), all 2 vCPU:
#   free     Standard_B2pts_v2  ARM  1 GB  free tier
#   free-x64 Standard_B2ats_v2  x64  1 GB  free tier
#   4g       Standard_B2pls_v2  ARM  4 GB  ~$0.034/hr (paid / trial credit)
#   4g-x64   Standard_B2als_v2  x64  4 GB  ~$0.039/hr (paid / trial credit)
#
# Credentials: AZURE_CLIENT_ID + AZURE_CLIENT_SECRET + AZURE_TENANT_ID env vars (cloud sessions),
# otherwise the JSON file at $DEVBOX_TEST_CRED (default ~/.azure/devbox-test-harness.json).
#
# Guardrails (enforced in Azure, not just here):
#   RBAC role  devbox-test-harness    -> only inside resource group devbox-test-rg
#   Policy     devbox-test-guardrails -> only the four sizes above, swedencentral only,
#              tag Project=devbox-test, disk <= 64 GB, no data disks, no public IP
set -euo pipefail

RG="devbox-test-rg"
VNET="devbox-test-vnet"
SUBNET="targets"
CRED_FILE="${DEVBOX_TEST_CRED:-$HOME/.azure/devbox-test-harness.json}"
SSH_PUB="${DEVBOX_TEST_SSH_PUB:-$HOME/.ssh/id_ed25519.pub}"
PUSH_CHUNK_BYTES=150000      # base64 bytes per Run Command call (Run Command scripts are size-limited)
PUSH_WARN_BYTES=5000000      # warn above ~5 MB compressed: each chunk costs ~20-30 s

# Separate CLI profile so the service principal never replaces your own `az login`.
AZURE_CONFIG_DIR="$HOME/.azure-devbox-test"
command -v cygpath >/dev/null 2>&1 && AZURE_CONFIG_DIR="$(cygpath -w "$AZURE_CONFIG_DIR")"
export AZURE_CONFIG_DIR
export MSYS_NO_PATHCONV=1
export AZURE_CORE_ONLY_SHOW_ERRORS=true

die() { echo "error: $*" >&2; exit 1; }

# az and python on Windows need native paths; no-op on Linux/macOS.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

cred_field() {
  python -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" \
    "$(native_path "$CRED_FILE")" "$1"
}

ensure_login() {
  command -v az >/dev/null 2>&1 || die "azure cli (az) not installed"
  az account show -o none 2>/dev/null && return 0
  local id secret tenant
  if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_CLIENT_SECRET:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ]; then
    id="$AZURE_CLIENT_ID"; secret="$AZURE_CLIENT_SECRET"; tenant="$AZURE_TENANT_ID"
  elif [ -f "$CRED_FILE" ]; then
    id="$(cred_field appId)"; secret="$(cred_field password)"; tenant="$(cred_field tenant)"
  else
    die "no credentials: set AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID or create $CRED_FILE"
  fi
  az login --service-principal -u "$id" -p "$secret" --tenant "$tenant" -o none \
    || die "service principal login failed (expired or revoked secret?)"
}

ensure_ssh_pub() {
  [ -f "$SSH_PUB" ] && return 0
  # VMs are reached via Run Command only; the key just satisfies Linux VM creation.
  SSH_PUB="$HOME/.ssh/devbox-test_ed25519.pub"
  [ -f "$SSH_PUB" ] && return 0
  mkdir -p "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C devbox-test -f "${SSH_PUB%.pub}"
}

resolve_size() {
  case "$1" in
    free)     echo "Standard_B2pts_v2" ;;
    free-x64) echo "Standard_B2ats_v2" ;;
    4g)       echo "Standard_B2pls_v2" ;;
    4g-x64)   echo "Standard_B2als_v2" ;;
    *)        echo "$1" ;;
  esac
}

image_for_size() {
  case "$1" in
    *pts_v2|*ps_v2|*pls_v2) echo "Canonical:ubuntu-24_04-lts:server-arm64:latest" ;;
    *) echo "Canonical:ubuntu-24_04-lts:server:latest" ;;
  esac
}

# Runs a local script file on the VM; prints its output and returns its exit code.
# Run Command never reports the script's exit code, so the wrapper echoes it as a marker.
invoke_file() {
  local name="$1" file="$2" out rc
  out="$(az vm run-command invoke -g "$RG" -n "$name" --command-id RunShellScript \
    --scripts "@$(native_path "$file")" --query 'value[0].message' -o tsv)"
  rc="$(printf '%s\n' "$out" | sed -n 's/^__DEVBOX_RC=\([0-9]*\)$/\1/p' | tail -1)"
  printf '%s\n' "$out" | grep -v '^__DEVBOX_RC=' | sed '/^Enable succeeded: *$/d'
  [ -n "$rc" ] || { echo "warning: no exit code returned (output truncated or script killed)" >&2; return 1; }
  return "$rc"
}

invoke_script() {
  local name="$1" body="$2" tmp rc=0
  tmp="$(mktemp)"
  printf '( %s\n)\necho "__DEVBOX_RC=$?"\n' "$body" > "$tmp"
  invoke_file "$name" "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

cmd_up() {
  local name="${1:-test-$(date +%m%d-%H%M%S)}" size owner
  size="$(resolve_size "${2:-free}")"
  owner="${CLAUDE_CODE_REMOTE_SESSION_ID:-$(hostname)}"
  ensure_ssh_pub
  az vm create -g "$RG" -n "$name" \
    --image "$(image_for_size "$size")" --size "$size" \
    --vnet-name "$VNET" --subnet "$SUBNET" --nsg "" --public-ip-address "" \
    --storage-sku Premium_LRS --os-disk-size-gb 64 \
    --os-disk-delete-option Delete --nic-delete-option Delete \
    --admin-username azureuser --ssh-key-values "$(native_path "$SSH_PUB")" \
    --tags Project=devbox-test ManagedBy=devbox-script "Owner=$owner" \
    --query '{privateIp:privateIpAddress, powerState:powerState}' -o json
  echo "created $name ($size)"
}

cmd_push() {
  local name="${1:?vm name}" src="${2:-.}" dest="${3:-/opt/work}" tmp size chunk n=0 total
  [ -d "$src" ] || die "not a directory: $src"
  [[ "$dest" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "dest must be an absolute path of [A-Za-z0-9._/-]: $dest"
  tmp="$(mktemp -d)"
  if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Tracked + untracked-but-not-ignored files, i.e. what you'd commit (incl. uncommitted edits).
    (cd "$src" && git ls-files -z -co --exclude-standard | tar --null -T - -czf "$tmp/p.tgz")
  else
    tar -C "$src" --exclude=.git --exclude=node_modules -czf "$tmp/p.tgz" .
  fi
  size="$(wc -c < "$tmp/p.tgz" | tr -d ' ')"
  [ "$size" -gt "$PUSH_WARN_BYTES" ] && echo "warning: archive is $size bytes; push will be slow" >&2
  base64 -w0 "$tmp/p.tgz" | split -b "$PUSH_CHUNK_BYTES" - "$tmp/chunk."
  total="$(ls "$tmp"/chunk.* | wc -l | tr -d ' ')"
  for chunk in "$tmp"/chunk.*; do
    n=$((n + 1))
    { [ "$n" -eq 1 ] && echo 'rm -f /tmp/devbox-push.b64'
      printf "printf '%%s' '%s' >> /tmp/devbox-push.b64\n" "$(cat "$chunk")"
      echo 'echo "__DEVBOX_RC=$?"'; } > "$tmp/step.sh"
    echo "push: chunk $n/$total" >&2
    invoke_file "$name" "$tmp/step.sh" >/dev/null || { rm -rf "$tmp"; die "push failed at chunk $n"; }
  done
  rm -rf "$tmp"
  invoke_script "$name" "set -e; rm -rf '$dest'; mkdir -p '$dest'
base64 -d /tmp/devbox-push.b64 | tar -xzf - -C '$dest'; rm -f /tmp/devbox-push.b64
echo \"pushed to $dest: \$(find '$dest' -type f | wc -l) files, \$(du -sh '$dest' | cut -f1)\""
}

cmd_run() {
  local name="${1:?vm name}"; shift
  [ $# -gt 0 ] || die "no command given"
  invoke_script "$name" "$*"
}

cmd_runf() {
  local name="${1:?vm name}" file="${2:?script file}"
  [ -f "$file" ] || die "script not found: $file"
  invoke_script "$name" "$(cat "$file")"
}

cmd_ls() {
  az vm list -g "$RG" -d \
    --query '[].{name:name, size:hardwareProfile.vmSize, state:powerState, created:timeCreated, owner:tags.Owner}' \
    -o table
}

cmd_down() {
  local name="${1:?vm name}"
  az vm delete -g "$RG" -n "$name" --yes
  echo "deleted $name"
}

cmd_reap() {
  local hours="${1:-3}" cutoff vm created
  cutoff="$(date -u -d "-$hours hours" +%s)"
  while IFS=$'\t' read -r vm created; do
    [ -n "$vm" ] || continue
    if [ "$(date -u -d "$created" +%s)" -le "$cutoff" ]; then
      az vm delete -g "$RG" -n "$vm" --yes --no-wait
      echo "reaping $vm (created $created)"
    fi
  done < <(az vm list -g "$RG" --query '[].[name, timeCreated]' -o tsv | tr -d '\r')
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    up|push|run|runf|ls|down|reap) ensure_login; "cmd_$sub" "$@" ;;
    *) sed -n '2,26p' "$0"; exit 1 ;;
  esac
}

main "$@"
