work_dir=$(pwd)
source "$work_dir/functions.sh"

# Ensure device_code is available
device_code=$(safe_cat "$work_dir/bin/ddevice/device_code.txt")
if [[ -z "$device_code" ]]; then
    warn "device_code not set, skipping AVB disable"
    exit 0
fi

avb_list="$work_dir/bin/package/DISABLE_AVB/avb_list.txt"

# Disable AVB For Some Devices
if [[ -f "$avb_list" ]] && grep -qw "$device_code" "$avb_list"; then
    info "Device $device_code found in AVB list, disabling AVB verify..."
    disable_avb_verify "$work_dir/build/baserom/images/vendor" >/dev/null 2>&1
    bash "$work_dir/bin/package/DISABLE_AVB/HMATools/start" || warn "HMATools failed"
else
    info "Patching vbmeta images..."
    while IFS= read -r -d '' img; do
        python3 "$work_dir/bin/patch-vbmeta.py" "${img}" || warn "Failed to patch: ${img}"
    done < <(find "$work_dir/build/baserom/images" -type f -name "vbmeta*.img" -print0)
fi