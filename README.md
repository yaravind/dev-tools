# 1. Developer Tools

I have been consistently using a series of commands for some time to reproduce a development environment across
various machines. For the most part, these commands were kept as gists. Recently, I managed to compile them all
into a single shell script and a runcom (rc) file. I hope this proves helpful to others!

> “On a UNIX system, everything is a file; if something is not a file, it is a process.” ― Machtelt Garrels,
> Introduction To Linux: A Hands-On Guide

## 1.1. Table of Contents

1. [Table of Contents](#11-table-of-contents)
2. [setup_env](#12-setup_envsh)
    1. [Developer folder](#121-developer-folder)
3. [setup_jenv](#13-setup_jenvsh)
4. [Git](#16-Git)
    1. [Pretty print all commits](#161-Pretty-print-all-commits)
    2. [List repository contributors by author name (sorted by name)](#162-List-repository-contributors-by-author-name)
    3. [List total commits by author (sorted by commit count)](#163-List-total-commits-by-author)
    4. [What changed since given date?](#164-What-changed-since-given-date)
    5. [List file change stats by author](#165-List-file-change-stats-by-author)
5. [Packages](#17-Packages)
6. [Reference](#18-Reference)

## 1.2. setup_env.sh

> ***Warning***
> 1. The script is tested on Apple M2 Pro (should also work on M1) and zsh shell.
> 2. If you haven't already installed Xcode Command Line Tools, you'll see a message that **The Xcode Command Line Tools
     will be installed.**

Check the output below to see if the Command Line Tools are installed:

```console
    ==> Searching online for the Command Line Tools
    ==> /usr/bin/sudo /usr/bin/touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    ==> Installing Command Line Tools for Xcode-15.3
    ==> /usr/bin/sudo /usr/sbin/softwareupdate -i Command\ Line\ Tools\ for\ Xcode-15.3
    Software Update Tool

    Finding available software

    Downloading Command Line Tools for Xcode
    Downloaded Command Line Tools for Xcode
    Installing Command Line Tools for Xcode

    Done with Command Line Tools for Xcode
```

1. Change to `bash` shell as Homebrew install script uses batch. Type `bash` and hit enter. You would
   see error "Bash is required to interpret this script" otherwise.
2. Install [Homebrew](https://brew.sh/) (**Pre-requisite**)
3. Clone this repo: `git clone https://github.com/yaravind/dev-tools.git`
4. cd `dev-tools`
5. Copy `.zshrc` (or `.bashrc` based on your shell) to home directory: <kbd>mv .zshrc ~/</kbd>
6. Make `setup_env.sh` executable: `chmod +x setup_env.sh`
7. Run: `./setup_env.sh`

> ***Warning (on macOS)***
>
> Your terminal does not have App Management permissions, so Homebrew will delete and reinstall the app.
> This may result in some configurations (like notification settings or location in the Dock/Launchpad) being lost.
> To fix this, go to System Settings > Privacy & Security > App Management and add or enable your terminal.

**Details**

`set_env.sh` automates the installation and configuration of various developer tools for Apple M1/M2 Pro. At a high
level it will

- Disables the terminal login banner.
- Install developer command-line and other productivity tools (JDK compatible with M1/M2, Maven, Mamba, Conda, Python
  etc.).
- Install modern developer fonts.
- Install IntelliJ IDEA CE/Ultimate, PyCharm CE/Ultimate and VS Code.
- Set required environment variables.
- Verify and highlight the successful installation and configuration of the tools.
- Some notable tools include

**Installed productivity shell utils**

| Utility     | Usage                                                                    |
|-------------|--------------------------------------------------------------------------|
| htop	       | Improved top (interactive process viewer)                                |
| tree	       | Display directories as trees (with optional color/HTML output)           |
| jq	         | Lightweight and flexible command-line JSON processor                     |
| gh	         | GitHub command-line tool                                                 |
| azure-cli	  |                                                                          |
| tldr	       | Simplified and community-driven man pages                                |
| fig	        | Adds IDE-style autocomplete to the terminal                              |
| exa	        | Exa is a modern replacement for the ls command                           |
| trash	      | Moves files to the trash, which is safer because it is reversible        |
| jenv	       | Manage multiple versions of Java                                         |
| bat	        | Clone of cat(1) with syntax highlighting and Git integration             |
| thefuck	    | Programmatically correct last mistyped console command                   |
| micromamba	 | micromamba is faster alternative to conda, gives clearer error reporting |
| lnav        | tool for viewing and analyzing log files                                 |
| node        | JavaScript runtime environment                                           |
| llm         | Access large language models from the command-line                       |

> Highly recommend this course if you are beginning your career as a software engineer:
> [Unix Tools: Data, Software and Production Engineering](https://www.edx.org/course/unix-tools-data-software-and-production-engineering)
> by Prof. Diomidis Spinellis.

### 1.2.1 Developer Folder

`mkdir ~/Developer`: It has a fancy icon in finder!

## 1.3 setup_jenv.sh

`setp_jenv.sh` automates the process of adding Java Virtual Machine (JVM) installations to the `jenv` version manager on
a
macOS system. Here is an overview of what the script does:

1. Uses `/usr/libexec/java_home --xml` to get xml output of the installed JVMs.
2. Parses the installation directories using `xmllint`
3. Adds the JVMs to `jenv` using `jenv add` command.
4. Lists the JVMs managed `jenv versions` command.

To list the version, architecture, and folder location of all installed JVMs on your Mac:

```$ /usr/libexec/java_home --verbose```

Output:

```shell
Matching Java Virtual Machines (2):
    11.0.25 (arm64) "Microsoft" - "OpenJDK 11.0.25" /Library/Java/JavaVirtualMachines/microsoft-11.jdk/Contents/Home
    1.8.0_422 (arm64) "Amazon" - "Amazon Corretto 8" /Users/aravind/Library/Java/JavaVirtualMachines/corretto-1.8.0_422/Contents/Home
/Library/Java/JavaVirtualMachines/microsoft-11.jdk/Contents/Home

```

## 1.6. Git

Add the following aliases to `.bashrc`

```shell
alias gcfg='git config -l'
alias gs='git status '
alias ga='git add '
alias gb='git branch '
alias gc='git commit -m'
alias gca='git commit --amend -m'
alias gac='git add -A . && git commit -m'
alias gp='git push origin master'
alias gd='git diff'
alias go='git checkout '
alias gl='git log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate'
alias gsl='git shortlog'
alias gslu='git log --format='%aN' | sort -u'
alias gslc='git shortlog -sn'

gsu() { git log --shortstat --author="$1" | grep -E "fil(e|es) changed" | awk '{files+=$1; inserted+=$4; deleted+=$6; delta+=$4-$6; ratio=deleted/inserted} END {printf "Commit stats:\n- Files changed (total)..  %s\n- Lines added (total)....  %s\n- Lines deleted (total)..  %s\n- Total lines (delta)....  %s\n- Add./Del. ratio (1:n)..  1 : %s\n", files, inserted, deleted, delta, ratio }' - ;}

gw() { git whatchanged --since "$1" --oneline --name-only --pretty=format: | sort | uniq; }
```

##### 1.6.1. Pretty print all commits

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gl
5e737fc (HEAD -> master)\ add examples for git commands\ [Aravind R. Yarram]
accef64 (origin/master, origin/HEAD)\ add exaples for find & locate\ [Aravind R. Yarram]
d592777\ add history command examples\ [Aravind R. Yarram]
46b5609\ add references\ [Aravind R. Yarram]
caa8be3\ add references\ [Aravind R. Yarram]
6c3afc4\ add TOC\ [Aravind R. Yarram]
6d72532\ add TOC\ [Aravind R. Yarram]
75d2fe9\ add examples for which and alias  commands\ [Aravind R. Yarram]
ff00092\ add examples for file command\ [Aravind R. Yarram]
f0b1593\ notes for file command\ [Aravind R. Yarram]
d4c2afb\ format content\ [Aravind R. Yarram]
3751b09\ add notes for Files\ [Aravind R. Yarram]
2617c7e\ Initial commit\ [GitHub]
```

##### 1.6.2. List repository contributors by author name

Output is sorted by name.

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gslu
Aravind R Yarram
Aravind R. Yarram
```

##### 1.6.3. List total commits by author

Output is sorted by commit count.

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gslc
    12  Aravind R. Yarram
     1  Aravind R Yarram
```

##### 1.6.4. What changed since given date?

```console
rishik@rishik-computer:~/ws/datasets$ gw 09/01/2018

computer/cpu-performance-data.csv
flight/2014_jan_carrier_performance.csv
.gitignore
machine-learning-a2z/Part 1 - Data Preprocessing/Data.csv
machine-learning-a2z/readme.txt
README.md
rishik@rishik-computer:~/ws/datasets$ gw "10/01/2018"

computer/cpu-performance-data.csv
flight/2014_jan_carrier_performance.csv
.gitignore
README.md
```

##### 1.6.5. List file change stats by author

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gsu Aravind R. Yarram
Commit stats:
- Files changed (total)..  18
- Lines added (total)....  490
- Lines deleted (total)..  35
- Total lines (delta)....  455
- Add./Del. ratio (1:n)..  1 : 0.0714286
```

## 1.7. Packages

Reference: https://help.ubuntu.com/community/Repositories

cat /etc/apt/sources.list - lists all the repositories

sudo apt update - updates the package index cache
sudo apt upgrade - upgrades all packages to latest versions
sudo apt upgrade <package-name> - upgrades specified package to latest version

apt-cache policy <package-name> - lists the currently installed version and available versions
apt-get install <package-name>=<version> - install specific version of a package. get version from apt-cache policy
command
apt-get install apache2=2.4.7-1ubuntu4.5

apt-mark hold <package-name> - apt-mark allows you to pin the package to an installed ver. apt/apt-get upgrade doesn't
upgrade to latest

aptitude versions <package-name> - shows all the versions available

## 1.8. Reference

- [Notes](NOTES.md)
- [The Linux Documentation Project](http://www.tldp.org/guides.html)
- [Stackoverflow](https://stackoverflow.com)
- [Git Gist](https://gist.github.com/eyecatchup/3fb7ef0c0cbdb72412fc)
- [Install custom logger formats for lnav](https://docs.lnav.org/en/latest/formats.html)

## 1.9. TODO

- https://www.warp.dev/pricing
- https://www.cursor.com/
- https://lawand.io/taskbar/
- https://displaybuddy.app/
- https://github.com/sharkdp/vivid
- https://icemenubar.app/
- https://github.com/dmarcotte/easy-move-resize
- https://www.alfredapp.com/
- https://obsidian.md/
- cmd
    - https://github.com/junegunn/fzf

Disable .DS_Store files

`defaults write com.apple.desktopservices DSDontWriteNetworkStores true`
`defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true`
`defaults write =com.apple.finder ShowPathbar -bool true` - It show the path on the bottom of finder when navigating
nested folder
