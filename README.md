# live-usb-maker
Create an antiX/MX LiveUSB
```
Usage: live-usb-maker [options] <iso-file> <usb-device> [commands]

Create a live-usb on <usb-device> from <iso-file>.  This will destroy
any existing information on <usb-device>.

Use ext4 as the filesystem for the live-usb and add a small fat32 file
system for booting via UEFI.

If one or more commands are given then only perform those commands
Commands:
    all              Do all commands
    partition        Partition the live usb
    make-ext         Create the ext file system
    make-efi         Create the efi file system
    copy-ext         Copy files to live usb ext partition
    copy-efi         Copy files to ESP partition
    uuids            Write UUIDs linking file systems
    install

Options:
  -c --clean        Delete files from each partition before copying
  -f --force        Ignore usb/removeable check (dangerous!)
  -F --force-ext    Force creation of ext4 filesystem even if one exists
  -g --gpt          Use gpt partitioning instead of msdos
  -h --help         Show this usage
  -L --label=Name   Label ext partition with Name
  -p --pretend      Don't run most commands, just show them
  -q --quiet        Print less
  -s --size=XX      Percent of usb-device to use (default 100%)
  -v --verbose      Print more, show commands when run
```
