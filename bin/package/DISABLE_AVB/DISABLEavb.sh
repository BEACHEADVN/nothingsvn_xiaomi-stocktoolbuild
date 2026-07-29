work_dir=$(pwd)
source $work_dir/functions.sh
device_code=$(cat $work_dir/bin/ddevice/device_f.txt)


# Disable AVB For Some Devices
if grep -qw "$device_code" "$work_dir/bin/package/DISABLE_AVB/avb_list.txt"; then
    disable_avb_verify $work_dir/build/baserom/images/vendor >/dev/null 2>&1
    
    # Process vendor_boot.img using vbpatcher.py
    if [ -f "$work_dir/build/baserom/images/vendor_boot.img" ]; then
        # Tạo thư mục output trước để tránh lỗi unpack
        mkdir -p "$work_dir/build/baserom/boot"

        python3 "$work_dir/bin/vbpatcher.py" unpack -i "$work_dir/build/baserom/images/vendor_boot.img" -o "$work_dir/build/baserom/boot"
        
        if [ -d "$work_dir/build/baserom/boot/ramdisk_root/avb" ]; then
            for i in "$work_dir/build/baserom/images"/vbmeta*.img; do
                python3 "$work_dir/bin/patch-vbmeta.py" "$i" > /dev/null 2>&1
            done
            vbmeta_digest=$(sha256sum "$work_dir/build/baserom/images/vbmeta.img" | cut -d ' ' -f1)
            vbmeta_size=$(stat -c%s "$work_dir/build/baserom/images/vbmeta.img")
            jq ".cmdline = \"androidboot.vbmeta.digest=$vbmeta_digest androidboot.vbmeta.avb_version=1.3 androidboot.vbmeta.size=$vbmeta_size androidboot.vbmeta.hash_alg=sha256 \" + .cmdline" \
                "$work_dir/build/baserom/boot/config.json" > "$work_dir/build/baserom/boot/config.bak" && mv -f "$work_dir/build/baserom/boot/config.bak" "$work_dir/build/baserom/boot/config.json"
            info "Patched vbmeta images"
        fi

        # Chỉ thực hiện find nếu thư mục boot tồn tại
        if [ -d "$work_dir/build/baserom/boot" ]; then
            find "$work_dir/build/baserom/boot/" -type f -name "*fstab*" | while read -r fstab; do
                sed -i "s/,avb_keys=.*avbpubkey//g" "$fstab"
                sed -i "s/,avb=vbmeta_system//g" "$fstab"
                sed -i "s/,avb=vbmeta_vendor//g" "$fstab"
                sed -i "s/,avb=vbmeta//g" "$fstab"
                sed -i "s/,avb//g" "$fstab"
                sed -i 's/,avb.*system//g' "$fstab"
                sed -i 's/,avb,/,/g' "$fstab"
                sed -i 's/,avb=.*a,/,/g' "$fstab"
                sed -i 's/,avb_keys.*key//g' "$fstab"
            done
            python3 "$work_dir/bin/vbpatcher.py" repack -c "$work_dir/build/baserom/boot/config.json" -o "$work_dir/build/baserom/images/vendor_boot.img" > /dev/null 2>&1 && rm -rf "$work_dir/build/baserom/boot"
        fi

        [ -f "$work_dir/build/baserom/images/vendor_boot.img" ] \
            && info "Patched vendor_boot.img" \
            || error "Can not patch vendor_boot.img"
    fi
else
    for img in $(find $work_dir/build/baserom/images -type f -name "vbmeta*.img");do
        python3 $work_dir/bin/patch-vbmeta.py ${img}
    done
fi
