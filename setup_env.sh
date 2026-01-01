#!/bin/zsh

# This script is designed to automate the installation and configuration of some
# commonly used developer tools on macOS M1/M2 chip

# Import colors codes for text
source colors.sh

# List of apps to be installed
apps=(
  "python@3.13"
  "rust"
  "pipx"        # Needed to install poetry
  "uv"          # Extremely fast Python package installer and resolver, written in Rust
  "htop"        # Improved top (interactive process viewer)
  "tree"        # Display directories as trees (with optional color/HTML output)
  "jq"          # Lightweight and flexible command-line JSON processor
  "gh"          # GitHub command-line tool
  "azure-cli"
  "tldr"        # Simplified and community-driven man pages
  "eza"         # Eza is a modern replacement for the ls command
  "trash"       # Moves files to the trash, which is safer because it is reversible
  "jenv"        # Manage multiple versions of Java
  "bat"         # Clone of cat(1) with syntax highlighting and Git integration
  "thefuck"     # Programmatically correct last mistyped console command
  "node"        # cross-platform JavaScript runtime environment that lets developers create servers, web apps, command line tools and scripts
  "pandoc"      # Swiss-army knife of markup format conversion.
  "llm"         # A CLI utility and Python library for interacting with Large Language Models. https://llm.datasette.io/en/stable/index.html
  "lnav"        # A robust log colorizer to tail logs:   tail -f your_log_file.log | ccze -A
  #"hugo"        # Configurable fastest static site generator
  "graphviz"    # Convert dot files to images
  "dockutil"     # Command line tool for manipulating macOS Dock items
)

# List of casks (GUI apps) to be installed
casks=(
  "microsoft-openjdk@11"      # For Fabric Runtime 1.3
  "microsoft-openjdk@17"      # For Apache Jena 5.4.x
  "dotnet-sdk"                # Needed to run different VS Code plugins related to Fabric and Synapse
  "git-credential-manager"    # Cross-platform Git credential storage for multiple hosting providers
  "appcleaner"                # Allows you to thoroughly uninstall unwanted apps.
  "intellij-idea"             # Use intellij-idea for Ultimate Edition
  "pycharm"                   # Use pycharm for Ultimate Edition
  "visual-studio-code"        # VS Code
  #"font-3270-nerd-font"       # Modern fonts to show icons etc
  #"font-anonymice-nerd-font"
  #"font-code-new-roman-nerd-font"
  #"font-fira-code-nerd-font"
  #"font-jetbrains-mono-nerd-font"
  "microsoft-azure-storage-explorer"
  "drawio"                    # Online diagram software
  "Zed"                       # Multiplayer code editor
  #"protege"                   # OWL for ontologies and knowledge graph
  "ollama"                    # Manage Local LLMs
  "logi-options+"             # Software for Logitech WebCam
  #"bunch"                     # Automate tasks on your Mac
  #"alt-tab"                   # Alt-Tab is a window switcher for Mac
  #"hovrly"                    # Display and convert timezones time in different cities
  #"aldente"                   # Menu bar tool to limit maximum charging percentage
  #"maccy"                     # Clipboard manager
  #"bruno"                     # open-source desktop alternative to Postman. saved to filesystem. use markup
  "powershell"                # PowerShell for Mac
  "fsnotes"                   # Note taking app with markdown support
  "go2shell"                  # Opens a terminal window to the current directory in Finder
)

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install Homebrew if not installed
install_homebrew() {
  if ! command_exists brew; then
    echo -e "${RED}===> Homebrew not found. Installing...${RESET}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

# Function to install app using brew
install_app() {
  echo -e "${RED}===> Installing formula: $1...${RESET}"
  brew install "$1"
}

# Function to install cask using brew
install_cask() {
  echo -e "${RED}===> Installing cask: $1...${RESET}"
  brew install --cask "$1"
}

# Function to set environment variables
set_env_vars() {
  echo -e "${UMAGENTA}===> Start setting ENV VARs${RESET}"
  if [[ -z "${JAVA_HOME}" ]]; then
    echo -e "${CYAN}===> Adding JAVA_HOME env variable to .zshrc...${RESET}"
    echo "# brew_install_apps.sh - Appending JAVA_HOME env var" >>~/.zshrc
    echo "export JAVA_HOME=$(/usr/libexec/java_home)" >>~/.zshrc
  else
    echo -e "${CYAN}===> JAVA_HOME is already set to: ${JAVA_HOME}${RESET}"
  fi

  echo -e "${BLUE}===> Source .zshrc...${RESET}"
  echo 'export PATH="$HOME/.jenv/bin:$PATH"' >>~/.zshrc
  echo 'eval "$(jenv init -)"' >>~/.zshrc

  source "$HOME/.zshrc"
}

# Function to verify installations
verify_installations() {
  echo -e "${UMAGENTA}===> Start verification${RESET}"
  echo -e "${BLUE}===> All installed packages (formulae and casks)...${RESET}"
  brew list --versions

  echo -e "${BLUE}===> Verify apps...${RESET}"
#  for app in "${apps[@]}"; do
#    echo -e "${CYAN}===> Verifying $app...${RESET}"
#    which -a "$app"
#    "$app" --version
#  done

  echo -e "${CYAN}===> Verify Java...${RESET}"
  java -version

  echo -e "${CYAN}===> Verify Maven...${RESET}"
  mvn -version

  echo -e "${CYAN}===> Verify Python...${RESET}"
  which -a python3
  python3 -V

  echo -e "${BBLACK}*** Add alias rm='trash' to .zshrc ***${RESET}"
  echo -e "${BBLACK}*** Add alias cat='bat' to .zshrc ***${RESET}"
}

# Main script execution
echo -e "${YELLOW}===> Creating ~/.hushlogin to disable login banner.${RESET}"
touch ~/.hushlogin

echo -e "${UMAGENTA}===> Start installation.${RESET}"

install_homebrew

echo -e "${BLUE}===> Updating Homebrew...${RESET}"
brew update

echo -e "${BLUE}===> Allowing brew to lookup versions...${RESET}"
brew tap homebrew/cask-versions

echo -e "${BLUE}===> Allowing brew to find nerd fonts...${RESET}"
brew tap homebrew/cask-fonts

echo -e "${RED}===> Installing maven without java dependency...${RESET}"
brew install --ignore-dependencies maven

echo -e "${BLUE}===> Installing formulae and casks...${RESET}"
for app in "${apps[@]}"; do
  install_app "$app"
done

for cask in "${casks[@]}"; do
  install_cask "$cask"
done

echo -e "${BLUE}===> Cleaning up Homebrew...${RESET}"
brew cleanup

# set_env_vars comment this as jenv manages versions
verify_installations

printf "\n\n👌 Awesome, all set.\n"