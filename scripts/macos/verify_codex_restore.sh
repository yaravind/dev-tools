#!/bin/sh
# verify_codex_restore.sh
# Read-only diagnostics for restored ChatGPT/Codex data on macOS.

RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m'); YELLOW=$(printf '\033[1;33m')
BLUE=$(printf '\033[0;34m'); CYAN=$(printf '\033[0;36m'); NC=$(printf '\033[0m')

PASS=0; WARN=0; FAIL=0; ISSUES=""

log(){ printf "%b\n" "$1"; }
section(){ printf "\n${BLUE}==== %s ====${NC}\n" "$1"; }
ok(){ PASS=$((PASS+1)); log "${GREEN}[PASS]${NC} $1"; }
warn(){ WARN=$((WARN+1)); ISSUES="$ISSUES\nWARNING: $1"; log "${YELLOW}[WARN]${NC} $1"; }
bad(){ FAIL=$((FAIL+1)); ISSUES="$ISSUES\nFAILURE: $1"; log "${RED}[FAIL]${NC} $1"; }
info(){ log "${CYAN}[INFO]${NC} $1"; }

CODEX="$HOME/.codex"
CODEX_LOCATIONS="
$HOME/.codex
$HOME/Developer/.codex
$HOME/Documents/.codex
$HOME/Documents/Codex/.codex
$HOME/Library/Application Support/Codex/.codex
$HOME/Library/Application Support/ChatGPT/.codex
$HOME/Library/Application Support/OpenAI/.codex
"

APP_PROFILE_LOCATIONS="
$HOME/Library/Application Support/Codex
$HOME/Library/Application Support/ChatGPT
$HOME/Library/Application Support/OpenAI
$HOME/Library/Containers/com.openai.ChatGPT
$HOME/Library/Containers/com.openai.codex
$HOME/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService
$HOME/Library/Group Containers/2DC432GLL2.com.openai.codex.notifications
"

section "Locations to check"
while IFS= read -r location; do
  [ -n "$location" ] && printf " * %s\n" "$location"
done <<EOF
$CODEX_LOCATIONS
EOF

section "App profile/cache locations to check"
while IFS= read -r location; do
  [ -n "$location" ] && printf " * %s\n" "$location"
done <<EOF
$APP_PROFILE_LOCATIONS
EOF

section "1. Verify ~/.codex"
[ -d "$CODEX" ] && ok "Found $CODEX" || { bad "~/.codex not found"; exit 1; }

section "2. Key files"
for f in sessions archived_sessions session_index.jsonl history.jsonl logs_2.sqlite state_5.sqlite memories_1.sqlite goals_1.sqlite; do
  [ -e "$CODEX/$f" ] && ok "$f exists" || warn "$f missing"
done

section "3. Session index"
if [ -f "$CODEX/session_index.jsonl" ]; then
 c=$(wc -l < "$CODEX/session_index.jsonl")
 info "Lines: $c"
 [ "$c" -gt 0 ] && ok "Session index populated" || bad "Session index empty"
 head -3 "$CODEX/session_index.jsonl"
fi

section "4. Sessions"
if [ -d "$CODEX/sessions" ]; then
 n=$(find "$CODEX/sessions" -type f | wc -l | tr -d ' ')
 s=$(du -sh "$CODEX/sessions" | awk '{print $1}')
 info "Files: $n Size: $s"
 [ "$n" -gt 0 ] && ok "Session files found" || warn "No session files"
 find "$CODEX/sessions" -type f | head -5
fi

section "5. Archived sessions"
if [ -d "$CODEX/archived_sessions" ]; then
 n=$(find "$CODEX/archived_sessions" -type f | wc -l | tr -d ' ')
 s=$(du -sh "$CODEX/archived_sessions"|awk '{print $1}')
 info "Files: $n Size: $s"
 [ "$n" -gt 0 ] && ok "Archived sessions found" || warn "No archived sessions"
fi

section "6. Ownership"
owner=$(stat -f %Su "$CODEX")
info "Owner: $owner"
[ "$owner" = "$USER" ] && ok "Ownership correct" || bad "Owned by $owner"

section "7. Other .codex dirs"
found_codex=0
while IFS= read -r location; do
  [ -n "$location" ] || continue
  if [ -d "$location" ]; then
    info "Found $location"
    found_codex=1
  fi
done <<EOF
$CODEX_LOCATIONS
EOF

[ "$found_codex" -eq 1 ] || warn "No .codex directories found in known macOS locations"

section "8. Application Support"
find "$HOME/Library/Application Support" -maxdepth 2 2>/dev/null | grep -Ei 'chatgpt|openai|codex' || warn "No ChatGPT/OpenAI folders found"

section "9. SQLite"
if command -v sqlite3 >/dev/null 2>&1; then
 for db in logs_2.sqlite state_5.sqlite memories_1.sqlite goals_1.sqlite; do
   if [ -f "$CODEX/$db" ]; then
      sqlite3 "$CODEX/$db" "pragma integrity_check;" 2>/dev/null | grep -q ok && ok "$db integrity OK" || warn "$db integrity could not be verified"
   fi
 done
else
 warn "sqlite3 not installed"
fi

section "10. ChatGPT"
pgrep_output=$(pgrep -f ChatGPT 2>&1)
pgrep_status=$?
if [ "$pgrep_status" -eq 0 ]; then
  warn "ChatGPT is running. Quit it before restore."
elif [ "$pgrep_status" -eq 1 ]; then
  ok "ChatGPT not running"
else
  warn "Could not determine whether ChatGPT is running (pgrep exit $pgrep_status): $pgrep_output"
fi

section "11. ChatGPT UI index/cache sentinel"
if [ -f "$CODEX/session_index.jsonl" ]; then
  sentinel_line=$(grep -m 1 '"id"' "$CODEX/session_index.jsonl" 2>/dev/null)
  sentinel_id=$(printf "%s\n" "$sentinel_line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
  sentinel_title=$(printf "%s\n" "$sentinel_line" | sed -n 's/.*"thread_name":"\([^"]*\)".*/\1/p')

  if [ -n "$sentinel_id" ]; then
    info "Restored session sentinel id: $sentinel_id"
    [ -n "$sentinel_title" ] && info "Restored session sentinel title: $sentinel_title"

    found_app_profile=0
    found_sentinel=0
    while IFS= read -r location; do
      [ -n "$location" ] || continue
      if [ -d "$location" ]; then
        found_app_profile=1
        info "Scanning $location"
        if command -v rg >/dev/null 2>&1; then
          if rg -a -q -F -- "$sentinel_id" "$location" 2>/dev/null; then
            ok "ChatGPT app profile references restored session id in $location"
            found_sentinel=1
          elif [ -n "$sentinel_title" ] && rg -a -q -F -- "$sentinel_title" "$location" 2>/dev/null; then
            ok "ChatGPT app profile references restored session title in $location"
            found_sentinel=1
          fi
        else
          if grep -R -q -F -- "$sentinel_id" "$location" 2>/dev/null; then
            ok "ChatGPT app profile references restored session id in $location"
            found_sentinel=1
          elif [ -n "$sentinel_title" ] && grep -R -q -F -- "$sentinel_title" "$location" 2>/dev/null; then
            ok "ChatGPT app profile references restored session title in $location"
            found_sentinel=1
          fi
        fi
      fi
    done <<EOF
$APP_PROFILE_LOCATIONS
EOF

    [ "$found_app_profile" -eq 1 ] || warn "No ChatGPT/OpenAI app profile/cache directories found"
    [ "$found_sentinel" -eq 1 ] || warn "Restored session sentinel was not found in ChatGPT app profile/cache locations"
  else
    warn "Could not extract a restored session id from session_index.jsonl"
  fi
else
  warn "Cannot check ChatGPT UI index/cache without session_index.jsonl"
fi

section "Summary"
printf "PASS=%s WARN=%s FAIL=%s\n" "$PASS" "$WARN" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
cat <<EOF

Likely diagnosis:
 * Restored data appears present in ~/.codex.
 * If the UI index/cache sentinel warned, ChatGPT Desktop has not visibly
   linked its app profile/cache to at least one restored session.
 * In that case, do not repeat the ~/.codex restore. Back up the app profile
   locations above before testing any app-profile reset or rebuild.
EOF
else
printf "Issues:%b\n" "$ISSUES"
fi
