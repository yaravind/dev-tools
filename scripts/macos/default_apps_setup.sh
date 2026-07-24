#!/bin/zsh

source "${0:A:h}/branding.sh"
ebk_print_banner "${0:A:t}"
SCRIPT_NAME="${0:A:t}"
SCRIPT_DIR="${0:A:h}"
CONFIG_FILE="${SCRIPT_DIR}/../../config/default_apps_macos.txt"

DRY_RUN=0
MODE="apply"
OUTPUT_FILE=""

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_current_scheme_handler() {
  local scheme="$1"
  python3 - "$scheme" <<'PY'
import plistlib
import subprocess
import sys

scheme = sys.argv[1]
proc = subprocess.run(
    ["defaults", "export", "com.apple.LaunchServices/com.apple.launchservices.secure", "-"],
    check=False,
    capture_output=True,
)
if proc.returncode != 0 or not proc.stdout:
    raise SystemExit(0)

try:
    data = plistlib.loads(proc.stdout)
except Exception:
    raise SystemExit(0)

for handler in data.get("LSHandlers", []):
    if handler.get("LSHandlerURLScheme") == scheme:
        bundle_id = handler.get("LSHandlerRoleAll", "")
        if bundle_id:
            print(bundle_id)
            break
PY
}

get_current_uti_handler() {
  local uti="$1"
  python3 - "$uti" <<'PY'
import plistlib
import subprocess
import sys

uti = sys.argv[1]
proc = subprocess.run(
    ["defaults", "export", "com.apple.LaunchServices/com.apple.launchservices.secure", "-"],
    check=False,
    capture_output=True,
)
if proc.returncode != 0 or not proc.stdout:
    raise SystemExit(0)

try:
    data = plistlib.loads(proc.stdout)
except Exception:
    raise SystemExit(0)

for handler in data.get("LSHandlers", []):
    if handler.get("LSHandlerContentType") == uti:
        bundle_id = handler.get("LSHandlerRoleAll", "")
        if bundle_id:
            print(bundle_id)
            break
PY
}

print_usage() {
  printf 'Usage: %s [--apply|--discover] [--dry-run] [--config <path>] [--output <path>]\n' "$SCRIPT_NAME"
  printf 'Modes:\n'
  printf '  --apply           Apply associations from config using duti (default mode)\n'
  printf '  --discover        Show current LaunchServices UTI handlers with discovered extensions\n'
  printf 'Options:\n'
  printf '  --config <path>   Override config file path for apply mode\n'
  printf '  --output <path>   Write discover output TSV to a file\n'
  printf '  --dry-run, -n     Preview apply-mode duti commands without running them\n'
  printf '  --help, -h        Show this help message\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      MODE="apply"
      ;;
    --discover)
      MODE="discover"
      ;;
    --config)
      shift
      if [[ -z "$1" ]]; then
        log_error "Missing value for --config"
        exit 1
      fi
      CONFIG_FILE="$1"
      ;;
    --output)
      shift
      if [[ -z "$1" ]]; then
        log_error "Missing value for --output"
        exit 1
      fi
      OUTPUT_FILE="$1"
      ;;
    --dry-run|-n)
      DRY_RUN=1
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      print_usage
      exit 1
      ;;
  esac
  shift
done

discover_handlers() {
  if ! command_exists python3; then
    log_error "python3 is required for discover mode."
    exit 1
  fi

  log_phase "Discovering current LaunchServices UTI handlers and extension mappings..."

  local discover_output
  discover_output="$(python3 - <<'PY'
import os
import plistlib
import subprocess
import sys

def normalize_extensions(value):
    if value is None:
        return []
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, (list, tuple)):
        values = [str(item) for item in value if item is not None]
    else:
        return []
    cleaned = []
    for ext in values:
        ext = ext.strip().lstrip(".")
        if ext and ext != "*":
            cleaned.append(ext)
    return cleaned

