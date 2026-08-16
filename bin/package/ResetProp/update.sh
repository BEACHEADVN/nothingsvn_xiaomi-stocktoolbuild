work_dir=$(pwd)
source $work_dir/functions.sh
source $work_dir/bin/package/DISABLE_AVB/DISABLEavb.sh

cp -rf $work_dir/bin/package/ResetProp/system_ext/* $work_dir/build/baserom/images/system_ext/

echo "
(type xeutoolbox_exec)
(roletype object_r xeutoolbox_exec)
(typeattributeset file_type (xeutoolbox_exec))
(typeattributeset exec_type (xeutoolbox_exec))
(typeattributeset system_file_type (xeutoolbox_exec))
(allow init xeutoolbox_exec (file (read getattr map execute open execute_no_trans)))
" >> "$work_dir/build/baserom/images/system_ext/etc/selinux/system_ext_sepolicy.cil"


if [ "$vbmeta_disable" = "true" ]; then
    vbmeta_digest=$(sha256sum "$work_dir/build/baserom/images/vbmeta.img" | cut -d ' ' -f1)
    vbmeta_size=$(stat -c%s "$work_dir/build/baserom/images/vbmeta.img")
    echo "
on post-fs-data
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.device_state locked
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.verifiedbootstate green
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.avb_version 1.3
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.hash_alg sha256
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.size $vbmeta_size
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.digest $vbmeta_digest
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.secureboot.lockstate locked
" >> "$work_dir/build/baserom/images/system/system/etc/init/hw/init.rc"
else
echo "
on post-fs-data
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.vbmeta.device_state locked
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.boot.verifiedbootstate green
    exec u:r:init:s0 root root -- /system_ext/xbin/xeutoolbox -n ro.secureboot.lockstate locked
" >> "$work_dir/build/baserom/images/system/system/etc/init/hw/init.rc"
fi