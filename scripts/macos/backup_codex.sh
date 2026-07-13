#!/bin/zsh

# Check if a backup directory argument was provided
if [[ -z "$1" ]]; then
    echo "Error: Please provide a backup target directory."
    echo "Usage: $0 /path/to/backup_folder"
    exit 1
fi

TARGET_DIR="$1"
SOURCE_DIR="$HOME/.codex"

# Check if the Codex source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory $SOURCE_DIR not found. Is Codex installed?"
    exit 1
fi

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

echo "Starting Codex backup to: $TARGET_DIR"

# Copy the entire .codex folder content (sessions, index, sqlite db)
cp -R "$SOURCE_DIR/"* "$TARGET_DIR/"

if [[ $? -eq 0 ]]; then
    echo "Success! Codex sessions backed up successfully."
else
    echo "Error: Something went wrong during the copy process."
fi
