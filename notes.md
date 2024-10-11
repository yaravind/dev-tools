# 1. Notes

## 1.1. Table of Contents

1. [Table of Contents](#11-table-of-contents)
2. [Colorized Logs](#12-colorized-logs)
2. [Notes](#13-notes)
5. [Common Commands](#14-Common-Commands)
    1. [Shell](#141-Shell)
    2. [Home](#142-Home)
    3. [Files](#143-Files)
    4. [History](#144-History)
    5. [Users](#145-Users)
    6. [Groups](#146-Groups)
    7. [Permissions](#147-Permissions)

## 1.2. Colorized Logs

`setup_env.sh` installs `lnv` package that enables tailing and colorizing logs, searching etc. Run the following
commands after running the setup to set up a custom log viewer for python logs.

This enables colorized viewer for the following python log format:

`[%(asctime)s] %(levelname)s %(name)s - %(message)s`

```console
% mkdir -p ~/.lnav/formats/ 
% cp lnav_format_python.json ~/.lnav/formats/
% lnav -i ~/.lnav/formats/lnav_format_python.json
✔ installed -- /Users/O60774/.lnav/formats/installed/pythonlogger.json
%    
```

## 1.3. Notes

| Hard Link                                                                                           | Symbolic Link                                                                                                                   |
|-----------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| associate 2 or more files with same inode                                                           | a small file that is a pointer to another file                                                                                  |
| share same data blocks on hard disk. That is why hard links show the same size as the original file | contains the path to the target file instead of a physical location on the hard disk. That is why they are always small in size |
| can not span partitions because inode numbers are only unique within a given partition              | since inodes are not used in this system, soft links can span across partitions                                                 |
| `ln sfile1file link1file`                                                                           | `ln -s targetfile linkname` is used to create symbolic link                                                                     |

#### 1.3.1. `alias` list all aliases currently set for your shell account

##### 1.3.1.1. `ls` default scheme color

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

##### 1.3.1.2. `ls` default suffix scheme

| Character | 	File type      |
|-----------|-----------------|
| nothing   | 	regular file   |
| `/`	      | directory       |
| `*`	      | executable file |
| `@`	      | link            |
| `=`	      | socket          |
| `\|`      | 	named pipe     |

##### 1.3.1.3. What is umask?

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

###### 1.3.1.3.1. What is my default umask setting?

Ignore the first character/zero

```console
rishik@rishik-computer:~$ umask -S
u=rwx,g=rwx,o=rx
rishik@rishik-computer:~$ umask
0002
```

##### 1.3.1.4. /dev/null, /dev/random, and /dev/zero

The /dev file system does not just contain files that represent physical devices. Here are three of the most notable
special devices it contains:

1. /dev/null – Discards all data written to it – think of it as a trash can or black hole. If you ever see a comment
   telling you to send complains to /dev/null – that’s a geeky way of saying “throw them in the trash.”
2. /dev/random – Produces randomness using environmental noise. It’s a random number generator you can tap into.
3. /dev/zero – Produces zeros – a constant stream of zeros.

## 1.4. Common Commands

### 1.4.1. Shell

##### 1.4.1.1. Known shells to Linux system

```console
rishik@rishik-computer:~/ws$ cat /etc/shells
# /etc/shells: valid login shells
/bin/sh
/bin/bash
/bin/rbash
/bin/dash
```

##### 1.4.1.2. Which shell am I using?

```console
rishik@rishik-computer:~/ws$ echo $0
/bin/bash
rishik@rishik-computer:~/ws$ echo $SHELL
/bin/bash
```

##### 1.4.1.3. What is the default shell set for each user?

```console
rishik@rishik-computer:~/ws$ cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
...
rishik:x:1000:1000:Rishik,,,:/home/rishik:/bin/bash
```

### 1.4.2. Home

##### 1.4.2.1. What is my home dir?

```console
rishik@rishik-computer:~/ws$ echo $HOME
/home/rishik
```

### 1.4.3. Files

##### 1.4.3.1. Guess the file type!

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

##### 1.4.3.2. Find executable file

`which` searches the user's search `PATH`. Good for troubleshooting `Command not found` problems.

```console
rishik@rishik-computer:~$ which -a java
/usr/bin/java
rishik@rishik-computer:~$ which docker
/usr/bin/docker
```

##### 1.4.3.3. Check if a command is an alias for another command!

```console
rishik@rishik-computer:~$ alias ls
alias ls='ls --color=auto'
rishik@rishik-computer:~$ alias ltr
alias ltr='ls -ltr'
```

##### 1.4.3.4. Find all files whose filename has "readme" in it

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

##### 1.4.3.5. Find all files bigger than 100MB

```console
rishik@rishik-computer:~$ find . -size +100M
./Downloads/ideaIC-2018.3.2.tar.gz
./.config/epiphany/gsb-threats.db
```

##### 1.4.3.6. Find all files whose filename has "readme" in it

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

### 1.4.4. History

- `history` lists all previously ran commands
- `!!` runs the last command
- `!2` runs the command at index 2 from the output of history command

##### 1.4.4.1. Where is my history stored?

```console
rishik@rishik-computer:~$ echo $HISTFILE
/home/rishik/.bash_history
```

### 1.4.5. Users

##### 1.4.5.1. What is my username?

```console
rishik@rishik-computer:~$ echo $USER
rishik
rishik@rishik-computer:~$ whoami
rishik
```

### 1.4.6. Groups

##### 1.4.6.1. What is my default group and other groups I belong to?

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

##### 1.4.6.2. What other groups do I belong to?

:warning: `groups` is deprecated in lieu of `id -Gn`

```console
rishik@rishik-computer:~$ groups rishik
rishik : rishik adm cdrom sudo dip plugdev lpadmin sambashare docker
rishik@rishik-computer:~$ id -Gn rishik
rishik adm cdrom sudo dip plugdev lpadmin sambashare docker
````

##### 1.4.6.3. How can I log in to other groups I belong to? For e.g. docker

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

##### 1.4.6.4. How to change user and group ownership on a file or directory?

- `sudo chown ownerName:groupName [dir | fileName]` - change owner and group of a folder or file
- `sudo chgrp` - change only group permissions
- Both `chown` and `chgrp` can be used to change ownership recursively, using the `-R` option

### 1.4.7. Permissions

Use `chmod` to change access modes for user, group or others.