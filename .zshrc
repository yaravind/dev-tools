alias profile='nano ~/.zshrc'
alias reload='source ~/.zshrc && echo "Done"'
alias hosts='sudo nano /etc/hosts'
alias gitconfig='nano ~/.gitconfig'

alias rm='trash'
alias cat='bat'

# Grabs the disk usage in the current directory
alias usage='du -ch | grep total'
# Gets the total disk usage on your machine
alias totalusage='df -hl --total | grep total'
# Shows the individual partition usages without the temporary memory values
alias partusage='df -hlT --exclude-type=tmpfs --exclude-type=devtmpfs'
# Gives you what is using the most space. Both directories and files. Varies on current directory
alias most='du -hsx * | sort -rh | head -10'

# copy the working directory path
alias cpwd='pwd|tr -d "\n" | pbcopy'

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


# ----------------------------------------Aravind bashrc ----------------------------------------

# External IP/Internet Speed
alias myip="curl https://ipinfo.io/json" # or /ip for plain-text ip
alias speedtest="curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -"
alias path='echo -e ${PATH//:/\n}'

alias cls="clear"
alias c="clear"
alias ltr="eza -l -t modified -r -F -h"
#-F appends symbols to filenames.
alias lta="eza -a -l -F -h"
#list only directories
alias ld='setopt +o nomatch; eza -ldh */ 2>/dev/null || eza -ldh .; setopt -o nomatch'
#list only files (exclude hidden files)
alias lf='eza -l --color=always | grep --color=always -v /$'
#list only files (include hidden files)
alias lfa='eza -al --color=always | grep --color=always -v /$'
# List only dotfiles (hidden files)
alias l.='eza -a | grep "^\."'

# Open the current directory in Finder (Mac only)
alias o="open ."

## a quick way to get out of current directory ##
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../..'
alias ~="cd ~"

#History
alias hist='history'
alias h='history'
alias h1='history 10'
alias h2='history 15'
alias h3='history 20'
# History search (use: hs sometext)
hs() { history | grep "$1"; }

## Colorize the grep command output for ease of use (good for log files)##
alias grep='grep --color=auto'

# install  colordiff package :)
alias cdiff='colordiff'

#pretty format json using python tool
#usage: prettyjson file.json
#OR pipe unformatted to these to nicely format the JSON e.g. cat file.json | prettyjson
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

#tar
alias untar='tar -zxvf '

#know your external IP address
alias ipe='curl ipinfo.io/ip'

#know your local/internal IP address
alias ipi='ipconfig getifaddr en0'

#repository
alias aptu='sudo apt-get update && sudo apt-get upgrade'

## pass options to free ##
alias meminfo='free -m -l -t'
 
## get top process eating memory
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
 
## get top process eating cpu ##
alias pscpu='ps auxf | sort -nr -k 3'
alias pscpu10='ps auxf | sort -nr -k 3 | head -10'
 
## Get server cpu info ##
alias cpuinfo='lscpu'
 
## older system use /proc/cpuinfo ##
##alias cpuinfo='less /proc/cpuinfo' ##
 
## get GPU ram on desktop / laptop##
alias gpumeminfo='grep -i --color memory /var/log/Xorg.0.log'

# Edit shortcuts for config files
alias sshconfig="${EDITOR:-nano} ~/.ssh/config"
alias bashrc="${EDITOR:-nano} +120 ~/.bashrc && source ~/.bashrc && echo Bash config edited and reloaded."

#Maven
alias mvni='mvn clean install'
alias mvnc='mvn clean compile'
alias mvnp='mvn clean package'

# Default editor to Nano - http://stackoverflow.com/questions/41866734/what-is-the-advantage-of-setting-a-default-editor-for-bash
export EDITOR=/usr/bin/nano

# jenv setup
export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"
