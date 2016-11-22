# live-usb-maker
Create an antiX/MX LiveUSB
### Quick Start

    sudo apt-get update       # if needed
    sudo apt-get install git  # if needed
    git clone https://github.com/BitJam/live-usb-maker
    git clone https://github.com/BitJam/cli-shell-utils
    cd live-usb-maker
    sudo ./live-usb-maker

```
Usage: live-usb-maker [commands]

Create a live-usb from an iso-file, another live-usb, a live-cd/dvd
or a running live system.  You will be prompted for information that
is not supplied in the command line options.

    default:  default "no" to some questions.
     expert:  default "yes" to some questions.
     simple:  skip some questions
        gui:  non-interactive

Uses ext4 as the filesystem for the main live-usb partition and adds
a small fat32 file system for booting via UEFI.

This will destroy any existing information on <usb-device>.  The default
partitioning scheme is GPT.  Use --msdos flag to use msdos partitioning
instead.

  --from="iso-file"    Enter an iso file to use as the source
  --from="clone"       clone a running live system.
  --from=clone=<dir>   clone from a mounted live-usb or iso-file.
  --from=<dev>         copy from a livecd/dvd or live-usb

Options:
  -c --cheat=xxx        Add these cheatcodes to the live-usb
                           Use "off" or "no" to disable cheats menu.
                           Use "on" or "yes"  to show cheat menus without asking

                        Otherwise you will be asked.
  -C --color=<xxx>      Set color scheme to off|low|low2|bw|dark|high
  -e --esp-size=<xx>    Size of ESP (fat) partition in MiB (default 50)
  -E --ext-options=<xx> Use these options when creating the ext4 filesystem

  -f --from=<xxx>       The device, cdrom, or file to make the live-usb from
                        Use "clone" to clone the current live system or use
                        clone=<xxx> to clone another live-usb

  -F --force=<xxx>      Force the options specfied:
                            umount: Allows try to umount all partitions on drive
                               usb: Ignore usb/removable check
                            makefs: Make the ext4 filesystem even if one exists
                              copy: Overwrite ext4 partition even if antiX/ exists
                               all: All of the above (dangerous!)

  -g --gpt              Use gpt partitioning (default) instead of msdos
  -h --help             Show this usage
  -I --ignore-config    Ignore the configuration file
  -L --label=Name       Label ext partition with Name
  -m --msdos            Use msdos partitioning instead of gpt
  -n --no-progess       Don't show progress bar when copying
  -p --pretend          Don't run most commands
     --pause            Wait for user input before exit
  -P --progress         Created /var/log/live-usb-maker.progress progress file
  -q --quiet            Print less
  -R --reset-config     Write a fresh config file with default options
  -s --size=XX          Percent of usb-device to use (default 100)
  -t --target=<xxx>     The device to make into a new live-usb
  -v --verbose          Print more, show commands when run
  -W --write-config     Write a config file preserving current options

Notes:
  - short options stack. Example: -pv is the same as --pretend --verbose
  - options can be intermingled with commands and parameters
  - config file: /root/.config/live-usb-maker/live-usb-maker.conf
  - the config file will be sourced if it exists
  - it will be created if it doesn't exist
```

The Script
----------
The `--verbose` and `--pretend` (which implies `--verbose`) options
were meant to make it very clear what the script is doing.  They also
helped in debugging.  You can control which steps are done with the
commands.  The command `all` does everything.  There are a few
failsafes built in but they can be disabled with `--force` and
`--force-ext`.

Theory
------
We want to use ext4 for our LiveUSBs due to its ruggedness and
features.  But we need a fat32 partition in order to boot via UEFI.
So we use ext4 for the main LiveUSB partition and add a 2nd small
fat32 partition for booting via UEFI.  Legacy booting is done
normally with the ext4 partition.  The fat32 partition is only
used for UEFI booting.

Each partition needs to know about the other one.  We communicate
this with the UUIDs of the partitions.  The fat32 partition needs
to know where the kernel and initrd.gz are.  This is accomplished
with a line like:
```
search --no-floppy --set=root --fs-uuid $EXT4_UUID
```
in the `grub.cfg` file.

