#!/bin/zsh

# This script is designed to automate the installation and configuration of some
# commonly used developer tools on macOS M1/M2 chip

# Remove the login banner that shows up every time the terminal is opened
echo -e "\033[1;35m===> Disabling login banner using .hushlogin ...\033[0m"
touch ~/.hushlogin

# Install formulae and casks
echo -e "\033[1;35m===> Start installation...\033[0m"

# List of apps to be installed
apps=(
  "python@3.10"
  "htop" # Improved top (interactive process viewer)
  "tree" # Display directories as trees (with optional color/HTML output)
  "jq"   # Lightweight and flexible command-line JSON processor
  "gh"   # GitHub command-line tool
  "azure-cli"
  "tldr"    # Simplified and community-driven man pages
  "fig"     # Adds IDE-style autocomplete to the terminal
  "exa"     # Exa is a modern replacement for the ls command
  "trash"   # Moves files to the trash, which is safer because it is reversible
  "jenv"    # Manage multiple versions of Java
  "bat"     # Clone of cat(1) with syntax highlighting and Git integration
  "thefuck" # Programmatically correct last mistyped console command
)

# List of casks to be installed
casks=(
  "zulu8" # JDK 8 for Mac ARM M1/M2 Chip
  "miniconda"
  "intellij-idea-ce"    # Use intellij-idea for Ultimate Edition
  "pycharm-ce"          # Use pycharm for Ultimate Edition
  "font-3270-nerd-font" # Modern fonts to show icons etc
  "font-agave-nerd-font"
  "font-anonymice-nerd-font"
  "font-code-new-roman-nerd-font"
  "font-fira-code-nerd-font"
  "font-jetbrains-mono-nerd-font"
)

# Function to install app using brew
install_app() {
  echo -e "\033[1;36m===> Installing formula: $1...\033[0m"
  brew install "$1"
}

# Function to install cask using brew
install_cask() {
  echo -e "\033[1;36m===> Installing cask: $1...\033[0m"
  brew install --cask "$1"
}

# Check if Homebrew is installed, otherwise install it
if ! command -v brew &>/dev/null; then
  echo -e "\033[1;33m===> Homebrew not found. Installing...\033[0m"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Update Homebrew
echo -e "\033[1;32m===> Updating Homebrew...\033[0m"
brew update

# Allow brew to lookup versions
echo -e "\033[1;32m===> Allowing brew to lookup versions...\033[0m"
brew tap homebrew/cask-versions

# Allow brew to find nerd fonts
echo -e "\033[1;32m===> Allowing brew to find nerd fonts...\033[0m"
brew tap homebrew/cask-fonts

# Install Oh My Posh
echo -e "\033[1;32m===> Installing fonts for Oh My Posh...\033[0m"

echo -e "\033[1;32m===> Installing formulae...\033[0m"

# Install maven separately to ignore installing Java 20 as a dependency
echo -e "\033[1;36m===> Installing maven without java dependency...\033[0m"
brew install --ignore-dependencies maven

# Install apps
for app in "${apps[@]}"; do
  install_app "$app"
done

# Install casks
echo -e "\033[1;32m===> Installing casks...\033[0m"
for cask in "${casks[@]}"; do
  install_cask "$cask"
done

# Cleanup Homebrew
echo -e "\033[1;32m===> Cleaning up Homebrew...\033[0m"
brew cleanup

echo -e "\033[1;35m===> Completed installation.\033[0m"

# -------------------------------------------------------------------
# Set environment variables
# -------------------------------------------------------------------
echo -e "\033[1;35m===> Start setting ENV VARs...\033[0m"
#export JAVA_HOME=$(/usr/libexec/java_home)
if [[ -z "${JAVA_HOME}" ]]; then
  echo -e "\033[1;36m===> Adding JAVA_HOME env variable to .zshrc...\033[0m"
  echo "# brew_install_apps.sh - Appending JAVA_HOME env var" >>~/.zshrc
  echo "export JAVA_HOME=$(/usr/libexec/java_home)" >>~/.zshrc
else
  echo -e "\033[1;36m===> JAVA_HOME is already set to: ${JAVA_HOME}\033[0m"
fi

echo -e "\033[1;36m===> Source .zshrc...\033[0m"
source ~/.zshrc
echo -e "\033[1;35m===> Completed setting ENV VARs.\033[0m"

# -------------------------------------------------------------------
# Verify installation
# -------------------------------------------------------------------
echo -e "\033[1;35m===> Start verification...\033[0m"

echo -e "\033[1;32m===> All installed packages (formulae and casks)...\033[0m"
brew list --versions

echo -e "\033[1;32m===> Verify apps...\033[0m"

echo -e "\033[1;36m===> Verify JAVA_HOME...\033[0m"
echo "$JAVA_HOME"

echo -e "\033[1;36m===> Verify Java...\033[0m"
java -version

echo -e "\033[1;36m===> Verify Maven...\033[0m"
mvn -version

echo -e "\033[1;36m===> Verify Conda...\033[0m"
conda --version

echo -e "\033[1;36m===> Verify Python...\033[0m"
which -a python3
python3 -V

echo -e "\033[1;36m===> Add alias rm=trash to .zshrc\033[0m"
echo -e "\033[1;36m===> Add alias cat=bat to .zshrc\033[0m"

echo -e "\033[1;35m===> Completed verification.\033[0m"
