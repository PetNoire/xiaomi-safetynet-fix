#!/system/bin/sh
MODDIR=${0%/*}

exec &> /cache/universal-safetynet-fix.log

echo "*** Universal SafetyNet Fix > Running module" >> /cache/magisk.log

set -x

function background() {
    set +x; while :; do
        [ "$(getprop sys.boot_completed)" == "1" ] && {
            set -x; break; }
        sleep 1
    done

    setprop "persist.usnf.version" "v2 Beta 5"

    [ "$(getprop magisk.version)" == "12.0" ] && {
        MAGISK_VERSION="12"
        HIDELIST_FILE="/magisk/.core/magiskhide/hidelist"; }

    [ "$(magisk -v 2>/dev/null | grep '13..*:MAGISK')" ] && {
        MAGISK_VERSION="13"
        HIDELIST_FILE="/magisk/.core/hidelist"; }

    cp -af "${MODDIR}"/busybox /data/magisk/busybox

    [ "$MAGISK_VERSION" == "12" ] && cp -af "${MODDIR}"/magiskhide /magisk/.core

    get_pid() { $BBX pgrep $1 | $BBX head -n 1; }

    INIT_PID=$(get_pid "init")
    ZYGOTE_PID=$(get_pid "-x zygote")
    [ "$(getprop ro.product.cpu.abi)" ==  "arm64-v8a" ] || [ "$(getprop ro.product.cpu.abi)" ==  "x86_64" ] && ZYGOTE64_PID=$(get_pid "-x zygote64")

    for GET_MNT in "$INIT_PID" "$ZYGOTE_PID" $ZYGOTE64_PID; do
        $BBX readlink /proc/"${GET_MNT}"/ns/mnt || {
            echo "*** Universal SafetyNet Fix > Fail: mount namespace is not supported in your kernel" >> /cache/magisk.log
            exit; }
    done

    ZYGOTE_MNT=$($BBX readlink /proc/"$ZYGOTE_PID"/ns/mnt | $BBX sed 's/.*\[/\Zygote.*/' | $BBX sed 's/\]//')

    [ "$($BBX grep -i ${ZYGOTE_MNT} '/cache/magisk.log' | $BBX head -n 1)" ] && MAGISKHIDE="1" || MAGISKHIDE="0"

    [ "$(getprop persist.usnf.universalhide)" == "1" ] && MAGISKHIDE="0"

### Universal Hide ###
    [ "$MAGISK_VERSION" == "12" ] || [ "$MAGISKHIDE" == "0" ] && {
        echo "*** Universal SafetyNet Fix > Running Universal Hide" >> /cache/magisk.log

        $RESETPROP --delete "init.svc.magisk_pfs"
        $RESETPROP --delete "init.svc.magisk_pfsd"
        $RESETPROP --delete "init.svc.magisk_service"
        $RESETPROP --delete "persist.magisk.hide"
        $RESETPROP --delete "ro.magisk.disable"

        getprop | $BBX grep magisk

        [ "$($BBX getenforce)" == "Permissive" ] && {
            chmod 640 /sys/fs/selinux/enforce
            chmod 440 /sys/fs/selinux/policy; }

        [ -d /sbin_orig ] || {
            echo "*** Universal SafetyNet Fix > Universal Hide: moving and re-linking /sbin binaries" >> /cache/magisk.log
            mount -o rw,remount rootfs /
            mv -f /sbin /sbin_mirror
            mkdir /sbin
            mkdir /sbin_orig
            mount -o ro,remount rootfs /
            mkdir -p /dev/sbin_bind
            chmod 755 /dev/sbin_bind
            ln -s /sbin_mirror/* /dev/sbin_bind
            $BBX chcon -h u:object_r:system_file:s0 /dev/sbin_bind /dev/sbin_bind/*
            mount -o bind /dev/sbin_bind /sbin
            mount -o bind /dev/sbin_bind /sbin_orig; }

        $BBX nsenter -F --target="$INIT_PID" --mount=/proc/"${INIT_PID}"/ns/mnt -- /system/bin/sh -c 'exit' && NSENTER_SH="/system/bin/sh" || NSENTER_SH="$BBX sh"

        $BBX kill -9 $($BBX pgrep com.google.android.gms.unstable)

        logcat -c; logcat -b events -v raw -s am_proc_start | while read LOG_PROC; do
            for HIDELIST in $(cat "$HIDELIST_FILE"); do
                [ "$(echo $LOG_PROC | $BBX grep $HIDELIST | $BBX head -n 1)" ] && APP_PID=$(echo $LOG_PROC | $BBX grep $HIDELIST | $BBX head -n 1 | $BBX awk '{ print substr($0,4) }' | $BBX sed 's/,.*//')
            done
            [ "$APP_PID" ] && {
                if [ "$MAGISKHIDE" == "1" ]; then
                    $BBX nsenter -F --target="$APP_PID" --mount=/proc/"${APP_PID}"/ns/mnt -- $NSENTER_SH -c '
                        BBX="/data/magisk/busybox"
                        DUMMY_SYSTEM=$($BBX find /dev/magisk/dummy/system 2>/dev/null)
                        $BBX umount -l /dev/magisk/mirror/system 2>/dev/null
                        $BBX umount -l $DUMMY_SYSTEM 2>/dev/null'
                else
                    $BBX nsenter -F --target="$APP_PID" --mount=/proc/"${APP_PID}"/ns/mnt -- $NSENTER_SH -c '
                        BBX="/data/magisk/busybox"
                        MNT_DUMMY=$(cd /dev/magisk/mnt/dummy 2>/dev/null && $BBX find system/*)
                        MNT_MIRROR=$(cd /dev/magisk/mnt/mirror 2>/dev/null && $BBX find system/*)
                        MNT_SYSTEM=$(cd /dev/magisk/mnt 2>/dev/null && $BBX find system/*)
                        DUMMY_SYSTEM=$($BBX find /dev/magisk/dummy/system 2>/dev/null)
                        DUMMY=$(cd /dev/magisk/dummy 2>/dev/null && $BBX find system/* | $BBX grep -v "system ")
                        MODULE=$(cd /magisk && $BBX find */system | $BBX sed "s|.*/system/|/system/|")
                        $BBX umount -l $MNT_DUMMY 2>/dev/null
                        $BBX umount -l $MNT_MIRROR 2>/dev/null
                        $BBX umount -l $MNT_SYSTEM 2>/dev/null
                        $BBX umount -l $DUMMY_SYSTEM 2>/dev/null
                        $BBX umount -l $DUMMY 2>/dev/null
                        $BBX umount -l $MODULE 2>/dev/null
                        $BBX umount -l /dev/magisk/mirror/system 2>/dev/null
                        $BBX umount -l /dev/block/loop* 2>/dev/null
                        $BBX umount -l /sbin 2>/dev/null
                        $BBX umount -l /system/xbin 2>/dev/null'
                fi
                unset APP_PID; logcat -c; }
        done; }
}