def parse_info_plist(info_path, uti_map):
    try:
        with open(info_path, "rb") as f:
            data = plistlib.load(f)
    except Exception:
        return

    for key in ("UTExportedTypeDeclarations", "UTImportedTypeDeclarations"):
        for decl in data.get(key, []) or []:
            uti = decl.get("UTTypeIdentifier")
            if not uti:
                continue
            tags = decl.get("UTTypeTagSpecification", {}) or {}
            for ext in normalize_extensions(tags.get("public.filename-extension")):
                uti_map.setdefault(uti, set()).add(ext)

    for doc_type in data.get("CFBundleDocumentTypes", []) or []:
        utis = doc_type.get("LSItemContentTypes", []) or []
        exts = normalize_extensions(doc_type.get("CFBundleTypeExtensions"))
        if not utis or not exts:
            continue
        for uti in utis:
            if uti:
                for ext in exts:
                    uti_map.setdefault(uti, set()).add(ext)

def collect_uti_extensions():
    roots = ["/Applications", "/System/Applications", os.path.expanduser("~/Applications")]
    uti_map = {}
    seen = set()
    for base in roots:
        if not os.path.isdir(base):
            continue
        for root, dirs, _files in os.walk(base):
            app_dirs = [d for d in dirs if d.endswith(".app")]
            for app_dir in app_dirs:
                app_path = os.path.join(root, app_dir)
                if app_path in seen:
                    continue
                seen.add(app_path)
                parse_info_plist(os.path.join(app_path, "Contents", "Info.plist"), uti_map)
            dirs[:] = [d for d in dirs if not d.endswith(".app")]
    return uti_map

proc = subprocess.run(
    ["defaults", "export", "com.apple.LaunchServices/com.apple.launchservices.secure", "-"],
    check=False,
    capture_output=True,
)
if proc.returncode != 0:
    raise SystemExit(f"ERROR: LaunchServices export failed: {proc.stderr.decode('utf-8', errors='ignore').strip()}")

stdin_bytes = proc.stdout
if not stdin_bytes:
    raise SystemExit("ERROR: LaunchServices export returned no data.")

try:
    launch_services = plistlib.loads(stdin_bytes)
except Exception as ex:
    raise SystemExit(f"ERROR: Unable to parse LaunchServices plist: {ex}")

handlers = launch_services.get("LSHandlers", [])
uti_map = collect_uti_extensions()

rows = []
for handler in handlers:
    uti = handler.get("LSHandlerContentType")
    if not uti:
        continue
    roles = []
    for role_key in (
        "LSHandlerRoleAll",
        "LSHandlerRoleViewer",
        "LSHandlerRoleEditor",
        "LSHandlerRoleShell",
    ):
        value = handler.get(role_key)
        if value:
            roles.append(f"{role_key.replace('LSHandlerRole', '').lower()}={value}")
    extensions = ",".join(sorted(uti_map.get(uti, set())))
    rows.append((uti, extensions, ";".join(roles)))

for uti, extensions, role_values in sorted(set(rows), key=lambda item: item[0]):
    print(f"{uti}\t{extensions}\t{role_values}")
PY
)"
  local discover_status=$?
  if [[ "$discover_status" -ne 0 ]]; then
    log_error "Discover mode failed while reading LaunchServices data."
    exit 1
  fi

  if [[ -z "$discover_output" ]]; then
    log_warn "No UTI handler records were found."
    exit 0
  fi

  log_ok "Current UTI handler table"
  DISCOVER_OUTPUT="$discover_output" python3 - <<'PY'
import os
import sys

headers = ["UTI", "Extensions", "Handlers"]
rows = []

for line in os.environ.get("DISCOVER_OUTPUT", "").splitlines():
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("\t")
    while len(parts) < 3:
        parts.append("")
    rows.append(parts[:3])

widths = [len(h) for h in headers]
for row in rows:
    for idx, value in enumerate(row):
        widths[idx] = max(widths[idx], len(value))

def separator(char):
    return "+" + "+".join(char * (width + 2) for width in widths) + "+"

print(separator("-"))
print("| " + " | ".join(headers[i].ljust(widths[i]) for i in range(3)) + " |")
print(separator("="))
for row in rows:
    print("| " + " | ".join(row[i].ljust(widths[i]) for i in range(3)) + " |")
print(separator("-"))
PY

  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$discover_output" > "$OUTPUT_FILE" || {
      log_error "Failed to write discover output to ${OUTPUT_FILE}"
      exit 1
    }
    log_ok "Discover output written to ${OUTPUT_FILE}"
  fi
}

