#!/bin/sh
# Provision a throwaway EC2 instance, install devbox on it, verify the result,
# then terminate it.
#
#   ./tests/vps/run.sh                          default scenario, working tree
#   ./tests/vps/run.sh --scenario minimal
#   ./tests/vps/run.sh --source github --ref main   test the curl | sh bootstrap
#   ./tests/vps/run.sh --keep                   leave the box up for debugging
#   ./tests/vps/run.sh --bare --ttl 120         a clean box, nothing installed
#   ./tests/vps/run.sh --modules                one module at a time, all of them
#   ./tests/vps/run.sh --modules docker,latex   only these
#
# Credentials come from the instance profile on this box; nothing is read from
# disk. The instance is reached over SSM, so it needs no key pair, no inbound
# security group rule and no SSH client.
#
# Every launched instance carries Project=devbox-test and a shutdown timer, so
# a crashed harness cannot leak a running box.

set -u

# Account-specific settings. The defaults match the account this harness was
# built against; override them in the environment to run it elsewhere. None of
# these are secrets: an IAM role name grants nothing without credentials to
# assume it.
AWS_REGION_DEFAULT="${DVB_TEST_REGION:-eu-central-1}"
INSTANCE_TYPE_DEFAULT="${DVB_TEST_TYPE:-t3.small}"
INSTANCE_PROFILE="${DVB_TEST_PROFILE:-devbox-test-target}"
PROJECT_TAG="${DVB_TEST_TAG:-devbox-test}"
AMI_PARAMETER="/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"

# Root volume must hold the heavy toolchains; the AMI default of 8 GiB will not.
VOLUME_GB=30
# Dead-man's switch: the box halts itself this many minutes after boot, and
# halting terminates it. Survives the harness being killed.
DEADMAN_MINUTES=45
# The SSM agent on Ubuntu is a snap and registers well after the instance is
# reported running.
SSM_WAIT_SECONDS=240
POLL_SECONDS=5
COMMAND_TIMEOUT_SECONDS=3600
# IAM cannot express a concurrency cap, so the harness enforces one.
MAX_CONCURRENT=3

OPT_SCENARIO="default"
OPT_SOURCE="local"
OPT_REF="main"
OPT_REPO="wolfomania/devbox"
OPT_TYPE="$INSTANCE_TYPE_DEFAULT"
OPT_KEEP=0
OPT_BARE=0
OPT_TTL=""
OPT_MODULES=""

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
INSTANCE_ID=""

# --- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$(printf '\033[0m'); C_DIM=$(printf '\033[2m'); C_BOLD=$(printf '\033[1m')
	C_RED=$(printf '\033[31m'); C_GREEN=$(printf '\033[32m'); C_BLUE=$(printf '\033[34m')
else
	C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_BLUE=''
fi

say()  { printf '%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()   { printf '%s  ok%s  %s\n' "$C_GREEN" "$C_RESET" "$*"; }
err()  { printf '%sfail%s  %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
			--scenario) OPT_SCENARIO="${2:-}"; shift ;;
			--source)   OPT_SOURCE="${2:-}"; shift ;;
			--ref)      OPT_REF="${2:-}"; shift ;;
			--repo)     OPT_REPO="${2:-}"; shift ;;
			--instance-type) OPT_TYPE="${2:-}"; shift ;;
			--keep)     OPT_KEEP=1 ;;
			# A clean box and nothing else: launch, wait for SSM, hand it
			# over. Nothing is installed and nothing is terminated.
			--bare)     OPT_BARE=1; OPT_KEEP=1 ;;
			--ttl)      OPT_TTL="${2:-}"; shift ;;
			# Install modules one at a time rather than running install.sh.
			# The argument is optional: with none, every module in the
			# manifest. This is the tier for the modules a container cannot
			# hold, docker above all.
			--modules)
				OPT_MODULES="all"
				case "${2:-}" in
					-*|"") ;;
					*) OPT_MODULES="$2"; shift ;;
				esac
				;;
			-h|--help)  usage ;;
			*) die "unknown option: $1  (try --help)" ;;
		esac
		shift
	done

	case "$OPT_SOURCE" in
		local|github) ;;
		*) die "--source must be local or github" ;;
	esac

	if [ -n "$OPT_TTL" ]; then
		case "$OPT_TTL" in
			''|*[!0-9]*) die "--ttl takes whole minutes" ;;
		esac
		DEADMAN_MINUTES="$OPT_TTL"
	fi
}

