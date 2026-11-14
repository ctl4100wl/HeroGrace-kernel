properties() { '
kernel.string=HeroGrace BPF G930X for EylemROM G930X (SELinux Enforcing, KSUN 33355)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=1
device.name1=herolte
device.name2=heroltexx
device.name3=herolteskt
device.name4=heroltektt
device.name5=heroltelgt
'; }

BLOCK=/dev/block/platform/155a0000.ufs/by-name/BOOT
IS_SLOT_DEVICE=0
PATCH_VBMETA_FLAG=0
NO_MAGISK_CHECK=1

. tools/ak3-core.sh
loader=$(getprop ro.bootloader)
[ -n "$loader" ] || loader=$(sed -n 's/.*androidboot.bootloader=\([^ ]*\).*/\1/p' /proc/cmdline)
case "$loader" in
    G930F*|G930S*|G930L*|G930K*) ;;
    *) abort "Unsupported bootloader: $loader" ;;
esac

split_boot
[ -s "$SPLITIMG/extra" ] || abort 'Samsung DT table missing from the installed boot image.'
strings "$SPLITIMG/kernel" | grep -Eq 'Linux version 3\.18\.140-HeroGrace(Kernel-V1\.0-G930X|\-G930X-Eylem)' ||
    abort 'Install the G930X EylemROM 1.0 boot image first.'
magiskboot cpio "$SPLITIMG/ramdisk.cpio" test
[ "$?" -eq 0 ] || abort 'Install the original EylemROM boot image before flashing.'
[ -f "$SPLITIMG/header" ] || abort 'Missing boot image header.'
patch_cmdline 'androidboot.selinux=' 'androidboot.selinux=enforcing'
grep -Eq '^cmdline=(.* )?androidboot\.selinux=enforcing( |$)' "$SPLITIMG/header" ||
    abort 'Could not set SELinux enforcing in the boot command line.'
ui_print 'Keeping the installed EylemROM ramdisk and Samsung DT table. Replacing the raw kernel only.'
flash_boot
