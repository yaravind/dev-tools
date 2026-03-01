# Contributing to Developer Tools

Thank you for your interest in contributing to **Developer Tools**! We welcome contributions from the community to help make this project better.

## How to Contribute

### Reporting Bugs

If you find a bug, please create a new issue in the [Issues](https://github.com/yaravind/dev-tools/issues) section. Be sure to include:
- A clear title and description.
- Steps to reproduce the issue.
- Your operating system and version.
- Any relevant logs or screenshots.

### Suggesting Enhancements

Have an idea for a new feature or improvement? Open an issue to discuss it before starting work. This ensures your efforts align with the project's goals and prevents duplication.

### Submitting a Pull Request (PR)

1. **Fork the Repository**: Click the "Fork" button at the top right of the repository page.
2. **Clone Your Fork**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/dev-tools.git
   cd dev-tools
   ```
3. **Create a Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **Make Changes**: Implement your changes or fixes.
5. **Run Tests**: Ensure your changes don't break existing functionality.

   ## Tests

   Run the OS-specific dry-run checks:

   ```zsh
   ./scripts/macos/run_tests.sh
   ```

   ```powershell
   .\scripts\windows\run_tests.ps1
   ```

   See `docs/tests/README.md` for details.

6. **Commit Changes**:
   ```bash
   git commit -m "Description of your changes"
   ```
7. **Push to Your Fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
8. **Open a Pull Request**: Go to the original repository and click "New Pull Request". Select your branch and provide a detailed description of your changes.

## Code Style

- Follow the existing coding style and conventions.
- Ensure scripts are executable and have appropriate permissions.
- Update documentation if necessary.

Thank you for your contribution!