# --- preflight -------------------------------------------------------------

preflight() {
	command -v aws >/dev/null 2>&1 || die "aws cli is not installed"
	PY="$(command -v python3 || true)"
	[ -n "$PY" ] || die "python3 is required to build SSM parameter documents"

	AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION_DEFAULT}"
	export AWS_DEFAULT_REGION

	caller="$(aws sts get-caller-identity --query Arn --output text 2>&1)" ||
		die "no usable AWS credentials: $caller"
	dim "caller  $caller"
	dim "region  $AWS_DEFAULT_REGION"

	scenario_file="$ROOT_DIR/tests/vps/scenarios/${OPT_SCENARIO}.env"
	[ -r "$scenario_file" ] || die "no such scenario: $OPT_SCENARIO"
	# shellcheck source=/dev/null
	. "$scenario_file"
	dim "scenario $OPT_SCENARIO  (user ${SCENARIO_USER}, flags ${SCENARIO_FLAGS})"
}

# Refuse to exceed the concurrency cap the IAM policy cannot express.
check_concurrency() {
	running="$(aws ec2 describe-instances \
		--filters "Name=tag:Project,Values=$PROJECT_TAG" \
		          "Name=instance-state-name,Values=pending,running" \
		--query 'length(Reservations[].Instances[])' --output text 2>/dev/null)"
	[ -n "$running" ] || running=0
	if [ "$running" -ge "$MAX_CONCURRENT" ]; then
		die "$running test instances already running, cap is $MAX_CONCURRENT"
	fi
	[ "$running" -gt 0 ] && dim "$running test instance(s) already running"
	return 0
}

# --- lifecycle -------------------------------------------------------------

terminate_instance() {
	[ -n "$INSTANCE_ID" ] || return 0
	if [ "$OPT_KEEP" -eq 1 ]; then
		printf '\n'
		dim "--keep given; $INSTANCE_ID left running (it self-terminates in ${DEADMAN_MINUTES}m)"
		dim "connect:   aws ssm start-session --target $INSTANCE_ID"
		dim "terminate: aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
		return 0
	fi
	say "Terminating $INSTANCE_ID"
	aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" \
		--query 'TerminatingInstances[0].CurrentState.Name' --output text 2>&1 |
		sed 's/^/    /'
	INSTANCE_ID=""
}

launch() {
	say "Launching $OPT_TYPE"

	ami="$(aws ssm get-parameter --name "$AMI_PARAMETER" \
		--query Parameter.Value --output text 2>&1)" ||
		die "could not resolve the Ubuntu AMI: $ami"

	subnet="$(aws ec2 describe-subnets --filters Name=default-for-az,Values=true \
		--query 'Subnets[0].SubnetId' --output text 2>&1)"
	[ -n "$subnet" ] && [ "$subnet" != "None" ] ||
		die "no default subnet found; the instance needs outbound 443 for SSM"

	dim "ami     $ami"
	dim "subnet  $subnet"

	# user-data arms the dead-man's switch and warns anyone who logs in. The
	# test itself runs over SSM so that its output is visible and attributable.
	# The banner matters: this box can be terminated at any moment by the
	# harness that created it, and without it an interactive session just
	# freezes mid-command with no explanation.
	user_data="$(cat <<'CLOUDINIT'
#!/bin/sh
cat > /etc/motd <<'BANNER'

  ********************************************************************
  *  DISPOSABLE devbox TEST INSTANCE                                 *
  *                                                                  *
  *  Created by tests/vps/run.sh. It is terminated as soon as that   *
  *  run finishes, and self-terminates DEADMAN minutes after boot.   *
  *                                                                  *
  *  Do not do real work here, and do not run devbox by hand while   *
  *  a test is in flight: your commands will race the harness and    *
  *  the machine can vanish underneath you.                          *
  ********************************************************************

BANNER
cp /etc/motd /etc/update-motd.d/00-devbox-test-banner 2>/dev/null || true
chmod -x /etc/update-motd.d/00-devbox-test-banner 2>/dev/null || true
shutdown -h +DEADMAN
CLOUDINIT
	)"
	user_data="$(printf '%s' "$user_data" | sed "s/DEADMAN/$DEADMAN_MINUTES/g")"

	INSTANCE_ID="$(aws ec2 run-instances \
		--image-id "$ami" \
		--instance-type "$OPT_TYPE" \
		--subnet-id "$subnet" \
		--iam-instance-profile "Name=$INSTANCE_PROFILE" \
		--instance-initiated-shutdown-behavior terminate \
		--block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_GB,VolumeType=gp3}" \
		--user-data "$user_data" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=$PROJECT_TAG},{Key=Name,Value=devbox-test-$OPT_SCENARIO}]" \
		--query 'Instances[0].InstanceId' --output text 2>&1)" ||
		die "run-instances failed: $INSTANCE_ID"

	case "$INSTANCE_ID" in
		i-*) ;;
		*) die "run-instances returned no instance id: $INSTANCE_ID" ;;
	esac

	trap 'terminate_instance' EXIT INT TERM
	ok "$INSTANCE_ID"
}

