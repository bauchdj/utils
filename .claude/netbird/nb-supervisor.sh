#!/bin/bash
# Keeps NetBird up and peer-reachable in a Claude Code cloud container.
# Through NetBird cloud relays this container often fails to meet a peer
# (both sides stay "Connecting"); restarting NetBird lands on another relay
# and after a few tries a peer connects. Loop: poke peers, cycle relays until
# at least one peer is Connected, then keep checking. Also runs sshd on the
# NetBird IP.
set -u
STATE=/var/lib/claude-netbird
LOG=$STATE/supervisor.log
SSHD_DIR=$STATE/ssh
CHECK_INTERVAL=60
CONNECT_WAIT=40
BACKOFF_AFTER=20
BACKOFF_SLEEP=300

mkdir -p "$STATE"
log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }

nb_field() { # $1 = python expr over `netbird status --json` as d
	timeout 10 netbird status --json 2>/dev/null | python3 -I -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
print($1)" 2>/dev/null
}

ensure_daemon() {
	timeout 10 netbird status >/dev/null 2>&1 && return
	log "starting netbird daemon"
	setsid netbird service run --log-file "$STATE/netbird.log" >/dev/null 2>&1 < /dev/null &
	timeout 20 bash -c 'until [ -S /var/run/netbird.sock ]; do sleep 1; done'
}

ensure_up() {
	[ "$(nb_field "d['management']['connected']")" = "True" ] && return 0
	if [ -n "${NETBIRD_SETUP_KEY:-}" ]; then
		timeout 60 netbird up --setup-key "$NETBIRD_SETUP_KEY" >/dev/null 2>&1
	else
		timeout 30 netbird up --no-browser >/dev/null 2>&1 < /dev/null
	fi
	[ "$(nb_field "d['management']['connected']")" = "True" ]
}

ensure_sshd() {
	local ip
	ip=$(nb_field "d['netbirdIp'].split('/')[0]")
	[ -n "$ip" ] && [ -f "$SSHD_DIR/sshd_config" ] || return
	if pgrep -f "sshd -f $SSHD_DIR/sshd_config" >/dev/null; then
		grep -q "^ListenAddress $ip$" "$SSHD_DIR/sshd_config" && return
		pkill -f "sshd -f $SSHD_DIR/sshd_config"
	fi
	sed -i "s/^ListenAddress .*/ListenAddress $ip/" "$SSHD_DIR/sshd_config"
	mkdir -p /run/sshd
	/usr/sbin/sshd -f "$SSHD_DIR/sshd_config" -E "$SSHD_DIR/sshd.log"
	sleep 1
	# bind fails until the NetBird interface has its IP; retried next loop
	pgrep -f "sshd -f $SSHD_DIR/sshd_config" >/dev/null && log "sshd on $ip:22"
}

home_relay() { timeout 10 netbird status -d 2>/dev/null | grep -oE 'rels://[^]]+' | head -1; }
connected_count() { nb_field "sum(p['status']=='Connected' for p in d['peers']['details'])"; }

poke_peers() { # outbound traffic wakes lazy connections
	local pids=()
	for ip in $(nb_field "' '.join(p['netbirdIp'] for p in d['peers']['details'])"); do
		timeout 2 bash -c "</dev/tcp/$ip/22" >/dev/null 2>&1 &
		pids+=($!)
	done
	# wait only for the pokes; a bare `wait` would block on the netbird daemon
	[ ${#pids[@]} -gt 0 ] && wait "${pids[@]}"
}

wait_connected() {
	local end=$((SECONDS + CONNECT_WAIT)) n
	while [ $SECONDS -lt $end ]; do
		n=$(connected_count)
		[ "${n:-0}" -gt 0 ] && return 0
		sleep 3
	done
	return 1
}

switch_relay() {
	timeout 20 netbird down >/dev/null 2>&1
	ensure_up
	timeout 20 bash -c 'until netbird status -d 2>/dev/null | grep -q "Available via"; do sleep 1; done'
	log "relay cycle $fails -> $(home_relay)"
}

log "supervisor start (pid $$)"
fails=0
while true; do
	ensure_daemon
	if ! ensure_up; then
		log "not logged in: set NETBIRD_SETUP_KEY or run 'netbird up' for SSO"
		sleep 30; continue
	fi
	ensure_sshd
	poke_peers
	if wait_connected; then
		[ $fails -gt 0 ] && log "connected via $(home_relay) after $fails cycle(s)"
		fails=0; sleep "$CHECK_INTERVAL"; continue
	fi
	fails=$((fails + 1))
	[ $fails -gt $BACKOFF_AFTER ] && sleep "$BACKOFF_SLEEP"
	switch_relay
done
