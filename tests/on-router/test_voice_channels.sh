#!/bin/sh
# Isolated lifecycle integration test. Mock runtimes/routes/probe; no network operations.
set -eu
BOOT=${1:-/usr/libexec/netscope-voice-boot}
BASE=$(mktemp -d /tmp/netscope-channel-test.XXXXXX)
case "$BASE" in /tmp/netscope-channel-test.*) ;; *) exit 2;; esac
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
export NETSCOPE_VOICE_ROOT="$BASE/root" NETSCOPE_VOICE_BOOT_RUN="$BASE/run" NETSCOPE_VOICE_LOCK="$BASE/lifecycle.lock"
export NETSCOPE_VPN_MANAGER="$BASE/manager" NETSCOPE_VOICE_ROUTE="$BASE/route" NETSCOPE_VOICE_UDP_PROBE="$BASE/probe" NS_TEST="$BASE"
A=20260101T000000-aaaaaaaaaa;B=20260101T000000-bbbbbbbbbb;OTHER=20260101T000000-cccccccccc
mkdir -p "$BASE/run" "$BASE/root/config/setup/$A" "$BASE/root/config/setup/$B"
touch "$BASE/root/config/setup/$A/hysteria.yaml" "$BASE/root/config/setup/$B/hysteria.yaml"
cat >"$BASE/manager" <<'MOCK'
#!/bin/sh
set -eu
case "$1" in
 status) if [ -f "$NS_TEST/current" ];then printf '{"active":true,"healthy":true,"id":"%s"}\n' "$(cat "$NS_TEST/current")";else echo '{"active":false,"healthy":false,"id":""}';fi;;
 start) [ ! -f "$NS_TEST/fail-$3" ] || exit 1;printf '%s' "$3" >"$NS_TEST/current";echo '{"healthy":true}';;
 confirm) :;;
 stop|rollback) rm -f "$NS_TEST/current";;
esac
MOCK
cat >"$BASE/route" <<'MOCK'
#!/bin/sh
case "$1" in
 start) echo active >"$NS_TEST/route-state";;
 stop) rm -f "$NS_TEST/route-state";;
 status) if [ -f "$NS_TEST/route-state" ];then echo '{"active":true,"healthy":true}';else echo '{"active":false,"healthy":false}';fi;;
esac
MOCK
printf '#!/bin/sh\n[ ! -f "$NS_TEST/probe-fail" ]\n' >"$BASE/probe"
chmod 700 "$BASE/manager" "$BASE/route" "$BASE/probe"
CONF="$BASE/root/config/voice/autostart.conf"
JOURNAL="$BASE/root/config/voice/channel-switch.previous"
check(){ eval "$1" || { echo "FAIL: $2" >&2;exit 1; };echo "PASS: $2"; }
"$BOOT" configure "$A";"$BOOT" reconcile
check '[ "$(cat "$BASE/current")" = "$A" ]' baseline
"$BOOT" switch "$B"
check '[ "$(cat "$BASE/current")" = "$B" ] && grep -q "profile=$B" "$CONF" && [ ! -f "$JOURNAL" ]' switch
touch "$BASE/fail-$A"
if "$BOOT" switch "$A";then echo 'unexpected successful failed-start switch';exit 1;fi
check '[ "$(cat "$BASE/current")" = "$B" ] && [ -f "$BASE/route-state" ]' failed_start_rolls_back
rm "$BASE/fail-$A";touch "$BASE/probe-fail"
if "$BOOT" switch "$A";then echo 'unexpected successful failed-probe switch';exit 1;fi
check '[ "$(cat "$BASE/current")" = "$B" ] && [ -f "$BASE/route-state" ]' failed_probe_rolls_back
rm "$BASE/probe-fail"
cp "$CONF" "$JOURNAL";printf '#target=%s\n' "$A" >>"$JOURNAL";printf '%s' "$A" >"$BASE/current"
"$BOOT" reconcile
check '[ "$(cat "$BASE/current")" = "$B" ] && [ ! -f "$JOURNAL" ]' interrupted_switch_recovery
touch "$BASE/run/user-paused"
if "$BOOT" switch "$A";then echo 'manual pause ignored';exit 1;fi
"$BOOT" reconcile
check '[ "$(cat "$BASE/current")" = "$B" ]' manual_pause_wins
rm "$BASE/run/user-paused";printf '%s' "$OTHER" >"$BASE/current"
if "$BOOT" switch "$A";then echo 'foreign profile replaced';exit 1;fi
check '[ "$(cat "$BASE/current")" = "$OTHER" ] && [ -f "$BASE/route-state" ]' foreign_profile_untouched
echo 'voice channel lifecycle: 7 checks passed'
