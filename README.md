# Developer Tools

I have been consistently using a series of commands for some time to reproduce a development environment across
various machines. For the most part, these commands were kept as gists. Recently, I managed to compile them all
into a single shell script and a runcom (rc) file. I hope this proves helpful to others!

> “On a UNIX system, everything is a file; if something is not a file, it is a process.” ― Machtelt Garrels,
> Introduction To Linux: A Hands-On Guide

## Table of Contents

1. [Notes](#Notes)
2. [Shell](#Shell)
3. [Home](#Home)
4. [Files](#Files)
5. [History](#History)
6. [Git](#Git)
7. [Users](#Users)
8. [Groups](#Groups)
9. [Permissions](#Permissions)
10. [Packages](#Packages)

## setup_env.sh

> ***Warning***
> The script is tested on Apple M2 Pro (should also work on M1) and zsh shell.

1. Install [Homebrew](https://brew.sh/) (**Pre-requisite**)
2. Clone this repo: `git clone https://github.com/yaravind/dev-tools.git`
3. cd `dev-tools`
4. Copy `.zshrc` (or `.bashrc` based on your shell) to home directory: `mv .zshrc ~/`
5. Make `setup_env.sh` executable: `chmod +x setup_env.sh`
6. Run: `./setup_env.sh`

**Details**

`set_env.sh` automates the installation and configuration of various developer tools for Apple M1/M2 Pro. At a high
level it

- disables the terminal login banner
- installs developer command and other productivity tools (JDK compatible with M1/M2, Maven, Mamba, Conda, Python etc.)
- install modern developer fonts
- sets environment variables
- verifies and highlights the successful installation and configuration of the tools
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

> Highly recommend this course if you are beginning your career as a software
> engineer: [Unix Tools: Data, Software and Production Engineering](https://www.edx.org/course/unix-tools-data-software-and-production-engineering)
> by Prof. Diomidis Spinellis.

## Notes

| Hard Link                                                                                           | Symbolic Link                                                                                                                   |
|-----------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| associate 2 or more files with same inode                                                           | a small file that is a pointer to another file                                                                                  |
| share same data blocks on hard disk. That is why hard links show the same size as the original file | contains the path to the target file instead of a physical location on the hard disk. That is why they are always small in size |
| can not span partitions because inode numbers are only unique within a given partition              | since inodes are not used in this system, soft links can span across partitions                                                 |
| `ln sfile1file link1file`                                                                           | `ln -s targetfile linkname` is used to create symbolic link                                                                     |

#### `alias` list all aliases currently set for your shell account

##### `ls` default scheme color

| Color         | File type           |
|---------------|---------------------|
| blue	         | directories         |
| red	          | compressed archives |
| white	        | text files          |
| pink	         | images              |
| cyan	         | links               |
| yellow	       | devices             |
| green	        | executables         |
| flashing red	 | broken links        |

##### `ls` default suffix scheme

| Character | 	File type      |
|-----------|-----------------|
| nothing   | 	regular file   |
| `/`	      | directory       |
| `*`	      | executable file |
| `@`	      | link            |
| `=`	      | socket          |
| `\|`      | 	named pipe     |

##### What is umask?

- `umask` setting plays a big role in determining the permissions that are assigned to files that you create
- The default permissions when creating a new dir is octal `777 (111 111 111)`, and a new file is
  octal `666 (110 110 110)`. We set the umask to block/disable certain permissions.
- A mask bit of 1 means to block/disable that permission (put masking tape over that bit).
- A mask bit of 0 will allow the permission to pass through (no masking tape over that bit).
- So an octal `022 (000 010 010)` mask means to disable group write and others write, and allow all other permissions to
  pass through.
- umask is a setting that directly controls the permissions assigned when you create files or directories. Create a new
  file using a text editor or simply with the touch command, and its permissions will be derived from your umask
  setting.
- The umask setting for all users is generally set up in a system-wide file like `/etc/profile`, `/etc/bashrc`
  or `/etc/login.defs` — a file that's used every time someone logs into the system

###### What is my default umask setting?

Ignore the first character/zero

```console
rishik@rishik-computer:~$ umask -S
u=rwx,g=rwx,o=rx
rishik@rishik-computer:~$ umask
0002
```

##### /dev/null, /dev/random, and /dev/zero

The /dev file system does not just contain files that represent physical devices. Here are three of the most notable
special devices it contains:

1. /dev/null – Discards all data written to it – think of it as a trash can or black hole. If you ever see a comment
   telling you to send complains to /dev/null – that’s a geeky way of saying “throw them in the trash.”
2. /dev/random – Produces randomness using environmental noise. It’s a random number generator you can tap into.
3. /dev/zero – Produces zeros – a constant stream of zeros.

## Shell

##### Known shells to Linux system

```console
rishik@rishik-computer:~/ws$ cat /etc/shells
# /etc/shells: valid login shells
/bin/sh
/bin/bash
/bin/rbash
/bin/dash
```

##### Which shell am I using?

```console
rishik@rishik-computer:~/ws$ echo $0
/bin/bash
rishik@rishik-computer:~/ws$ echo $SHELL
/bin/bash
```

##### What is the default shell set for each user?

```console
rishik@rishik-computer:~/ws$ cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
...
rishik:x:1000:1000:Rishik,,,:/home/rishik:/bin/bash
```

## Home

##### What is my home dir?

```console
rishik@rishik-computer:~/ws$ echo $HOME
/home/rishik
```

## Files

##### Guess the file type!

```console
rishik@rishik-computer:~/Downloads$ file ideaIC-2018.3.2.tar.gz 
ideaIC-2018.3.2.tar.gz: gzip compressed data, from FAT filesystem (MS-DOS, OS/2, NT)
```

```console
rishik@rishik-computer:~/ws$ file datasets/citibikenyc/JC-201709-citibike-tripdata.csv 
datasets/citibikenyc/JC-201709-citibike-tripdata.csv: ASCII text
```

```console
rishik@rishik-computer:~$ file /dev/sda
/dev/sda: block special (8/0)
rishik@rishik-computer:~$ file /dev/sda1
/dev/sda1: block special (8/1)
rishik@rishik-computer:~$ file /dev/null
/dev/null: character special (1/3)
```

##### Find executable file

`which` searches the user's search `PATH`. Good for troubleshooting `Command not found` problems.

```console
rishik@rishik-computer:~$ which -a java
/usr/bin/java
rishik@rishik-computer:~$ which docker
/usr/bin/docker
```

##### Check if a command is an alias for another command!

```console
rishik@rishik-computer:~$ alias ls
alias ls='ls --color=auto'
rishik@rishik-computer:~$ alias ltr
alias ltr='ls -ltr'
```

##### Find all files whose filename has "readme" in it

```console
rishik@rishik-computer:~$ find /usr -name "*readme*"
/usr/share/snmp/mib2c-data/mfd-readme.m2c
/usr/share/snmp/mib2c-data/syntax-DateAndTime-readme.m2i
/usr/share/mime/text/x-readme.xml
/usr/share/icons/elementary/mimes/128/text-x-readme.svg
/usr/share/icons/elementary/mimes/64/text-x-readme.svg
/usr/share/icons/elementary/mimes/32/text-x-readme.svg
/usr/share/icons/elementary/mimes/16/text-x-readme.svg
/usr/share/icons/elementary/mimes/24/text-x-readme.svg
/usr/share/icons/elementary/mimes/48/text-x-readme.svg
/usr/share/games/assaultcube/packages/maps/official/official_readme.txt
/usr/share/games/assaultcube/packages/maps/preview/readme.txt
/usr/share/games/assaultcube/packages/maps/servermaps/readme.txt
/usr/share/games/assaultcube/packages/textures/kurt/dummyfiles_readme.txt
/usr/share/doc/assaultcube-data/docs/cube_bot-readme.txt.gz
/usr/share/doc/aufs-tools/examples/uloop/00readme.txt.gz
/usr/share/doc/p7zip/DOC/readme.txt.gz
/usr/share/lintian/checks/debian-readme.pm
/usr/share/lintian/checks/debian-readme.desc
```

##### Find all files bigger than 100MB

```console
rishik@rishik-computer:~$ find . -size +100M
./Downloads/ideaIC-2018.3.2.tar.gz
./.config/epiphany/gsb-threats.db
```

##### Find all files whose filename has "readme" in it

`locate` is fast as its output is based on file index database. But it is refreshed only once every day.

```console
rishik@rishik-computer:~$ locate readme
/home/rishik/ws/datasets/machine-learning-a2z/readme.txt
/usr/share/doc/aufs-tools/examples/uloop/00readme.txt.gz
/usr/share/doc/p7zip/DOC/readme.txt.gz
/usr/share/icons/elementary/mimes/128/text-x-readme.svg
/usr/share/icons/elementary/mimes/16/text-x-readme.svg
/usr/share/icons/elementary/mimes/24/text-x-readme.svg
/usr/share/icons/elementary/mimes/32/text-x-readme.svg
/usr/share/icons/elementary/mimes/48/text-x-readme.svg
/usr/share/icons/elementary/mimes/64/text-x-readme.svg
/usr/share/lintian/checks/debian-readme.desc
/usr/share/lintian/checks/debian-readme.pm
/usr/share/mime/text/x-readme.xml
/usr/share/snmp/mib2c-data/mfd-readme.m2c
/usr/share/snmp/mib2c-data/syntax-DateAndTime-readme.m2i
rishik@rishik-computer:~$ 
```

## History

- `history` lists all previously ran commands
- `!!` runs the last command
- `!2` runs the command at index 2 from the output of history command

##### Where is my history stored?

```console
rishik@rishik-computer:~$ echo $HISTFILE
/home/rishik/.bash_history
```

## Git

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

##### Pretty print all commits

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

##### List repository contributors by author name (sorted by name)

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gslu
Aravind R Yarram
Aravind R. Yarram
```

##### List total commits by author (sorted by commit count)

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gslc
    12  Aravind R. Yarram
     1  Aravind R Yarram
```

##### What changed since given date?

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

##### List file change stats by author

```console
rishik@rishik-computer:~/ws/linux-cheatsheet$ gsu Aravind R. Yarram
Commit stats:
- Files changed (total)..  18
- Lines added (total)....  490
- Lines deleted (total)..  35
- Total lines (delta)....  455
- Add./Del. ratio (1:n)..  1 : 0.0714286
```

## Users

##### What is my username?

```console
rishik@rishik-computer:~$ echo $USER
rishik
rishik@rishik-computer:~$ whoami
rishik
```

## Groups

##### What is my default group and other groups I belong to?

```console
rishik@rishik-computer:~$ id
uid=1000(rishik) gid=1000(rishik) groups=1000(rishik),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),118(lpadmin),127(sambashare)
```

:warning:
> User private group scheme:
> In order to allow more flexibility, most Linux systems follow the so
> called user private group scheme, that assigns each user primarily to his
> or her own group. This group is a group that only contains this
> particular user, hence the name "private group". Usually this group has
> the same name as the user login name, which can be a bit confusing.

##### What other groups do I belong to?

:warning: `groups` is deprecated in lieu of `id -Gn`

```console
rishik@rishik-computer:~$ groups rishik
rishik : rishik adm cdrom sudo dip plugdev lpadmin sambashare docker
rishik@rishik-computer:~$ id -Gn rishik
rishik adm cdrom sudo dip plugdev lpadmin sambashare docker
````

##### How can I log in to other groups I belong to? For e.g. docker

```console
rishik@rishik-computer:~$ id
uid=1000(rishik) gid=1000(rishik) groups=1000(rishik),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),118(lpadmin),127(sambashare)

rishik@rishik-computer:~$ newgrp docker

rishik@rishik-computer:~$ id
uid=1000(rishik) gid=999(docker) groups=999(docker),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),118(lpadmin),127(sambashare),1000(rishik)

rishik@rishik-computer:~$ newgrp rishik

rishik@rishik-computer:~$ id
uid=1000(rishik) gid=1000(rishik) groups=1000(rishik),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),118(lpadmin),127(sambashare),999(docker)
``` 

##### How to change user and group ownership on a file or directory?

- `sudo chown ownerName:groupName [dir | fileName]` - change owner and group of a folder or file
- `sudo chgrp` - change only group permissions
- Both `chown` and `chgrp` can be used to change ownership recursively, using the `-R` option

## Permissions

Use `chmod` to change access modes for user, group or others.

## Packages

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

## Reference

- [The Linux Documentation Project](http://www.tldp.org/guides.html)
- [Stackoverflow](https://stackoverflow.com)
- [Git Gist](https://gist.github.com/eyecatchup/3fb7ef0c0cbdb72412fc)