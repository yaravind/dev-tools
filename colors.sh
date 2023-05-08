# -------------------------------------------------------------------
# ANSI Escape codes for shells: bash
# -------------------------------------------------------------------
RESET="\e[0m"

# Regular Colors
BLACK='\033[0;30m'  # Black
RED='\033[0;31m'    # Red
GREEN='\033[0;32m'  # Green
YELLOW='\033[0;33m' # Yellow
BLUE='\033[0;34m'   # Blue
PURPLE='\033[0;35m' # Purple
CYAN='\033[0;36m'   # Cyan
WHITE='\033[0;37m'  # White
MAGENTA="\e[35m"    # Magenta

# Bold
BBLACK='\033[1;30m'  # Black
BRED='\033[1;31m'    # Red
BGREEN='\033[1;32m'  # Green
BYELLOW='\033[1;33m' # Yellow
BBLUE='\033[1;34m'   # Blue
BPURPLE='\033[1;35m' # Purple
BCYAN='\033[1;36m'   # Cyan
BWHITE='\033[1;37m'  # White
BMAGENTA="\e[1;35m"  # Magenta

# Underline
UBLACK='\033[4;30m'  # Black
URED='\033[4;31m'    # Red
UGREEN='\033[4;32m'  # Green
UYELLOW='\033[4;33m' # Yellow
UBLUE='\033[4;34m'   # Blue
UPURPLE='\033[4;35m' # Purple
UCYAN='\033[4;36m'   # Cyan
UWHITE='\033[4;37m'  # White
UMAGENTA="\e[4;35m"  # Magenta

# -------------------------------------------------------------------
# zsh: You can use prompt sequences instead of ANSI escape codes
# Example usage: Print colored text using print and prompt expansion
# print -P "%F{red}This is red text%f"
# -------------------------------------------------------------------

# Regular Colors
Black="%F{black}"
Red="%F{red}"
Green="%F{green}"
Yellow="%F{yellow}"
Blue="%F{blue}"
Purple="%F{magenta}"
Cyan="%F{cyan}"
White="%F{white}"

# Bold
BBlack="%B%F{black}%b"
BRed="%B%F{red}%b"
BGreen="%B%F{green}%b"
BYellow="%B%F{yellow}%b"
BBlue="%B%F{blue}%b"
BPurple="%B%F{magenta}%b"
BCyan="%B%F{cyan}%b"
BWhite="%B%F{white}%b"

# Underline
UBlack="%U%F{black}%u"
URed="%U%F{red}%u"
UGreen="%U%F{green}%u"
UYellow="%U%F{yellow}%u"
UBlue="%U%F{blue}%u"
UPurple="%U%F{magenta}%u"
UCyan="%U%F{cyan}%u"
UWhite="%U%F{white}%u"
