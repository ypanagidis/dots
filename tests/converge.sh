#!/usr/bin/env bash
# Convergence harness for niri-ctx: deliberately perturb the window layout,
# run the dispatcher command, and assert it returns to the canonical state.
# WARNING: visibly moves windows and focus on the live session while running.
set -uo pipefail

NIRI_CTX="${NIRI_CTX:-$HOME/.local/bin/niri-ctx}"
PASS=0
FAIL=0

say() { printf '%s\n' "$*"; }

ws_id() { niri msg --json workspaces | jq -r --arg n "$1" 'first(.[] | select(.name == $n) | .id) // empty'; }

win_ws() { niri msg --json windows | jq -r --argjson id "$1" 'first(.[] | select(.id == $id) | .workspace_id) // empty'; }

win_col() { niri msg --json windows | jq -r --argjson id "$1" 'first(.[] | select(.id == $id) | .layout.pos_in_scrolling_layout[0]) // empty'; }

card_id() { # card_id <app_id>
    niri msg --json windows | jq -r --arg a "$1" '[.[] | select(.app_id == $a) | .id] | sort | (.[0] // empty)'
}

window_count() { niri msg --json windows | jq length; }

check() { # check <desc> <actual> <expected>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS+1)); say "PASS $1 ($2)"
    else
        FAIL=$((FAIL+1)); say "FAIL $1 (actual=$2 expected=$3)"
    fi
}

up_cards() { # prints "docs editor agents output logs" window ids for UP
    local docs editor agents output logs
    docs="$(head -1 ~/.cache/niri-ctx/browser-up-docs.id 2>/dev/null || true)"
    output="$(head -1 ~/.cache/niri-ctx/browser-up-output.id 2>/dev/null || true)"
    editor="$(card_id dev.yiannis.niri.up.editor)"
    agents="$(card_id dev.yiannis.niri.up.agents)"
    logs="$(card_id dev.yiannis.niri.up.logs)"
    printf '%s %s %s %s %s\n' "${docs:-?}" "${editor:-?}" "${agents:-?}" "${output:-?}" "${logs:-?}"
}

assert_up_canonical() { # <label>
    local label="$1" ws docs editor agents output logs
    ws="$(ws_id UP)"
    read -r docs editor agents output logs <<< "$(up_cards)"
    for pair in "docs:$docs:1" "editor:$editor:2" "agents:$agents:3" "output:$output:4" "logs:$logs:5"; do
        IFS=: read -r name id col <<< "$pair"
        if [[ "$id" == "?" ]]; then
            FAIL=$((FAIL+1)); say "FAIL $label/$name card missing"
            continue
        fi
        check "$label/$name on UP ws" "$(win_ws "$id")" "$ws"
        check "$label/$name at column $col" "$(win_col "$id")" "$col"
    done
}

say "=== S1: open UP twice is idempotent and canonical ==="
"$NIRI_CTX" open UP; sleep 2
c1="$(window_count)"
"$NIRI_CTX" open UP; sleep 2
c2="$(window_count)"
check "S1 window count stable" "$c2" "$c1"
assert_up_canonical S1

say "=== S2: cards scattered to other workspaces converge back ==="
read -r docs editor agents output logs <<< "$(up_cards)"
niri msg action move-window-to-workspace --window-id "$docs" --focus false Webroot >/dev/null
niri msg action move-window-to-workspace --window-id "$editor" --focus false Side >/dev/null
sleep 1
"$NIRI_CTX" open UP; sleep 2
check "S2 window count stable" "$(window_count)" "$c1"
assert_up_canonical S2

say "=== S3: cards stacked into one column converge back ==="
read -r docs editor agents output logs <<< "$(up_cards)"
# stack editor onto agents' column by consuming
niri msg action focus-window --id "$editor" >/dev/null
niri msg action consume-window-into-column >/dev/null 2>&1
sleep 1
"$NIRI_CTX" open UP; sleep 2
check "S3 window count stable" "$(window_count)" "$c1"
assert_up_canonical S3

say "=== S4: comms converges from slack exiled to UP ==="
slack="$(card_id slack)"
if [[ -n "$slack" ]]; then
    niri msg action move-window-to-workspace --window-id "$slack" --focus false UP >/dev/null
    sleep 1
    "$NIRI_CTX" comms; sleep 1
    cws="$(ws_id comms)"
    check "S4 slack back on comms" "$(win_ws "$slack")" "$cws"
    cols="$(niri msg --json windows | jq -r --argjson ws "$cws" '[.[] | select(.workspace_id == $ws and (.app_id == "slack" or .app_id == "discord" or .app_id == "org.telegram.desktop")) | .layout.pos_in_scrolling_layout[0]] | unique | length')"
    check "S4 comms one column" "$cols" "1"
else
    say "SKIP S4 (no slack window)"
fi

say "=== S5: spotify converges from exile to top-ambient ==="
spotify="$(card_id Spotify)"
if [[ -n "$spotify" ]]; then
    niri msg action move-window-to-workspace --window-id "$spotify" --focus false UP >/dev/null
    sleep 1
    "$NIRI_CTX" spotify; sleep 1
    tws="$(ws_id top-ambient)"
    check "S5 spotify on top-ambient" "$(win_ws "$spotify")" "$tws"
else
    say "SKIP S5 (no spotify window)"
fi

say "=== S6: final focus back to UP docs after open ==="
"$NIRI_CTX" open UP; sleep 2
read -r docs _ _ _ _ <<< "$(up_cards)"
focused="$(niri msg --json windows | jq -r 'first(.[] | select(.is_focused) | .id) // empty')"
check "S6 focused window is docs card" "$focused" "$docs"

say ""
say "RESULT: PASS=$PASS FAIL=$FAIL"
exit "$((FAIL > 0))"
