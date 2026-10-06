#!/bin/bash
# Cloud sessions only: install NetBird/herdr/sshd/rsync, start the supervisor.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

NB_VERSION=0.80.0
DIR="$CLAUDE_PROJECT_DIR/.claude/netbird"
STATE=/var/lib/claude-netbird
mkdir -p "$STATE/ssh"

if ! command -v netbird >/dev/null; then
	tmp=$(mktemp -d)
	curl -fsSL "https://github.com/netbirdio/netbird/releases/download/v${NB_VERSION}/netbird_${NB_VERSION}_linux_amd64.tar.gz" | tar -xz -C "$tmp" netbird
	install -m755 "$tmp/netbird" /usr/local/bin/netbird
	rm -rf "$tmp"
fi
if ! command -v sshd >/dev/null || ! command -v rsync >/dev/null; then
	apt-get install -y -q openssh-server rsync >/dev/null 2>&1 ||
		{ apt-get update -q >/dev/null 2>&1 && apt-get install -y -q openssh-server rsync >/dev/null 2>&1; }
fi
command -v herdr >/dev/null || curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR=/usr/local/bin sh >/dev/null 2>&1 || true

# sshd: key-only, your key from the repo; supervisor binds it to the NetBird IP
[ -f "$STATE/ssh/hostkey" ] || ssh-keygen -q -t ed25519 -N "" -f "$STATE/ssh/hostkey"
cp "$DIR/authorized_keys" "$STATE/ssh/authorized_keys"; chmod 600 "$STATE/ssh/authorized_keys"
cat > "$STATE/ssh/sshd_config" <<EOF
ListenAddress 127.0.0.1
Port 22
HostKey $STATE/ssh/hostkey
AuthorizedKeysFile $STATE/ssh/authorized_keys
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
StrictModes no
AllowTcpForwarding no
X11Forwarding no
PidFile $STATE/ssh/sshd.pid
EOF

pgrep -f nb-supervisor.sh >/dev/null ||
	NETBIRD_SETUP_KEY="${NETBIRD_SETUP_KEY:-}" setsid "$DIR/nb-supervisor.sh" >/dev/null 2>&1 < /dev/null &
echo "netbird supervisor running; log: $STATE/supervisor.log"
