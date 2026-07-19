#!/bin/zsh

source "${0:A:h}/colors.sh"

INFO="${CYAN}"
ACTION="${BLUE}"
SUCCESS="${GREEN}"
WARN="${YELLOW}"
ERROR="${RED}"
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
  printf "${INFO}Usage: %s [--apply|--discover] [--dry-run] [--config <path>] [--output <path>]${RESET}\n" "$SCRIPT_NAME"
  printf "${INFO}Modes:${RESET}\n"
  printf "${INFO}  --apply           Apply associations from config using duti (default mode)${RESET}\n"
  printf "${INFO}  --discover        Show current LaunchServices UTI handlers with discovered extensions${RESET}\n"
  printf "${INFO}Options:${RESET}\n"
  printf "${INFO}  --config <path>   Override config file path for apply mode${RESET}\n"
  printf "${INFO}  --output <path>   Write discover output TSV to a file${RESET}\n"
  printf "${INFO}  --dry-run, -n     Preview apply-mode duti commands without running them${RESET}\n"
  printf "${INFO}  --help, -h        Show this help message${RESET}\n"
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
        printf "${ERROR}===> Missing value for --config${RESET}\n"
        exit 1
      fi
      CONFIG_FILE="$1"
      ;;
    --output)
      shift
      if [[ -z "$1" ]]; then
        printf "${ERROR}===> Missing value for --output${RESET}\n"
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
      printf "${ERROR}===> Unknown argument: %s${RESET}\n" "$1"
      print_usage
      exit 1
      ;;
  esac
  shift
done

discover_handlers() {
  if ! command_exists python3; then
    printf "${ERROR}===> python3 is required for discover mode.${RESET}\n"
    exit 1
  fi

  printf "${INFO}===> Discovering current LaunchServices UTI handlers and extension mappings...${RESET}\n"

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
    printf "${ERROR}===> Discover mode failed while reading LaunchServices data.${RESET}\n"
    exit 1
  fi

  if [[ -z "$discover_output" ]]; then
    printf "${WARN}===> No UTI handler records were found.${RESET}\n"
    exit 0
  fi

  printf "${SUCCESS}===> Current UTI handler table${RESET}\n"
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
      printf "${ERROR}===> Failed to write discover output to %s${RESET}\n" "$OUTPUT_FILE"
      exit 1
    }
    printf "${SUCCESS}===> Discover output written to %s${RESET}\n" "$OUTPUT_FILE"
  fi
}

apply_mappings() {
  if [[ "$DRY_RUN" -ne 1 ]] && ! command_exists duti; then
    printf "${ERROR}===> duti is not installed. Install it first with: brew install duti${RESET}\n"
    exit 1
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    printf "${ERROR}===> Config file not found: %s${RESET}\n" "$CONFIG_FILE"
    exit 1
  fi

  printf "${INFO}===> Reading default app mappings from %s${RESET}\n" "$CONFIG_FILE"
  [[ "$DRY_RUN" -eq 1 ]] && printf "${WARN}===> Dry run enabled. No changes will be applied.${RESET}\n"

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
      printf "${ERROR}===> Invalid entry at line %d: %s${RESET}\n" "$line_number" "$line"
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
        printf "${WARN}===> Scheme already mapped: %s -> %s${RESET}\n" "$scheme" "$bundle_id"
        ((skip_count++))
        continue
      fi
      local -a cmd=(duti -s "$bundle_id" "$scheme")
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "${ACTION}[dry-run] %q %q %q %q${RESET}\n" "${cmd[1]}" "${cmd[2]}" "${cmd[3]}" "${cmd[4]}"
        ((apply_count++))
      elif "${cmd[@]}"; then
        printf "${SUCCESS}===> Applied scheme mapping: %s -> %s${RESET}\n" "$scheme" "$bundle_id"
        ((apply_count++))
      else
        if command_exists python3; then
          current_handler="$(get_current_scheme_handler "$scheme")"
          if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
            printf "${WARN}===> Scheme mapping already in effect after duti error: %s -> %s${RESET}\n" "$scheme" "$bundle_id"
            ((skip_count++))
            continue
          fi
        fi
        printf "${ERROR}===> Failed scheme mapping at line %d: %s${RESET}\n" "$line_number" "$line"
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
          printf "${ERROR}===> Invalid role '%s' at line %d (allowed: all|viewer|editor|shell).${RESET}\n" "$role" "$line_number"
          ((invalid_count++))
          continue
          ;;
      esac

      local current_handler=""
      if [[ "$role" == "all" ]] && command_exists python3; then
        current_handler="$(get_current_uti_handler "$uti")"
      fi
      if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
        printf "${WARN}===> UTI already mapped: %s (%s) -> %s${RESET}\n" "$uti" "$role" "$bundle_id"
        ((skip_count++))
        continue
      fi

      local -a cmd=(duti -s "$bundle_id" "$uti" "$role")
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "${ACTION}[dry-run] %q %q %q %q %q${RESET}\n" "${cmd[1]}" "${cmd[2]}" "${cmd[3]}" "${cmd[4]}" "${cmd[5]}"
        ((apply_count++))
      elif "${cmd[@]}"; then
        printf "${SUCCESS}===> Applied UTI mapping: %s (%s) -> %s${RESET}\n" "$uti" "$role" "$bundle_id"
        ((apply_count++))
      else
        if [[ "$role" == "all" ]] && command_exists python3; then
          current_handler="$(get_current_uti_handler "$uti")"
          if [[ "${current_handler:l}" == "${bundle_id:l}" ]]; then
            printf "${WARN}===> UTI mapping already in effect after duti error: %s (%s) -> %s${RESET}\n" "$uti" "$role" "$bundle_id"
            ((skip_count++))
            continue
          fi
        fi
        printf "${ERROR}===> Failed UTI mapping at line %d: %s${RESET}\n" "$line_number" "$line"
        ((fail_count++))
      fi
      continue
    fi

    printf "${ERROR}===> Invalid entry at line %d: %s${RESET}\n" "$line_number" "$line"
    ((invalid_count++))
  done < "$CONFIG_FILE"

  printf "${SUCCESS}===> Applied mappings: %d${RESET}\n" "$apply_count"
  printf "${WARN}===> Skipped lines: %d${RESET}\n" "$skip_count"
  printf "${WARN}===> Invalid lines: %d${RESET}\n" "$invalid_count"
  printf "${ERROR}===> Failed mappings: %d${RESET}\n" "$fail_count"

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
