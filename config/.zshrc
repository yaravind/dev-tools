# ============================================================
# 1. SHELL MANAGEMENT
# ============================================================
alias profile='nano ~/.zshrc'
alias reload='source ~/.zshrc && echo "Done"'
alias cpreload='cp .zshrc ~/ && source ~/.zshrc && echo "Done"'
alias c="clear"
export EDITOR=/usr/bin/nano

# ============================================================
# 2. NAVIGATION
# ============================================================
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../../'
alias .5='cd ../../../../..'
alias ~="cd ~"

# Run "up" to "cd ..", or "up 6" to go 6 levels up
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

# ============================================================
# 3. FILE LISTING
# ============================================================
alias ltr="eza -l -t modified -r -F -h --color=always"
alias lta="eza -a -l -F -h --color=always"            # -F appends symbols to filenames
alias ld='setopt +o nomatch; eza -ldh */ 2>/dev/null || eza -ldh .; setopt -o nomatch'  # directories only
alias lf='eza -l --color=always | grep --color=always -v /$'    # files only (no hidden)
alias lfa='eza -al --color=always | grep --color=always -v /$'  # files only (include hidden)
alias l.='eza -a | grep "^\."'                         # dotfiles only
alias o="open ."                                        # open current directory in Finder

# ============================================================
# 4. FILE OPERATIONS
# ============================================================
alias rm='trash'
alias cat='bat'
alias untar='tar -zxvf '
alias cpwd='pwd|tr -d "\n" | pbcopy'                   # copy working directory path to clipboard
alias usage='du -ch | grep total'                       # disk usage in current directory
alias totalusage='df -hl'                               # total disk usage on machine
alias most='du -hsx * | sort -rh | head -10'            # top 10 largest files/dirs

# ============================================================
# 5. NETWORK
# ============================================================
alias myip="curl https://ipinfo.io/json"                # external IP with full info (location, org, etc.)
alias ipe='curl ipinfo.io/ip'                           # external IP plain text
alias ipi='ipconfig getifaddr en0'                      # local/internal IP address
alias speedtest="curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -"

# ============================================================
# 6. SYSTEM INFO
# ============================================================
alias path='echo -e ${PATH//:/\n}'

