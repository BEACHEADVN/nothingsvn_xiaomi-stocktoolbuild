work_dir=$(pwd)
source $work_dir/functions.sh
device_code=$(cat $work_dir/bin/ddevice/device_f.txt)


# Disable AVB For Some Devices
if grep -qw "$device_code" "$work_dir/bin/package/DISABLE_AVB/avb_list.txt"; then
    disable_avb_verify $work_dir/build/baserom/images/vendor >/dev/null 2>&1
    
    # Process vendor_boot.img using magiskboot
    if [ -f "$work_dir/build/baserom/images/vendor_boot.img" ]; then
        mkdir -p "$work_dir/build/baserom/boot"
        cd "$work_dir/build/baserom/boot"
        bash "$work_dir/bin/magiskboot.sh" unpack "$work_dir/build/baserom/images/vendor_boot.img" > /dev/null 2>&1
        if [ -d "ramdisk_extracted/avb" ]; then
            for i in "$work_dir/build/baserom/images"/vbmeta*.img; do
                [ -f "$i" ] && python3 "$work_dir/bin/patch-vbmeta.py" "$i" > /dev/null 2>&1
            done
            info "Patched vbmeta images"
        fi
        bash "$work_dir/bin/magiskboot.sh" repack "$work_dir/build/baserom/images/vendor_boot.img" > /dev/null 2>&1
        cd "$work_dir"
        rm -rf "$work_dir/build/baserom/boot"
        [ -f "$work_dir/build/baserom/images/vendor_boot.img" ] \
            && info "Patched vendor_boot.img" \
            || error "Can not patch vendor_boot.img"
    fi
else
    for img in $(find $work_dir/build/baserom/images -type f -name "vbmeta*.img");do
        python3 $work_dir/bin/patch-vbmeta.py ${img}
    done
fi