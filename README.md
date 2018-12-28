# Linux Cheatsheet
Cheatsheet of common Linux commands

## Shell
##### Known shells to Linux system
```
rishik@rishik-computer:~/ws$ cat /etc/shells
# /etc/shells: valid login shells
/bin/sh
/bin/bash
/bin/rbash
/bin/dash
```
##### Which shell am I using?
```
rishik@rishik-computer:~/ws$ echo $0
/bin/bash
rishik@rishik-computer:~/ws$ echo $SHELL
/bin/bash
```
##### What is the default shell set for each user?
```
rishik@rishik-computer:~/ws$ cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
...
rishik:x:1000:1000:Rishik,,,:/home/rishik:/bin/bash
```

## Home
##### What is your home dir?
```
rishik@rishik-computer:~/ws$ echo $HOME
/home/rishik
```

## Files
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
echo $HISTFILE - shows the file where history is being stored
history - lists all previously ran commands
!! - runs the last command
!2 - runs the command at index 2 from the output of history command

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