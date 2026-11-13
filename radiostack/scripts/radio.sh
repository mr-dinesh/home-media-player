#!/usr/bin/env bash
# radio — run the home radio (Icecast + Liquidsoap + Navidrome) from anywhere.
#
#   radio [up]          start it, wait for audio, print where to listen
#   radio down          stop it
#   radio status        containers, stream, playlist, now playing, listeners
#   radio now           current track
#   radio skip          next track
#   radio play [name]   switch to playlists/<name>.m3u (no name: list them)
#   radio toggle        up if down, down if up (used by the desktop icon)
set -uo pipefail

STACK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
LIQ="$STACK_DIR/liquidsoap/radio.liq"
ICECAST_XML="$STACK_DIR/icecast/icecast.xml"
SERVICES=(icecast liquidsoap navidrome)
STREAM="http://localhost:8000/stream"
ICECAST_CONTAINER_UID="${ICECAST_CONTAINER_UID:-101}"

if [ -t 1 ]; then B=$'\e[1m' G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' D=$'\e[2m' N=$'\e[0m'
else B= G= R= Y= D= N=; fi

dc()   { docker compose --project-directory "$STACK_DIR" "$@"; }
ok()   { echo "${G}✔${N} $*"; }
warn() { echo "${Y}!${N} $*"; }
die()  { echo "${R}✘${N} $*" >&2; exit 1; }

# Dialogs only when launched from the desktop icon: a display, no ssh, no terminal.
gui() { [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -z "${SSH_CONNECTION:-}" ] \
        && [ ! -t 1 ] && command -v zenity >/dev/null; }

say() {  # zenity when launched from the icon, plain text in a terminal or over ssh
  if ! gui; then echo "$1"
  else zenity --info --no-wrap --title="Radio" --text="$1" --timeout=8 2>/dev/null || true; fi  # 5 = timed out
}

streaming() {  # true if Icecast is serving MP3 on /stream
  [ "$(curl -s -o /dev/null -m 3 -w '%{content_type}' "$STREAM" 2>/dev/null)" = "audio/mpeg" ]
}

now_playing() {  # tags if the file has them, else the file name
  local logs title
  logs=$(dc logs --tail 300 liquidsoap 2>/dev/null)
  title=$(grep -o 'Now playing:.*' <<<"$logs" | tail -1 | sed 's/^Now playing: *//')
  if [ -z "${title//[ -]/}" ]; then  # untagged files log "Now playing:  -"
    title=$(grep -o 'Prepared "[^"]*"' <<<"$logs" | tail -1 | sed 's#^Prepared ".*/##; s#\.[^.]*"$##')
  fi
  echo "${title:-unknown}"
}

current_playlist() { grep -o '"/playlists/[^"]*\.m3u"' "$LIQ" | head -1 | sed 's#"/playlists/##; s#\.m3u"##'; }

listeners() {
  curl -s -m 3 http://localhost:8000/status-json.xsl 2>/dev/null | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)["icestats"].get("source", {})
    s = s if isinstance(s, list) else [s]
    print(sum(x.get("listeners", 0) for x in s))
except Exception:
    print("?")'
}

urls() {
  local lan ts
  lan=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -o 'src [0-9.]*' | cut -d' ' -f2)
  ts=$(tailscale ip -4 2>/dev/null | head -1)
  echo "${B}Listen (VLC → Open network stream):${N}"
  [ -n "$lan" ] && echo "  home wifi   http://$lan:8000/stream"
  [ -n "$ts" ]  && echo "  tailscale   http://$ts:8000/stream"
  echo "${D}  Navidrome   http://${ts:-$lan}:4533  (for Symfonium/Tempo, not VLC)${N}"
}

ensure_docker() {  # hermes-lowpower stops docker.socket + docker.service; bring the daemon back
  docker info >/dev/null 2>&1 && return
  echo "docker is stopped (low-power mode stops it), starting it…"
  local sudo=(sudo)
  gui && sudo=(env SUDO_ASKPASS="$HOME/.local/bin/zenity-askpass" ASKPASS_TITLE="Home Radio: start Docker (sudo password)" sudo -A)  # icon: password box
  "${sudo[@]}" systemctl start docker.socket docker.service \
    || die "couldn't start docker (password cancelled?)"
  local i; for i in $(seq 1 15); do docker info >/dev/null 2>&1 && return; sleep 1; done
  die "docker started but isn't answering; check: journalctl -u docker -b"
}

preflight() {
  ensure_docker
  [ -f "$STACK_DIR/.env" ] || die ".env missing: cp .env.example .env, fill it in, run scripts/gen-icecast-config.sh"
  [ -f "$ICECAST_XML" ] || die "icecast.xml missing: run scripts/gen-icecast-config.sh"
  # Icecast runs as uid 101 in its container and can't read a mode-600 file without this.
  if ! getfacl -n -p "$ICECAST_XML" 2>/dev/null | grep -q "^user:${ICECAST_CONTAINER_UID}:r"; then
    setfacl -m "u:${ICECAST_CONTAINER_UID}:r" "$ICECAST_XML" \
      && warn "re-granted Icecast (uid $ICECAST_CONTAINER_UID) read access to icecast.xml" \
      || die "couldn't set the read ACL on icecast.xml (apt install acl?)"
  fi
}

cmd_up() {
  preflight
  if streaming; then ok "already on air"
  else
    echo "starting ${SERVICES[*]}…"
    dc up -d "${SERVICES[@]}" >/dev/null 2>&1 || die "docker compose up failed"
    local i
    for i in $(seq 1 20); do streaming && break; sleep 1; done
    if ! streaming; then
      echo "${R}✘${N} no audio after 20 s. Recent logs:" >&2
      dc logs --tail 6 icecast liquidsoap >&2
      exit 1
    fi
    ok "on air"
  fi
  echo "  playlist    $(current_playlist)"
  echo "  now         $(now_playing)"
  urls
}

cmd_down() {
  dc stop "${SERVICES[@]}" >/dev/null 2>&1 && ok "radio stopped" || die "docker compose stop failed"
}

cmd_status() {
  local svc state
  for svc in "${SERVICES[@]}"; do
    state=$(dc ps -a --format '{{.State}}' "$svc" 2>/dev/null)
    [ "$state" = running ] && ok "$svc" || echo "${R}✘${N} $svc ${D}(${state:-not created})${N}"
  done
  if streaming; then
    ok "stream on air · $(listeners) listener(s)"
    echo "  playlist    $(current_playlist)"
    echo "  now         $(now_playing)"
  else
    echo "${R}✘${N} stream off air — run: radio up"
  fi
}

cmd_skip() {
  streaming || die "radio is off"
  printf 'main_playlist.skip\nquit\n' | nc -w 2 localhost 1234 >/dev/null 2>&1 || die "couldn't reach Liquidsoap telnet on :1234"
  sleep 2
  ok "skipped → $(now_playing)"
}

cmd_play() {
  local name="${1:-}" cur f
  cur=$(current_playlist)
  if [ -z "$name" ]; then
    echo "${B}Playlists${N} (radio play <name>):"
    for f in "$STACK_DIR"/playlists/*.m3u; do
      name=$(basename "$f" .m3u)
      printf '  %s %-16s %4d tracks\n' "$([ "$name" = "$cur" ] && echo "${G}▶${N}" || echo " ")" \
        "$name" "$(grep -vc '^\s*\(#\|$\)' "$f")"
    done
    return
  fi
  name="${name%.m3u}"
  [ -f "$STACK_DIR/playlists/$name.m3u" ] || die "no playlists/$name.m3u (run 'radio play' to list)"
  [ "$name" = "$cur" ] && { ok "already playing $name"; return; }
  sed -i "s#\"/playlists/[^\"]*\.m3u\"#\"/playlists/$name.m3u\"#" "$LIQ"
  dc restart liquidsoap >/dev/null 2>&1 || die "liquidsoap restart failed"
  local i; for i in $(seq 1 15); do streaming && break; sleep 1; done
  sleep 2
  ok "switched $cur → $name · now $(now_playing)"
}

cmd_toggle() {
  if streaming; then cmd_down >/dev/null; say "Radio stopped."
  else
    local out
    if out=$(cmd_up 2>&1); then say "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")"
    else say "Radio failed to start:
$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | tail -8)"; exit 1; fi
  fi
}

case "${1:-up}" in
  up|start)      cmd_up ;;
  down|stop)     cmd_down ;;
  status|st)     cmd_status ;;
  now)           streaming && now_playing || die "radio is off" ;;
  skip|next)     cmd_skip ;;
  play)          cmd_play "${2:-}" ;;
  toggle)        cmd_toggle ;;
  -h|--help|help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)             die "unknown command '$1' (try: radio help)" ;;
esac