The Live system (on the ext4 partition) needs to know about where
the Grub2 UEFI bootloader grub.cfg file is in order to be able
to save boot parameters selected by the user.  This is accomplished
with the `antiX/esp-uuid` file which contains the UUID of the
fat32 ESP partition.

Practice
--------
This program started out as proof-of-concept for passing along
instructions for creating ext4 LiveUSBs with a small fat32 partition
for UEFI booting.  In a nutshell: copy the `efi/` and `boot/`
directories to the fat32 partition and then record UUIDs so the two
partitons know about each other.

Legacy booting is done via the ext4 partition so it has the `boot`
flag set.  UEFI booting is done via the fat32 partition so it has the
`esp` flag set.  The fat32 partition only needs the contents of the
`boot/` directory and the `efi/` (or `EFI/`) directory.  Some of the
contents of boot/ is not needed but this only wastes a few Meg at
most.

One complication is the format of the grub.cfg file changed between
MX-15 and antiX-16.

For antiX-16, to specify the ext4 UUID you should uncomment the
following line and replace `%UUID%` with the UUID of the ext4
partition:
```
# search --no-floppy --set=root --fs-uuid %UUID%
```
For MX-15, you need to add the line.  This script adds it before
the first `menuentry` line.

Optimizing for Size
-------------------
I've tried to optimize the ext4 file system with these options:

```
-m0 -i100000 -J size=32
```

This reduces the number of inodes, the size of the journal and sets
aside no extra space reserved for root.  The number of inodes scales
with the size of the partition.  The idea is that our LiveUSB does not
normally contain many files (compared to an installed system) nor does
it need extra space reserved for root.  Since running out of inodes is
very bad and since adding more inodes does not cost a lot space-wise,
I've tried to err on the side of too many inodes while still keeping
well under the default amount.

The partitioning is aligned on 1 MiB boundaries.

Here are results from using various mkfs.ext4 options.  All sizes are
in Megabytes.  The savings are compared to the default settings.
These tests were all done on an 32-Gig Samsung Fit using the default
50 Meg fat32 partition in addition to the ext4 partition.  The smaller
drivers were simulated using --size=25% and --size=6%.

On 32-Gig:

```
    mkfs.ext4 options         total  avail  savings    (inodes)
    -----------------------   -----  -----  -------    --------
A1  -m0 -N2000   -J size=16   30522  30462     2116      (3824)
B1  -m0 -N10000  -J size=32   30504  30444     2098     (11472)
A2  -m0 -N50000  -J size=32   30493  30433     2087     (53536)
D2  -m0 -N100000 -J size=32   30481  30421     2075    (103248)
E2  -m0 -i800000 -J size=32   30496  30436     2090     (42064)
F2  -m0 -i400000 -J size=32   30487  30427     2081     (80304)
G2  -m0 -i200000 -J size=32   30467  30407     2061    (160608)
H2  -m0 -i100000 -J size=32   30428  30368     2022    (321216)
J2  -m0 -i100000              30332  30272     1926    (321216)
Z2                            29933  28346        0   (1957888)

On 8-Gig (using --size=25%):

    mkfs.ext4 options         total  avail  savings    (inodes)
    ----------------------    -----  -----  -------    --------
E3  -m0 -i800000 -J size=32    7561   7529      592     (10560)
F3  -m0 -i400000 -J size=32    7559   7526      589     (20160)
G3  -m0 -i200000 -J size=32    7554   7521      584     (40320)
H3  -m0 -i100000 -J size=32    7545   7512      575     (79680)
J3  -m0 -i100000               7449   7416      479     (79680)
Z3                             7349   6937        0    (486720)

On 2-Gig (using --size=6%):

    mkfs.ext4 options         total  avail  savings    (inodes)
    ----------------------    -----  -----  -------    --------
E4  -m0 -i800000 -J size=32    1751   1732      116      (2464)
F4  -m0 -i400000 -J size=32    7559   1732      116      (4704)
G4  -m0 -i200000 -J size=32    1749   1730      114      (9408)
H4  -m0 -i100000 -J size=32    1747   1728      112     (18816)
J4  -m0 -i100000               1747   1728      112     (18816)
Z4                             1723   1616        0    (114240)
```
