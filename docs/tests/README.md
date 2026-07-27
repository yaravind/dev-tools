---
title: Dry-Run Tests
permalink: /docs/tests/
---

# Dry-Run Tests

This repo includes lightweight dry-run tests for both macOS and Windows scripts.

## macOS

Run the macOS script checks from a zsh shell:

```zsh
./scripts/macos/run_tests.sh
```

The macOS dry-run checks:
- Validate shell syntax for each macOS script (`zsh -n`).
- Confirm required config files exist.

## Windows

Run the Windows script checks from PowerShell:

```powershell
.\scripts\windows\run_tests.ps1
```

The Windows dry-run checks:
- Parse each PowerShell script for syntax errors.
- Parse the repo-managed PowerShell profile config.
- Run safe `-DryRun` checks for launchpad, profile, repo clone, Codex backup/restore, Git, jenv, VS Code, IntelliJ, PyCharm, minimal setup, rollback, and Taskbar setup when running on Windows.
- Exit nonzero on missing scripts/configs, syntax failures, or dry-run failures.
