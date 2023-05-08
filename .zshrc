# Function to parse git branch
function parse_git_branch() {
    git branch 2> /dev/null | sed -n -e 's/^\* \(.*\)/[\1]/p'
}

# Define colors
COLOR_DEF=$'%f'
COLOR_USR=$'%F{243}'
COLOR_DIR=$'%F{197}'
COLOR_GIT=$'%F{39}'

# Set prompt options
setopt PROMPT_SUBST
export PROMPT='${COLOR_USR}%T ${COLOR_DIR}%~ ${COLOR_GIT}$(parse_git_branch)${COLOR_DEF} $ '

# Uncomment for different prompt styles
#PROMPT="%F{yellow}%T%f %F{magenta}%2~%f> "
#PROMPT='%B%U%F{blue}%n%u%b> %f'

# Make some commands (potentially) less destructive by moving them to Recycle Bin/Trash
alias rm=trash
#alias rm="rm -i"

# Syntax coloring for files - show line numbers
alias cat="bat -n"

# Set color for ls
export CLICOLOR=1

# Update PATH for Python 3.10
export PATH="/opt/homebrew/opt/python@3.10/libexec/bin:$PATH"

# Configure thefuck tool https://github.com/nvbn/thefuck/wiki/Shell-aliases
eval "$(thefuck --alias fix)"

# Reload zshrc
alias reload="source $HOME/.zshrc"

# Count files in current directory
alias filecount='ls -aRF | wc -l'

# Grabs the disk usage in the current directory
alias usage='du -ch | grep total'

# Gets the total disk usage on your machine
alias totalusage='df -h | awk "NR>1 {total+=\$3} END {printf \"%.2f%s\n\", total/1024, \"G\"}"'

# Shows top 10 largest directories and files in the current directory
alias most='du -hsx * | sort -rh | head -10'

# Get total disk size
alias disksize='df -k / | awk '\''NR==2{printf("%.2f GB\n", ($4 * 1024) / (10^9))}'\'

# Copy the working directory path
alias cpwd='pwd|tr -d "\n" | pbcopy'

# Display all the files and directories (including hidden ones -a) in the current directory, in a long-format -l listing with
# human-readable file sizes -h and additional characters indicating the file types -F /=dir, *=executable, @=sym link.
alias ltr="ls -ltrFh"
alias lta="ls -alFh"

alias cls="clear"
alias c="clear"

# List only directories
alias ld='ls -ldh */'

# List only files (exclude hidden files)
alias lf='ls -lph | grep -v /'

# List only files (include hidden files)
alias lfa='ls -alph | grep -v /'
alias l.="ls -A | egrep '^\.'"      # List only dotfiles (hidden files)

# Open the current directory in Finder (Mac only)
alias o="open ."

#I can just run "up" to "cd ..", or I can run "up 6" to "cd ../../../../../.."
function up {
        if [[ "$#" < 1 ]] ; then
            cd ..
        else
            CDSTR=""
            for i in {1..$1} ; do
                CDSTR="../$CDSTR"
            done
            cd $CDSTR
        fi
}

## A quick way to get out of current directory ##
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../..'
alias ~="cd ~"

# History
alias hist='history'
alias h='history'
alias h1="history 10"
alias h2="history 15"
alias h3="history 20"
# History search (use: hs sometext).
# if you want to search your command history for any commands containing the word "git," you would run hs git
alias hs='history | grep $1'

#pretty format json using python tool
#usage: prettyjson file.json
#OR pipe un-formatted to these to nicely format the JSON e.g. cat file.json | prettyjson
alias prettyjson='python -m json.tool'
alias json="python -m json.tool"

#git
alias gi='git init'
alias gs='git status '
alias ga='git add '
alias gb='git branch '
alias gc='git commit -m'
alias gca='git commit --amend -m'
alias gp='git push origin master'
alias gd='git diff'
alias go='git checkout '
alias gl='git log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate'
alias gld='git log --pretty=format:"%h %ad %s" --date=short --all'
alias gsl='git shortlog'
#List repository contributors by author name (sorted by name):
alias gslu='git log --format='%aN' | sort -u'
#List total commits by author (sorted by commit count)
alias gslc='git shortlog -sn'
#List file change stats by author
gsu() { git log --shortstat --author="$1" | grep -E "fil(e|es) changed" | awk '{files+=$1; inserted+=$4; deleted+=$6; delta+=$4-$6; ratio=deleted/inserted} END {printf "Commit stats:\n- Files changed (total)..  %s\n- Lines added (total)....  %s\n- Lines deleted (total)..  %s\n- Total lines (delta)....  %s\n- Add./Del. ratio (1:n)..  1 : %s\n", files, inserted, deleted, delta, ratio }' - ;}
#List what changed since given date
gw() { git whatchanged --since "$1" --oneline --name-only --pretty=format: | sort | uniq; }
# Git log find by commit message
glf() { git log --all --grep="$1"; }
# git log graph" and presents a compact, visual representation of the commit history. It displays the commit history
# as a graph with one line per commit, including decorations for branches and tags, and shows the history across all branches.
alias glg='git log --graph --oneline --decorate --all'

#tar
alias untar='tar -zxvf '

#know your external IP address
alias ipe='curl ipinfo.io/ip'

# Python version
alias pv='python --version'

## get top process eating memory
alias psmem='ps -arcwwwxo "pid %mem command" | head -n 2'
alias psmem10='ps -arcwwwxo "pid %mem command" | head -n 10'

## get top process eating cpu
alias pscpu='ps aux | sort -nrk 3,3 | head -n 1'
alias pscpu10='ps aux | sort -nrk 3,3 | head -n 10'

## Get CPU info
alias cpuinfo='sysctl -n machdep.cpu.brand_string'

# Get CPU cores
# Alias to get CPU cores on macOS
alias cpucount="sysctl -n hw.physicalcpu"

# Display total and used RAM in macOS
alias ramusage="echo 'Total RAM: $(($(sysctl -n hw.memsize) / 1024**3))GB'; vm_stat | grep 'Pages active' | awk '{print \"Used RAM: \" int(\$3*4096/1024**3)\"GB\"}'"

# Display total and used CPU in macOS
alias cpuusage="echo 'Total CPU cores: '; sysctl -n hw.ncpu; echo 'CPU usage (%):'; top -l 1 | awk '/CPU usage/ {print $3}'"

## Get GPU info
alias gpuinfo="system_profiler SPDisplaysDataType | grep -E '(Chipset Model:|Type:|VRAM \(Total\):|Device ID:|Revision ID:)'"

# Apache Maven
alias mvni='mvn clean install'
alias mvnc='mvn clean compile'
alias mvnt="mvn clean test"
alias mvnp='mvn clean package'