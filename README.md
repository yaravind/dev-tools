# Linux Cheatsheet
Cheatsheet of common Linux commands. Derived from

- [The Linux Documentation Project](http://www.tldp.org/guides.html)
- [Stackoverflow](https://stackoverflow.com)
- [Git Gist](https://gist.github.com/eyecatchup/3fb7ef0c0cbdb72412fc)

## Table of Contents
1. [Shell](#Shell)
2. [Home](#Home)
3. [Files](#Files)
4. [History](#History)
5. [Git](#Git)
6. [Groups](#Groups)
7. [Permissions](#Permissions)
8. [Packages](#Packages)

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

`locate` is fast as its output is based on file index database. But it is refreshed only once everyday.
 
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
##### `ls` default scheme color

| Color | File type |
| --- | --- |
| blue	| directories |
| red	| compressed archives |
| white	| text files |
| pink	| images |
| cyan	| links |
| yellow	| devices |
| green	| executables |
| flashing red	| broken links |

##### `ls` default suffix scheme

| Character |	File type |
| --- | --- |
| nothing |	regular file |
| `/`	 |directory |
| `*`	 |executable file |
| `@`	 |link |
| `=`	 |socket |
| `\|` |	named pipe |


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

```.bashrc
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

## Groups
groups <userid> - list all the groups a user belongs to. deprecated.
id <userid> - groups with more details
id -Gn <userid>

## Permissions
sudo chown ownerName:groupName [dir | fileName] - change owner and group of a folder or file

## Packages
Reference: https://help.ubuntu.com/community/Repositories

cat /etc/apt/sources.list - lists all the repositories

sudo apt update - updates the package index cache
sudo apt upgrade - upgrades all packages to latest versions
sudo apt upgrade <package-name> - upgrades specified package to latest version

apt-cache policy <package-name> - lists the currently installed version and available versions
apt-get install <package-name>=<version> - install specific version of a package. get version from apt-cache policy command
apt-get install apache2=2.4.7-1ubuntu4.5

apt-mark hold <package-name> - apt-mark allows you to pin the package to an installed ver. apt/apt-get upgrade doesn't upgrade to latest 

aptitude versions <package-name> - shows all the versions available