wait_for_ssm() {
	say "Waiting for the SSM agent to register"
	waited=0
	while [ "$waited" -lt "$SSM_WAIT_SECONDS" ]; do
		ping="$(aws ssm describe-instance-information \
			--filters "Key=InstanceIds,Values=$INSTANCE_ID" \
			--query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)"
		if [ "$ping" = "Online" ]; then
			ok "agent online after ${waited}s"
			return 0
		fi
		sleep "$POLL_SECONDS"
		waited=$((waited + POLL_SECONDS))
	done
	die "the SSM agent did not register within ${SSM_WAIT_SECONDS}s"
}

# --- remote execution ------------------------------------------------------

# Run a script on the instance. Reads the script body from stdin, streams back
# stdout and stderr, and returns the remote exit status.
remote_sh() {
	label="$1"
	body_file="$WORK_DIR/remote.sh"
	cat > "$body_file"

	"$PY" - "$body_file" "$label" > "$WORK_DIR/params.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    body = handle.read()
json.dump({"commands": [body]}, sys.stdout)
PYEOF

	command_id="$(aws ssm send-command \
		--instance-ids "$INSTANCE_ID" \
		--document-name AWS-RunShellScript \
		--comment "$label" \
		--timeout-seconds 600 \
		--parameters "file://$WORK_DIR/params.json" \
		--query Command.CommandId --output text 2>&1)" || {
		err "send-command failed: $command_id"
		return 1
	}

	waited=0
	while [ "$waited" -lt "$COMMAND_TIMEOUT_SECONDS" ]; do
		invocation_status="$(aws ssm get-command-invocation \
			--command-id "$command_id" --instance-id "$INSTANCE_ID" \
			--query Status --output text 2>/dev/null)"
		case "$invocation_status" in
			Success|Failed|Cancelled|TimedOut) break ;;
		esac
		sleep "$POLL_SECONDS"
		waited=$((waited + POLL_SECONDS))
	done

	aws ssm get-command-invocation \
		--command-id "$command_id" --instance-id "$INSTANCE_ID" \
		--output json 2>/dev/null > "$WORK_DIR/invocation.json"
	"$PY" - "$WORK_DIR/invocation.json" <<'PYEOF' | sed 's/^/    /'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for key in ("StandardOutputContent", "StandardErrorContent"):
    text = data.get(key) or ""
    if text.strip():
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
PYEOF

	[ "$invocation_status" = "Success" ]
}

push_source() {
	say "Shipping the working tree"
	# The whole payload travels inside one SSM command, which has a size
	# limit, so the box gets the provisioner and tests/module-case.sh and not
	# the harness that launched it.
	payload="$(tar --exclude=.git --exclude=tests/vps --exclude=__pycache__ \
		-czf - -C "$ROOT_DIR" . | base64 -w0)"
	dim "$(printf '%s' "$payload" | wc -c) bytes of base64"

	remote_sh "push-source" <<REMOTE
set -eu
rm -rf /opt/devbox-src
mkdir -p /opt/devbox-src
printf '%s' '$payload' | base64 -d | tar -xz -C /opt/devbox-src
chown -R ${SCENARIO_USER}:${SCENARIO_USER} /opt/devbox-src 2>/dev/null || true
chmod +x /opt/devbox-src/install.sh
echo "unpacked \$(find /opt/devbox-src -type f | wc -l) files"
REMOTE
}

