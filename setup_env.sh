#!/bin/zsh

# This script is designed to automate the installation and configuration of some
# commonly used developer tools on macOS M1/M2 chip

# Import colors codes for text
source colors.sh

# List of apps to be installed
apps=(
  "python@3.11"
  "rust"
  "pipx" # Needed to install poetry
  "htop" # Improved top (interactive process viewer)
  "tree" # Display directories as trees (with optional color/HTML output)
  "jq"   # Lightweight and flexible command-line JSON processor
  "gh"   # GitHub command-line tool
  "azure-cli"
  "tldr"       # Simplified and community-driven man pages
  "fig"        # Adds IDE-style autocomplete to the terminal
  "exa"        # Exa is a modern replacement for the ls command
  "trash"      # Moves files to the trash, which is safer because it is reversible
  "jenv"       # Manage multiple versions of Java
  "bat"        # Clone of cat(1) with syntax highlighting and Git integration
  "thefuck"    # Programmatically correct last mistyped console command
  #"micromamba" # micromamba is faster alternative to conda, gives clearer error reporting
  "node"       # cross-platform JavaScript runtime environment that lets developers create servers, web apps, command line tools and scripts
  "pandoc" # Swiss-army knife of markup format conversion.
)

# List of casks (GUI apps) to be installed
casks=(
  "zulu8" # JDK 8 for Mac ARM M1/M2 Chip
  "git-credential-manager"
  "miniconda"
#  "intellij-idea-ce"    # Use intellij-idea-ce for Community Edition
  "intellij-idea"       # Use intellij-idea for Ultimate Edition
#  "pycharm-ce"          # Use pycharm-ce for Community Edition
  "pycharm"             # Use pycharm for Ultimate Edition
  "visual-studio-code"  # VS Code
  "font-3270-nerd-font" # Modern fonts to show icons etc
 # "font-agave-nerd-font"
  "font-anonymice-nerd-font"
  "font-code-new-roman-nerd-font"
  "font-fira-code-nerd-font"
  "font-jetbrains-mono-nerd-font"
  "azure-data-studio" # Data management tool that enables working with Azure DB Services
 # "azure-data-studio-insiders"
  "microsoft-azure-storage-explorer"
  "drawio" # Online diagram software
  "Zed" # Multiplayer code editor
  "protege" #OWL for ontologies and knowledge graph
  "google-cloud-sdk" #for NL API and Vertex AI
)

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

# -------------------------------------------------------------------
# Remove the login banner that shows up every time the terminal is opened
# -------------------------------------------------------------------
echo -e "${YELLOW}===> Creating ~/.hushlogin to disable login banner.${RESET}"
touch ~/.hushlogin

# -------------------------------------------------------------------
# Install formulae and casks
# -------------------------------------------------------------------
echo -e "\n"
echo -e "${UMAGENTA}===> Start installation.${RESET}"

# Check if Homebrew is installed, otherwise install it
if ! command -v brew &>/dev/null; then
  echo -e "${RED}===> Homebrew not found. Installing...${RESET}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Update Homebrew
echo -e "${BLUE}===> Updating Homebrew...${RESET}"
brew update

# Allow brew to lookup versions
echo -e "${BLUE}===> Allowing brew to lookup versions...${RESET}"
brew tap homebrew/cask-versions

# Allow brew to find nerd fonts
echo -e "${BLUE}===> Allowing brew to find nerd fonts...${RESET}"
brew tap homebrew/cask-fonts

echo -e "${BLUE}===> Installing formulae...${RESET}"

# Install maven separately to ignore installing Java 20 as a dependency
echo -e "${RED}===> Installing maven without java dependency...${RESET}"
brew install --ignore-dependencies maven

# Install apps
for app in "${apps[@]}"; do
  install_app "$app"
done

# Install casks
echo -e "${BLUE}===> Installing casks...${RESET}"
for cask in "${casks[@]}"; do
  install_cask "$cask"
done

# -------------------------------------------------------------------
# Install mamba
# -------------------------------------------------------------------
#echo -e "${RED}===> Install mamba - faster alternative to conda ...${RESET}"
## Check if mamba is installed
#if command -v mamba >/dev/null 2>&1; then
#  echo -e "${BBLACK}*** Mamba is already installed. Use it as an alternative to conda. ***${RESET}"
#else
#  echo -e "${RED}Mamba not found. Installing Mamba via Conda...${RESET}"
#
#  # Check if conda is installed, if not, exit the script
#  if ! command -v conda >/dev/null 2>&1; then
#    echo -e "${BRED}Error: Conda is not installed. Please install Conda and try again.${RESET}"
#    exit 1
#  fi
#
#  # Install mamba using Conda from the conda-forge channel
#  conda install --quiet -c conda-forge mamba
#
#  # Verify successful installation
#  if ! command -v mamba >/dev/null 2>&1; then
#    echo -e "${BRED}Error: Mamba installation failed. Using Conda for environment management${RESET}"
#  else
#    echo "${BBLACK}*** Mamba successfully installed. Use it as an alternative to conda. ***${RESET}"
#  fi
#fi

# Cleanup Homebrew
echo -e "${BLUE}===> Cleaning up Homebrew...${RESET}"
brew cleanup

# -------------------------------------------------------------------
# Set environment variables
# -------------------------------------------------------------------
echo -e "\n"
echo -e "${UMAGENTA}===> Start setting ENV VARs${RESET}"
#export JAVA_HOME=$(/usr/libexec/java_home)
if [[ -z "${JAVA_HOME}" ]]; then
  echo -e "${CYAN}===> Adding JAVA_HOME env variable to .zshrc...${RESET}"
  echo "# brew_install_apps.sh - Appending JAVA_HOME env var" >>~/.zshrc
  echo "export JAVA_HOME=$(/usr/libexec/java_home)" >>~/.zshrc
else
  echo -e "${CYAN}===> JAVA_HOME is already set to: ${JAVA_HOME}${RESET}"
fi

echo -e "${BLUE}===> Source .zshrc...${RESET}"
source ~/.zshrc

# -------------------------------------------------------------------
# Verify installation
# -------------------------------------------------------------------
echo -e "\n"
echo -e "${UMAGENTA}===> Start verification${RESET}"

echo -e "${BLUE}===> All installed packages (formulae and casks)...${RESET}"
brew list --versions

echo -e "${BLUE}===> Verify apps...${RESET}"

echo -e "${CYAN}===> Verify JAVA_HOME...${RESET}"
echo "$JAVA_HOME"

echo -e "${CYAN}===> Verify Java...${RESET}"
java -version

echo -e "${CYAN}===> Verify Maven...${RESET}"
mvn -version

#echo -e "${CYAN}===> Verify Conda...${RESET}"
#conda --version

echo -e "${CYAN}===> Verify Python...${RESET}"
which -a python3
python3 -V

echo -e "${BBLACK}*** Add alias rm='trash' to .zshrc ***${RESET}"
echo -e "${BBLACK}*** Add alias cat='bat' to .zshrc ***${RESET}"