BBX="/data/magisk/busybox"

RESETPROP="resetprop -v -n"

if [ -f "/sbin/magisk" ]; then RESETPROP="/sbin/magisk $RESETPROP"
elif [ -f "/data/magisk/magisk" ]; then RESETPROP="/data/magisk/magisk $RESETPROP"
elif [ -f "/magisk/.core/bin/resetprop" ]; then RESETPROP="/magisk/.core/bin/$RESETPROP"
elif [ -f "/data/magisk/resetprop" ]; then RESETPROP="/data/magisk/$RESETPROP"; fi

[ "$(getprop persist.usnf.fingerprint)" == 0 ] || {
    [ "$(getprop persist.usnf.fingerprint)" == 1 ] || [ ! "$(getprop persist.usnf.fingerprint)" ] && FINGERPRINT="Xiaomi/sagit/sagit:7.1.1/NMF26X/V8.2.17.0.NCACNEC:user/release-keys" || FINGERPRINT=$(getprop persist.usnf.fingerprint)
    $RESETPROP "ro.build.fingerprint" "$FINGERPRINT"
    $RESETPROP "ro.bootimage.build.fingerprint" "$FINGERPRINT"; }

VERIFYBOOT=$(getprop ro.boot.verifiedbootstate)
FLASHLOCKED=$(getprop ro.boot.flash.locked)
VERITYMODE=$(getprop ro.boot.veritymode)
KNOX1=$(getprop ro.boot.warranty_bit)
KNOX2=$(getprop ro.warranty_bit)
DEBUGGABLE=$(getprop ro.debuggable)
SECURE=$(getprop ro.secure)
BUILD_TYPE=$(getprop ro.build.type)
BUILD_TAGS=$(getprop ro.build.tags)
BUILD_SELINUX=$(getprop ro.build.selinux)
RELOAD_POLICY=$(getprop selinux.reload_policy)

[ ! -z "$VERIFYBOOT" -a "$VERIFYBOOT" != "green" ] && $RESETPROP "ro.boot.verifiedbootstate" "green"
[ ! -z "$FLASHLOCKED" -a "$FLASHLOCKED" != "1" ] && $RESETPROP "ro.boot.flash.locked" "1"
[ ! -z "$VERITYMODE" -a "$VERITYMODE" != "enforcing" ] && $RESETPROP "ro.boot.veritymode" "enforcing"
[ ! -z "$KNOX1" -a "$KNOX1" != "0" ] && $RESETPROP "ro.boot.warranty_bit" "0"
[ ! -z "$KNOX2" -a "$KNOX2" != "0" ] && $RESETPROP "ro.warranty_bit" "0"
[ ! -z "$DEBUGGABLE" -a "$DEBUGGABLE" != "0" ] && $RESETPROP "ro.debuggable" "0"
[ ! -z "$SECURE" -a "$SECURE" != "1" ] && $RESETPROP "ro.secure" "1"
[ ! -z "$BUILD_TYPE" -a "$BUILD_TYPE" != "user" ] && $RESETPROP "ro.build.type" "user"
[ ! -z "$BUILD_TAGS" -a "$BUILD_TAGS" != "release-keys" ] && $RESETPROP "ro.build.tags" "release-keys"
[ ! -z "$BUILD_SELINUX" -a "$BUILD_SELINUX" != "0" ] && $RESETPROP "ro.build.selinux" "0"
[ ! -z "$RELOAD_POLICY" -a "$RELOAD_POLICY" != "1" ] && $RESETPROP "selinux.reload_policy" "1"


background &

exit
