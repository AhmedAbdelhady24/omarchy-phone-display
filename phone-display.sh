#!/usr/bin/env bash
# Runtime state is private and scoped to the compositor, never sourced as code.
set -Eeuo pipefail
umask 077
export LC_ALL=C

OUTPUT=PHONE-DISPLAY
APP=com.gaurav.avnc
SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
SESSION=${HYPRLAND_INSTANCE_SIGNATURE:-no-session}
SESSION=${SESSION//[^a-zA-Z0-9_.-]/_}
RUNTIME=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omarchy-phone-display-$SESSION
mkdir -p -- "$RUNTIME"
[[ -O $RUNTIME && ! -L $RUNTIME ]] || exit 1
chmod 700 "$RUNTIME"
STATE=$RUNTIME/state.json
PIDFILE=$RUNTIME/wayvnc.pid
LOG=$RUNTIME/wayvnc.log
serial= pid= born= token= resolution= reverse=false monitor=false app=false
width=1080 height=2400 position=right-of scale=1.5 hz=60 orientation=fixed

die() { printf 'phone-display: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing $1. Install: omarchy pkg add wayvnc android-tools jq iproute2 util-linux"; }
for dep in jq timeout flock; do need "$dep"; done

load_state() {
  [[ -f $STATE ]] || return 0
  local values
  values=$(jq -er '[.serial, (.pid|tostring), .born, .token, .resolution,
    (.reverse|tostring), (.monitor|tostring), (.app|tostring),
    (.width // "1080"), (.height // "2400"), (.position // "right-of"),
    (.scale // "1.5"), (.hz // "60"), (.orientation // "fixed")] | @tsv' "$STATE") || die 'Invalid runtime state; inspect state.json.'
  IFS=$'\t' read -r serial pid born token resolution reverse monitor app width height position scale hz orientation <<<"$values"
}

save_state() {
  jq -n --arg serial "$serial" --arg pid "$pid" --arg born "$born" \
    --arg token "$token" --arg resolution "$resolution" \
    --argjson reverse "$reverse" --argjson monitor "$monitor" --argjson app "$app" \
    --arg width "$width" --arg height "$height" --arg position "$position" --arg scale "$scale" --arg hz "$hz" --arg orientation "$orientation" \
    '{serial:$serial,pid:$pid,born:$born,token:$token,resolution:$resolution,
      reverse:$reverse,monitor:$monitor,app:$app,width:$width,height:$height,
      position:$position,scale:$scale,hz:$hz,orientation:$orientation}' > "$STATE.tmp"
  mv -f -- "$STATE.tmp" "$STATE"
}

process_birth() {
  local stat
  [[ $1 =~ ^[1-9][0-9]*$ && -r /proc/$1/stat ]] || return 1
  stat=$(<"/proc/$1/stat")
  stat=${stat##*) }
  # After the comm field, starttime is the twentieth field.
  awk '{if ($1 != "Z") print $20}' <<<"$stat"
}

own_process() {
  [[ -n $born && $(process_birth "$pid") == "$born" ]] || return 1
  local -a args=()
  mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || return 1
  # The private control socket binds the PID to this instance, even in tests.
  local arg
  for arg in "${args[@]}"; do [[ $arg != "$RUNTIME/control" ]] || return 0; done
  return 1
}

adb_phone() { timeout 6 adb -s "$serial" "$@"; }

choose_phone() {
  local devices
  devices=$(timeout 6 adb devices -l) || die 'ADB failed. Check USB debugging and USB permissions.'
  # usb: rejects wireless-debugging and emulator transports, including mDNS IDs.
  mapfile -t phones < <(awk '$2 == "device" && / usb:/ {print $1}' <<<"$devices")
  if [[ -n ${ANDROID_SERIAL:-} ]]; then
    serial=$ANDROID_SERIAL
    printf '%s\n' "${phones[@]}" | grep -Fxq -- "$serial" || die 'ANDROID_SERIAL is not an authorized USB device.'
  else
    ((${#phones[@]} == 1)) || die 'Connect and authorize exactly one USB phone (or set ANDROID_SERIAL).'
    serial=${phones[0]}
  fi
  [[ $(adb_phone get-state 2>/dev/null) == device ]] || die 'Accept the USB debugging authorization on the phone.'
}

connected() {
  command -v adb >/dev/null || return 1
  if [[ -n $serial ]]; then
    [[ $(adb_phone get-state 2>/dev/null) == device ]] || return 1
    timeout 6 adb devices -l 2>/dev/null | awk -v s="$serial" '$1 == s && $2 == "device" && / usb:/ {ok=1} END {exit !ok}'
  else
    local devices
    devices=$(timeout 6 adb devices -l 2>/dev/null) || return 1
    awk '$2 == "device" && / usb:/ {n++} END {exit n != 1}' <<<"$devices"
  fi
}

monitors() { timeout 4 hyprctl -j monitors all; }
monitor_exists() { monitors 2>/dev/null | jq -e --arg o "$OUTPUT" 'any(.[]; .name == $o)' >/dev/null; }
hypr() {
  local reply
  reply=$(timeout 6 hyprctl "$@") || return 1
  # Some hyprctl errors have historically returned exit status zero.
  [[ $reply == ok* ]] || { printf '%s\n' "$reply" >&2; return 1; }
}

listener() {
  ss -Hlnpt '( sport = :5900 )' 2>/dev/null
}
own_listener() {
  local line
  while IFS= read -r line; do
    [[ $line == *"127.0.0.1:5900"* && $line == *"pid=$pid,"* ]] && return 0
  done < <(listener)
  return 1
}

stop_session() {
  local failed=false
  # Kill the encoder before removing the monitor: wayvnc otherwise selects
  # another output automatically when its selected output disappears.
  if [[ $app == true ]] && connected; then
    adb_phone shell am force-stop "$APP" >/dev/null 2>&1 || failed=true
  fi
  if own_process; then
    kill -TERM "$pid" 2>/dev/null || true
    for ((i=0; i<30; i++)); do own_process || break; sleep 0.1; done
    if own_process; then kill -KILL "$pid" 2>/dev/null || failed=true; fi
  fi
  if [[ $reverse == true ]]; then
    # A disconnected phone loses reverse mappings with its ADB transport.
    if connected; then
      adb_phone reverse --remove tcp:5900 >/dev/null 2>&1 || failed=true
    fi
  fi
  if [[ $monitor == true ]]; then
    if ! monitors >/dev/null 2>&1; then
      # A dead compositor cannot retain a headless output.
      [[ ! -S ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock ]] || failed=true
    elif monitor_exists; then
      hypr output remove "$OUTPUT" >/dev/null || failed=true
    fi
  fi
  if [[ $failed == true ]]; then
    printf 'phone-display: Cleanup incomplete; run stop again.\n' >&2
    return 1
  fi
  rm -f -- "$STATE" "$PIDFILE" "$RUNTIME/control"
}

show_status() {
  local active=false usb=false res=''
  connected && usb=true
  if [[ $usb == true ]] && own_process && monitor_exists && own_listener; then
    active=true
    res=$resolution
  fi
  jq -cn --argjson active "$active" --argjson usb "$usb" --arg res "$res" \
    '{active:$active,adb_connected:$usb,resolution:$res}'
}

read_options() {
  width=${1:-1080} height=${2:-2400} position=${3:-right-of} scale=${4:-1.5} hz=${5:-60} orientation=${6:-fixed}
  [[ $# -le 7 ]] || die 'Usage: start [width] [height] [position] [scale] [hz] [orientation] [keep-awake]'
  [[ ${7:-false} == true || ${7:-false} == false ]] || die 'Keep-awake must be true or false.'
  if [[ $width == native && $height == native ]]; then
    need adb
    choose_phone
    local native
    native=$(adb_phone shell wm size | sed -nE 's/.*size: ([0-9]+x[0-9]+).*/\1/p' | tail -1)
    width=${native%x*} height=${native#*x}
  fi
  [[ $width =~ ^[1-9][0-9]{2,3}$ && $height =~ ^[1-9][0-9]{2,3}$ ]] || die 'Width and height must be integers between 320 and 7680.'
  ((width >= 320 && width <= 7680 && height >= 320 && height <= 7680)) || die 'Resolution outside 320–7680.'
  [[ $scale =~ ^[1-4]([.][0-9]{1,3})?$ ]] || die 'Scale must be 1 through 4.'
  [[ $hz == 60 || $hz == 90 || $hz == 120 ]] || die 'Refresh rate must be 60, 90, or 120.'
  jq -en --argjson w "$width" --argjson h "$height" --argjson s "$scale" \
    '$s <= 4 and (($w / $s | floor) == ($w / $s)) and (($h / $s | floor) == ($h / $s))' >/dev/null || die 'Scale must divide both dimensions into whole logical pixels.'
  [[ $position == left-of || $position == right-of || $position =~ ^-?[0-9]{1,6}x-?[0-9]{1,6}$ ]] || die 'Position must be left-of, right-of, or XxY.'
  [[ $orientation == fixed || $orientation == portrait || $orientation == landscape || $orientation == auto ]] || die "Invalid orientation."
}

phone_orientation() {
  local info
  info=$(adb_phone shell 'dumpsys input | grep -m 1 -E "Viewport.*displayId=0,|SurfaceOrientation:"' 2>/dev/null) || return 1
  if [[ $info =~ logicalFrame=\[([0-9]+),[[:space:]]*([0-9]+),[[:space:]]*([0-9]+),[[:space:]]*([0-9]+)\] ]]; then
    if ((BASH_REMATCH[3]-BASH_REMATCH[1] > BASH_REMATCH[4]-BASH_REMATCH[2])); then echo landscape; else echo portrait; fi
  elif [[ $info =~ SurfaceOrientation:[[:space:]]*([0-3]) ]]; then
    if ((BASH_REMATCH[1] % 2)); then echo landscape; else echo portrait; fi
  else return 1; fi
}

apply_monitor() {
  local actual_width=$width actual_height=$height wanted=$orientation displays xy
  if [[ $wanted == auto ]]; then
    wanted=$(phone_orientation) || wanted=fixed
  fi
  if [[ $wanted == portrait && $actual_width -gt $actual_height || $wanted == landscape && $actual_width -lt $actual_height ]]; then
    actual_width=$height actual_height=$width
  fi
  displays=$(monitors) || return 1
  if [[ $position == left-of || $position == right-of ]]; then
    xy=$(jq -er --arg p "$position" --argjson w "$actual_width" --argjson s "$scale" '
      [.[] | select(.disabled != true and .name != "PHONE-DISPLAY")] |
      if length == 0 then error("No desktop outputs") else
        map(. + {lw: ((if (.transform % 2) == 1 then .height else .width end) / .scale | round)}) |
        if $p == "left-of" then min_by(.x) | "\((.x - $w/$s)|floor)x\(.y)"
        else max_by(.x + .lw) | "\((.x + .lw)|ceil)x\(.y)" end
      end' <<<"$displays") || return 1
  else xy=$position; fi
  if [[ $orientation == auto && $position =~ ^-?[0-9]+x-?[0-9]+$ ]]; then
    # Keep an attached left/top edge attached when rotation changes its size.
    xy=$(jq -er --arg xy "$xy" --arg o "$OUTPUT" --argjson w "$actual_width" --argjson h "$actual_height" --argjson s "$scale" '
      . as $all | [.[] | select(.name == $o)][0] as $old |
      ($xy | split("x") | map(tonumber)) as $pos |
      if $old == null or ($old.width == $w and $old.height == $h) then $xy else
        [$all[] | select(.name != $o and .disabled != true) |
          if (.x == ($old.x + $old.width/$old.scale)) and ($old.y < .y+.height/.scale) and ($old.y+$old.height/$old.scale > .y) then
            "\((.x-$w/$s)|round)x\($pos[1])"
          elif (.y == ($old.y + $old.height/$old.scale)) and ($old.x < .x+.width/.scale) and ($old.x+$old.width/$old.scale > .x) then
            "\($pos[0])x\((.y-$h/$s)|round)"
          else empty end][0] // $xy
      end' <<<"$displays") || return 1
    position=$xy
  fi
  local configure
  configure=$(timeout 6 hyprctl keyword monitor "$OUTPUT,${actual_width}x${actual_height}@${hz},$xy,$scale" 2>&1) || true
  if [[ $configure == *"non-legacy parsers"* ]]; then
    # Values are constrained above before inserting them into Lua source.
    hypr eval "hl.monitor({output=\"$OUTPUT\",mode=\"${actual_width}x${actual_height}@${hz}\",position=\"$xy\",scale=$scale})" >/dev/null || return 1
  elif [[ $configure != ok* ]]; then
    { printf 'Hyprland monitor configuration failed: %s\n' "$configure" >&2; return 1; }
  fi
  local ready=false
  for ((i=0; i<40; i++)); do
    if monitors | jq -e --arg o "$OUTPUT" --argjson w "$actual_width" --argjson h "$actual_height" --argjson s "$scale" --argjson hz "$hz" \
      'any(.[]; .name == $o and .width == $w and .height == $h and .scale == $s and ((.refreshRate - $hz)|fabs) < 1)' >/dev/null; then ready=true; break; fi
    sleep 0.1
  done
  [[ $ready == true ]] || { printf 'Hyprland did not apply the requested monitor mode.\n' >&2; return 1; }
  resolution=${actual_width}x${actual_height}@${hz}
}

configure_session() {
  [[ -f $STATE ]] && own_process && monitor_exists || die 'Start the display before applying layout changes.'
  local previous_hz=$hz
  read_options "$@"
  local previous
  previous=$(cat "$STATE")
  [[ $hz == "$previous_hz" ]] || die 'Stop the display before changing refresh rate.'
  if apply_monitor; then save_state; else
    printf '%s\n' "$previous" > "$STATE.tmp"
    mv -f "$STATE.tmp" "$STATE"
    load_state
    apply_monitor || true
    die 'Could not apply display settings; restored the previous configuration.'
  fi
}

inspect_setup() {
  local missing=() dep devices='' usb=false installed=false native='' rotation='' views='[]' phone_orientation_value=''
  for dep in wayvnc adb hyprctl ss nohup; do command -v "$dep" >/dev/null || missing+=("$dep"); done
  if command -v adb >/dev/null; then
    if choose_phone_quiet=$(timeout 6 adb devices -l 2>/dev/null); then
      devices=$choose_phone_quiet
      mapfile -t candidates < <(awk '$2 == "device" && / usb:/ {print $1}' <<<"$devices")
      if ((${#candidates[@]} == 1)); then
        serial=${candidates[0]}; usb=true
        adb_phone shell pm path "$APP" 2>/dev/null | grep -q '^package:' && installed=true
        native=$(adb_phone shell wm size 2>/dev/null | sed -nE 's/.*size: ([0-9]+x[0-9]+).*/\1/p' | tail -1)
        rotation=$(adb_phone shell settings get system accelerometer_rotation 2>/dev/null) || true
        phone_orientation_value=$(phone_orientation) || true
      fi
    fi
  fi
  if command -v hyprctl >/dev/null; then
    views=$(monitors 2>/dev/null | jq -c '[.[] | select(.disabled != true) |
      {name, x, y, width: ((if (.transform % 2) == 1 then .height else .width end)/.scale | round),
       height: ((if (.transform % 2) == 1 then .width else .height end)/.scale | round)}]') || views='[]'
  fi
  jq -cn --argjson missing "$(jq -cn --args '$ARGS.positional' "${missing[@]}")" \
    --argjson usb "$usb" --argjson app "$installed" --arg native "$native" --arg rotation "$rotation" --arg orientation "$phone_orientation_value" --argjson views "$views" \
    '{missing:$missing,usb:$usb,avnc:$app,nativeSize:$native,autoRotate:($rotation=="1"),phoneOrientation:$orientation,monitors:$views}'
}

start_session() {
  local keep_awake=${7:-false}
  read_options "$@"
  for dep in wayvnc adb hyprctl ss nohup; do need "$dep"; done
  [[ -n ${WAYLAND_DISPLAY:-} && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || die 'Run inside the Hyprland session.'
  if [[ -f $STATE ]]; then
    if connected && own_process && monitor_exists && own_listener; then return 0; fi
    stop_session || die 'Could not clean up the previous session.'
  fi
  choose_phone
  adb_phone shell pm path "$APP" | grep -q '^package:' || die 'AVNC is not installed for the active Android user.'
  [[ -z $(listener) ]] || die 'TCP port 5900 is already in use; no existing server was touched.'
  local reverses
  reverses=$(adb_phone reverse --list) || die 'Cannot inspect ADB reverse mappings.'
  ! awk '$2 == "tcp:5900" {found=1} END {exit !found}' <<<"$reverses" || die 'Phone port 5900 already has an ADB reverse mapping.'
  local displays
  displays=$(monitors) || die 'Cannot query Hyprland.'
  ! jq -e --arg o "$OUTPUT" 'any(.[]; .name == $o)' <<<"$displays" >/dev/null || die 'PHONE-DISPLAY already exists outside this plugin.'
  token=$(cat /proc/sys/kernel/random/uuid)
  resolution=${width}x${height}@${hz}
  pid=0 born=none reverse=false monitor=false app=false
  save_state
  # Every subsequent failure rolls back only resources recorded as ours.
  trap 'rc=$?; trap - EXIT; if ((rc != 0)); then stop_session || true; fi; exit "$rc"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  adb_phone reverse --no-rebind tcp:5900 tcp:5900 >/dev/null
  reverse=true; save_state
  hypr output create headless "$OUTPUT" >/dev/null
  monitor=true; save_state
  apply_monitor
  save_state
  # A dedicated config prevents an existing wayvnc config changing auth/binds.
  printf 'address=127.0.0.1\nport=5900\nenable_auth=false\n' > "$RUNTIME/wayvnc.conf"
  nohup wayvnc --config "$RUNTIME/wayvnc.conf" --output "$OUTPUT" --max-fps "$hz" \
    --disable-resizing --socket "$RUNTIME/control" 127.0.0.1 5900 \
    </dev/null >"$LOG" 2>&1 9>&- &
  pid=$!
  born=$(process_birth "$pid")
  printf '%s\n' "$pid" > "$PIDFILE"
  save_state
  ready=false
  for ((i=0; i<60; i++)); do
    sleep 0.1
    own_process || { cat "$LOG" >&2; die 'wayvnc exited. See wayvnc.log.'; }
    if own_listener && [[ -S $RUNTIME/control ]]; then ready=true; break; fi
  done
  [[ $ready == true ]] || die 'wayvnc did not become ready. See wayvnc.log.'
  adb_phone shell input keyevent KEYCODE_WAKEUP >/dev/null
  if [[ $keep_awake == true ]]; then adb_phone shell svc power stayon true >/dev/null; fi
  app=true; save_state
  local intent
  intent=$(adb_phone shell am start -W -a android.intent.action.VIEW -d 'vnc://127.0.0.1:5900' "$APP" 2>&1)
  printf '%s\n' "$intent" >> "$LOG"
  [[ $intent != *Error:* && $intent != *Exception* ]] || die 'Android could not launch AVNC. See wayvnc.log.'
  own_process || die 'wayvnc failed while launching AVNC. See wayvnc.log.'
  nohup "$SCRIPT" _watch "$token" </dev/null >"$RUNTIME/watch.log" 2>&1 9>&- &
  trap - EXIT INT TERM
}

action=${1:-status}
shift || true
if [[ $action == _watch ]]; then
  expected=${1:?}
  while sleep 2; do
    # Never hold the lock during sleep or a blocking ADB probe.
    load_state
    [[ -f $STATE && $token == "$expected" ]] || exit 0
    if ! own_process || ! connected || ! monitor_exists; then
      exec 9>"$RUNTIME/lock"
      flock -w 15 9 || exit 1
      load_state
      [[ -f $STATE && $token == "$expected" ]] || exit 0
      stop_session
      exit
    fi
    if [[ $orientation == auto ]]; then
      wanted=$(phone_orientation) || continue
      dimensions=${resolution%@*}
      current=portrait
      [[ ${dimensions%%x*} -le ${dimensions#*x} ]] || current=landscape
      if [[ $wanted != "$current" ]]; then
        exec 9>"$RUNTIME/lock"
        if flock -w 8 9; then
          load_state
          if [[ -f $STATE && $token == "$expected" && $orientation == auto ]]; then
            apply_monitor && save_state || printf 'Could not follow phone orientation.\n' >&2
          fi
          flock -u 9
        fi
        exec 9>&-
      fi
    fi
  done
elif [[ $action == inspect ]]; then
  inspect_setup
elif [[ $action == awake ]]; then
  need adb
  [[ ${1:-} == on || ${1:-} == off ]] || die 'Usage: awake on|off'
  choose_phone
  if [[ $1 == on ]]; then adb_phone shell svc power stayon true; else adb_phone shell svc power stayon false; fi
elif [[ $action == status ]]; then
  # Atomic state writes let polling stay independent of a start in progress.
  load_state
  show_status
else
  exec 9>"$RUNTIME/lock"
  flock -w 30 9 || die 'Another operation is still running.'
  load_state
  case $action in
    start) start_session "$@" ;;
    stop) stop_session ;;
    configure) configure_session "$@" ;;
    toggle)
      if [[ -f $STATE ]]; then stop_session; else start_session "$@"; fi ;;
    *) die 'Usage: phone-display.sh {start [width height position scale hz orientation]|configure [same options]|stop|status|inspect|toggle}' ;;
  esac
fi