alias meminfo='
echo "--- Physical Memory ---";
sysctl hw.memsize | awk "{printf \"%-15s %10.2f GB\n\", \"Total RAM:\", \$2/(1024^3)}";
vm_stat | perl -ne "/page size of (\d+) bytes/ && (\$s=\$1); /Pages (\w+(?:\s\w+)*): \s+(\d+)/ && printf(\"%-15s %10.2f MB\n\", \$1, \$2*\$s/1024/1024);" | grep -E "free|active|inactive|wired|occupied by compressor" | awk "{
    label=\$1;
    val=\$(NF-1);
    if (\$1==\"occupied\") {label=\"compressed\"}
    if (\$1==\"wired\") {label=\"wired\"}

    if (val >= 1024) {
        printf \"%-15s %10.2f GB\n\", label, val/1024
    } else {
        printf \"%-15s %10.2f MB\n\", label, val
    }
}";
echo "\n--- Logical Calculation ---";
echo "Total RAM ≈ (Active + Inactive + Wired + Compressed + Free)";
echo "\n--- Legend ---";
echo "Active:     RAM currently in use by running processes.";
echo "Inactive:   Recently used RAM; kept for quick re-opening of apps.";
echo "Wired:      Essential system memory that cannot be moved to disk.";
echo "Compressed: Memory zipped to save space; much faster than using SSD swap.";
echo "Free:       Empty RAM doing nothing (Wasted RAM).";
'

alias cpuinfo='
echo "--- CPU Hardware Information ---";
sysctl -n machdep.cpu.brand_string | awk "{print \"Model:             \", \$0}";
sysctl -n machdep.cpu.core_count | awk "{print \"Total Cores:       \", \$1}";
sysctl -n machdep.cpu.cores_per_package | awk "{print \"Cores per Package: \", \$1}";
sysctl -n machdep.cpu.thread_count | awk "{print \"Total Threads:     \", \$1}";
echo "\n--- Legend ---";
echo "Model:             The specific Apple Silicon chip generation.";
echo "Total Cores:       The total number of physical processing units.";
echo "Cores per Package: Number of cores inside the physical M4 Max chip.";
echo "Total Threads:     Simultaneous tasks the CPU can handle.";
echo "\n--- Note on Apple Silicon ---";
echo "Because Apple uses a System-on-a-Chip (SoC) design, there is only";
echo "ONE package. Therefore, Cores per Package and Total Cores are identical.";
'

alias gpumeminfo='system_profiler SPDisplaysDataType | grep -E "Chipset|Vendor|Metal|VRAM"'

# ============================================================
# 7. PROCESS MONITOR
# ============================================================
alias psmem='ps -A -o pid=PID,pmem=%MEM,comm=COMMAND | tail -n +2 | sort -nr -k 2'
alias psmem10='ps -A -o pid=PID,pmem=%MEM,comm=COMMAND | tail -n +2 | sort -nr -k 2 | head -10'
alias pscpu='ps aux | sort -nr -k 3'
alias pscpu10='ps aux | sort -nr -k 3 | head -10'

# ============================================================
# 8. HISTORY
# ============================================================
alias h='history'
alias h1='history | tail -10'
alias h2='history | tail -20'
alias h3='history | tail -30'
hs() { history | grep "$1"; }                           # search history (usage: hs sometext)

# ============================================================
# 9. SEARCH & TEXT
# ============================================================
alias grep='grep --color=auto'
alias json='jq .'                                       # pretty format json (usage: json file.json  OR  cat file.json | json)

# ============================================================
# 10. GIT
# ============================================================
alias gi='git init'
alias gs='git status '
alias ga='git add '
alias gb='git branch '
alias gc='git commit -m'
alias gca='git commit --amend -m'
alias gp='git push origin $(git branch --show-current)'
alias gd='git diff'
alias gco='git checkout '
alias gl='git log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate'
alias gld='git log --pretty=format:"%h %ad %s" --date=short --all'
alias gsl='git shortlog'
alias gslu='git log --format="%aN" | sort -u'          # list contributors by name
alias gslc='git shortlog -sn'                           # total commits by author
gsu() { git log --shortstat --author="$1" | grep -E "fil(e|es) changed" | awk '{files+=$1; inserted+=$4; deleted+=$6; delta+=$4-$6; ratio=deleted/inserted} END {printf "Commit stats:\n- Files changed (total)..  %s\n- Lines added (total)....  %s\n- Lines deleted (total)..  %s\n- Total lines (delta)....  %s\n- Add./Del. ratio (1:n)..  1 : %s\n", files, inserted, deleted, delta, ratio }' - ;}
gw() { git whatchanged --since "$1" --oneline --name-only --pretty=format: | sort | uniq; }
glf() { git log --all --grep="$1"; }                   # find commit by message

# ============================================================
# 11. GITHUB CLI
# ============================================================
alias ghr='gh repo view --web'                          # open current repo in browser
alias ghpr='gh pr list'                                 # list open PRs
alias ghprc='gh pr create'                              # create a PR
alias ghprv='gh pr view --web'                          # open current PR in browser
alias ghis='gh issue list'                              # list issues
alias ghisc='gh issue create'                           # create an issue

# ============================================================
# 12. CONFIG EDITORS
# ============================================================
alias hosts='sudo nano /etc/hosts'
alias gitconfig='nano ~/.gitconfig'
alias sshconfig="${EDITOR:-nano} ~/.ssh/config"

# ============================================================
# 13. JAVA / MAVEN
# ============================================================
alias jdks='/usr/libexec/java_home -V'
alias mvni='mvn clean install'
alias mvnc='mvn clean compile'
alias mvnp='mvn clean package'

export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"

# ============================================================
# 14. TOOLS & INTEGRATIONS
# ============================================================
eval "$(thefuck --alias)"                               # type 'fuck' to correct last failed command
eval "$(direnv hook zsh)"                               # auto-load .envrc on directory change
alias tldr='tlrc'                                       # quick command examples
alias logs='lnav'                                       # interactive log file navigator
