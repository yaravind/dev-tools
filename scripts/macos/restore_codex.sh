#!/bin/zsh

set -u

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/backup_folder"
    exit 1
fi

SOURCE_DIR="${1:A}"
TARGET_DIR="$HOME/.codex"
BACKUP_ROOT="$HOME/.codex-restore-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAFETY_BACKUP="$BACKUP_ROOT/codex-before-restore-$TIMESTAMP"

format_duration() {
    local total_seconds="$1"
    printf '%02d:%02d:%02d' \
        $(( total_seconds / 3600 )) \
        $(( (total_seconds % 3600) / 60 )) \
        $(( total_seconds % 60 ))
}

rollback() {
    echo
    echo "Restore failed. Rolling back to the original Codex directory..."
    rm -rf "$TARGET_DIR"

    if [[ -d "$SAFETY_BACKUP" ]]; then
        mv "$SAFETY_BACKUP" "$TARGET_DIR" || {
            echo "Error: Automatic rollback failed."
            echo "Original data remains at: $SAFETY_BACKUP"
            exit 1
        }
        echo "Rollback completed successfully."
    else
        echo "No original Codex directory existed; partial target was removed."
    fi

    exit 1
}

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Backup source directory not found: $SOURCE_DIR"
    exit 1
fi

if [[ "$SOURCE_DIR" == "$TARGET_DIR" ]]; then
    echo "Error: Source and target directories are the same."
    exit 1
fi

if [[ ! -d "$SOURCE_DIR/sessions" && ! -d "$SOURCE_DIR/archived_sessions" ]]; then
    echo "Error: The folder does not look like a Codex backup (no sessions directories found)."
    exit 1
fi

echo "Codex full restore"
echo "  Source: $SOURCE_DIR"
echo "  Target: $TARGET_DIR"
echo
echo "This will replace the entire target directory with the backup, including"
echo "sessions, databases, indexes, configuration, credentials, plugins, and"
echo "hidden files. The existing directory will be retained as a safety backup."
echo
echo "Important: Completely quit the Codex app before continuing. Copying live"
echo "SQLite database files can result in an inconsistent restore."
echo -n "Replace $TARGET_DIR with this backup? (y/N): "
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Restore canceled."
    exit 0
fi

restore_started_at="$SECONDS"
copied_units=0
failed_units=0

echo "Restore started: $(date '+%Y-%m-%d %H:%M:%S %Z')"

if [[ -d "$TARGET_DIR" ]]; then
    mkdir -p "$BACKUP_ROOT" || {
        echo "Error: Could not create safety-backup directory: $BACKUP_ROOT"
        exit 1
    }

    backup_started_at="$SECONDS"
    echo
    echo "BEGIN   safety-backup"
    echo "MOVE    $TARGET_DIR -> $SAFETY_BACKUP"
    mv "$TARGET_DIR" "$SAFETY_BACKUP" || {
        echo "Error: Could not move the existing Codex directory to safety."
        exit 1
    }
    echo "END     safety-backup ($(format_duration $(( SECONDS - backup_started_at ))))"
fi

mkdir -p "$TARGET_DIR" || rollback

echo
echo "Restoring all top-level backup items:"

# The (DN) glob includes dotfiles and produces no error for an empty directory.
for source_item in "$SOURCE_DIR"/*(DN); do
    item_name="${source_item:t}"
    target_item="$TARGET_DIR/$item_name"
    unit_started_at="$SECONDS"

    echo
    echo "BEGIN   $item_name"
    echo "COPY    $source_item -> $target_item"

    if cp -pR "$source_item" "$target_item"; then
        (( copied_units += 1 ))
        echo "END     $item_name ($(format_duration $(( SECONDS - unit_started_at ))); copied)"
    else
        (( failed_units += 1 ))
        echo "ERROR   $item_name ($(format_duration $(( SECONDS - unit_started_at ))); copy failed)"
        rollback
    fi
done

echo
echo "Restore summary"
echo "  Top-level items copied: $copied_units"
echo "  Failed items:           $failed_units"
echo "  Total duration:         $(format_duration $(( SECONDS - restore_started_at )))"
echo "  Finished:               $(date '+%Y-%m-%d %H:%M:%S %Z')"
if [[ -d "$SAFETY_BACKUP" ]]; then
    echo "  Safety backup:          $SAFETY_BACKUP"
fi

echo
echo "Full restore completed successfully."