apply_mappings() {
  if [[ "$DRY_RUN" -ne 1 ]] && ! command_exists duti; then
    log_error "duti is not installed. Install it first with: brew install duti"
    exit 1
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    exit 1
  fi

  log_info "Reading default app mappings from ${CONFIG_FILE}"
  [[ "$DRY_RUN" -eq 1 ]] && log_warn "Dry run enabled. No changes will be applied."

  local line line_number=0
  local apply_count=0 skip_count=0 fail_count=0 invalid_count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number++))

    local trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

    if [[ -z "$trimmed" || "$trimmed" == \#* || "$trimmed" == //* ]]; then
      ((skip_count++))
      continue
    fi

    local -a fields
    fields=(${(z)trimmed})

    local bundle_id="${fields[1]}"
    if [[ -z "$bundle_id" ]]; then
      log_error "Invalid entry at line ${line_number}: ${line}"
      ((invalid_count++))
      continue
    fi

    if [[ ${#fields[@]} -eq 2 ]]; then
      local scheme="${fields[2]}"
      local current_handler=""
      if command_exists python3; then
        current_handler="$(get_current_scheme_handler "$scheme")"
      fi
      if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
        log_warn "Scheme already mapped: ${scheme} -> ${bundle_id}"
        ((skip_count++))
        continue
      fi
      local -a cmd=(duti -s "$bundle_id" "$scheme")
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_debug "[dry-run] ${cmd[*]}"
        ((apply_count++))
      elif "${cmd[@]}"; then
        log_ok "Applied scheme mapping: ${scheme} -> ${bundle_id}"
        ((apply_count++))
      else
        if command_exists python3; then
          current_handler="$(get_current_scheme_handler "$scheme")"
          if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
            log_warn "Scheme mapping already in effect after duti error: ${scheme} -> ${bundle_id}"
            ((skip_count++))
            continue
          fi
        fi
        log_error "Failed scheme mapping at line ${line_number}: ${line}"
        ((fail_count++))
      fi
      continue
    fi

    if [[ ${#fields[@]} -eq 3 ]]; then
      local uti="${fields[2]}"
      local role="${fields[3]}"
      case "$role" in
        all|viewer|editor|shell)
          ;;
        *)
          log_error "Invalid role '${role}' at line ${line_number} (allowed: all|viewer|editor|shell)."
          ((invalid_count++))
          continue
          ;;
      esac

      local current_handler=""
      if [[ "$role" == "all" ]] && command_exists python3; then
        current_handler="$(get_current_uti_handler "$uti")"
      fi
      if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
        log_warn "UTI already mapped: ${uti} (${role}) -> ${bundle_id}"
        ((skip_count++))
        continue
      fi

      local -a cmd=(duti -s "$bundle_id" "$uti" "$role")
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_debug "[dry-run] ${cmd[*]}"
        ((apply_count++))
      elif "${cmd[@]}"; then
        log_ok "Applied UTI mapping: ${uti} (${role}) -> ${bundle_id}"
        ((apply_count++))
      else
        if [[ "$role" == "all" ]] && command_exists python3; then
          current_handler="$(get_current_uti_handler "$uti")"
          if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
            log_warn "UTI mapping already in effect after duti error: ${uti} (${role}) -> ${bundle_id}"
            ((skip_count++))
            continue
          fi
        fi
        log_error "Failed UTI mapping at line ${line_number}: ${line}"
        ((fail_count++))
      fi
      continue
    fi

    log_error "Invalid entry at line ${line_number}: ${line}"
    ((invalid_count++))
  done < "$CONFIG_FILE"

  log_ok "Applied mappings: ${apply_count}"
  log_warn "Skipped lines: ${skip_count}"
  log_warn "Invalid lines: ${invalid_count}"
  if (( fail_count > 0 )); then
    log_error "Failed mappings: ${fail_count}"
  else
    log_ok "Failed mappings: ${fail_count}"
  fi

  if (( fail_count > 0 || invalid_count > 0 )); then
    exit 1
  fi
}

if [[ "$MODE" == "discover" ]]; then
  discover_handlers
else
  apply_mappings
fi

printf "\nAll set.\n"
