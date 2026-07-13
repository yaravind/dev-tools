#!/bin/zsh

# Check if a backup directory argument was provided
if [[ -z "$1" ]]; then
    echo "Error: Please provide the source backup directory."
    echo "Usage: $0 /path/to/backup_folder"
    exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$HOME/.codex"

# Check if the provided backup directory actually exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Backup source directory $SOURCE_DIR not found."
    exit 1
fi

# Confirm it contains actual Codex files before proceeding
if [[ ! -d "$SOURCE_DIR/sessions" && ! -f "$SOURCE_DIR/state_5.sqlite" ]]; then
    echo "Error: The folder does not look like a valid Codex backup."
    exit 1
fi

# Safe precaution: Warn if a Codex directory already exists on the new machine
if [[ -d "$TARGET_DIR" ]]; then
    echo "Warning: $TARGET_DIR already exists."
    echo -n "Do you want to overwrite existing sessions? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Restore canceled."
        exit 0
    fi
fi

# Create the target directory hidden in the home folder
mkdir -p "$TARGET_DIR"

echo "Restoring Codex data to: $TARGET_DIR"

# Copy the contents back into place
cp -R "$SOURCE_DIR/"* "$TARGET_DIR/"

if [[ $? -eq 0 ]]; then
    echo "Success! Codex sessions restored. Run 'codex resume' to view them."
else
    echo "Error: Something went wrong during the restore process."
fi