install_devbox() {
	say "Installing (as $SCENARIO_USER)"
	if [ "$OPT_SOURCE" = "github" ]; then
		remote_sh "install-from-github" <<REMOTE
set -eu
export DVB_REPO='$OPT_REPO' DVB_REF='$OPT_REF'
runuser -l '$SCENARIO_USER' -c "DVB_REPO='$OPT_REPO' DVB_REF='$OPT_REF' \\
  curl -fsSL 'https://raw.githubusercontent.com/$OPT_REPO/$OPT_REF/install.sh' | sh -s -- $SCENARIO_FLAGS"
REMOTE
	else
		remote_sh "install-from-worktree" <<REMOTE
set -eu
runuser -l '$SCENARIO_USER' -c "cd /opt/devbox-src && ./install.sh $SCENARIO_FLAGS"
REMOTE
	fi
}

# Install every module on its own, in manifest order, and report each one.
#
# Running them one at a time on one box is not the same isolation a container
# gives, but it is the only way to reach the modules a container cannot hold,
# and a module that only works because an earlier one happened to leave
# something behind shows up here as a check that passed before its install.
run_modules() {
	say "Installing modules one at a time (as root)"
	wanted="$OPT_MODULES"
	[ "$wanted" != "all" ] || wanted=""

	remote_sh "modules" <<REMOTE
set -u
cd /opt/devbox-src
export DVB_TEST_DISPOSABLE=1
wanted='$(printf '%s' "$wanted" | tr ',' ' ')'
[ -n "\$wanted" ] || wanted="\$(DVB_MANIFEST=manifests python3 tui/manifest.py ids | tr '\n' ' ')"

failed=""
for id in \$wanted; do
	printf '\n--- %s\n' "\$id"
	if sh tests/module-case.sh "\$id"; then
		:
	else
		failed="\$failed \$id"
	fi
done

printf '\n'
if [ -n "\$failed" ]; then
	printf 'modules failed:%s\n' "\$failed"
	exit 1
fi
printf 'every module installed and reported its own version\n'
REMOTE
}

verify() {
	say "Verifying"
	assert_body="$(cat "$ROOT_DIR/tests/vps/assert.sh")"
	remote_sh "assert" <<REMOTE
set -eu
cat > /opt/devbox-assert.sh <<'ASSERT_EOF'
$assert_body
ASSERT_EOF
chmod +x /opt/devbox-assert.sh
DVB_EXPECT='$SCENARIO_EXPECT' DVB_USER='$SCENARIO_USER' DVB_SRC=/opt/devbox-src \\
  DVB_FLAGS='$SCENARIO_FLAGS' \\
  sh /opt/devbox-assert.sh
REMOTE
}

# --- main ------------------------------------------------------------------

main() {
	parse_args "$@"
	preflight
	check_concurrency

	WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devbox-vps.XXXXXX")"
	trap 'rm -rf "$WORK_DIR"; terminate_instance' EXIT INT TERM

	started="$(date +%s)"
	launch
	wait_for_ssm

	if [ "$OPT_BARE" -eq 1 ]; then
		printf '\n'
		ok "clean box ready, nothing installed"
		printf '  connect:      aws ssm start-session --target %s\n' "$INSTANCE_ID"
		printf '  become ubuntu: sudo -iu ubuntu\n'
		printf '  terminate:    aws ec2 terminate-instances --instance-ids %s\n' "$INSTANCE_ID"
		printf '  self-destructs in %s minutes\n' "$DEADMAN_MINUTES"
		exit 0
	fi

	status=0
	if [ "$OPT_SOURCE" = "local" ]; then
		push_source || status=1
	fi

	if [ -n "$OPT_MODULES" ]; then
		[ "$OPT_SOURCE" = "local" ] || die "--modules needs the working tree; drop --source github"
		[ "$status" -eq 0 ] && { run_modules || status=1; }
	else
		[ "$status" -eq 0 ] && { install_devbox || status=1; }
		[ "$status" -eq 0 ] && { verify || status=1; }
	fi

	elapsed=$(( $(date +%s) - started ))
	printf '\n'
	label="scenario '$OPT_SCENARIO'"
	[ -z "$OPT_MODULES" ] || label="per-module run"
	if [ "$status" -eq 0 ]; then
		ok "$label passed in ${elapsed}s"
	else
		err "$label failed after ${elapsed}s"
	fi
	exit "$status"
}

main "$@"
