work_dir=$(pwd)
source "$work_dir/functions.sh"

ANDROID_DEVICE=$(safe_cat "$work_dir/bin/ddevice/device_f.txt")
rom_os=$(safe_cat "$work_dir/bin/ddevice/rom_os.txt")
regionTYPE=$(safe_cat "$work_dir/bin/ddevice/device_type.txt")

str='<item>120</item>'
str1='<item>90</item>'
str2='<item>1</item>'
checkfps='<bool name="support_smart_fps">true</bool>'

# Use a proper loop to handle XML files instead of unsafe glob in variable
shopt -s nullglob
xml_files=("$work_dir/build/baserom/images/product/etc/device_features/"*.xml)
shopt -u nullglob

if [[ ${#xml_files[@]} -eq 0 ]]; then
    info "No device_features XML files found, skipping RefreshRate patch"
    exit 0
fi

for gfFile in "${xml_files[@]}"; do
    info "Processing RefreshRate for: $(basename "$gfFile")"

    if ! grep -qc "$str" "$gfFile"; then
        sed "/\<item\>144<\/item\>/a\\        <item>120<\/item>" "$gfFile" > "${gfFile}.new"
        mv "${gfFile}.new" "$gfFile"
        info "Added 120hz to $(basename "$gfFile")"
    fi

    if ! grep -qc "$str1" "$gfFile"; then
        sed "/\<item\>120<\/item\>/a\\        <item>90<\/item>" "$gfFile" > "${gfFile}.new"
        mv "${gfFile}.new" "$gfFile"
        info "Added 90hz to $(basename "$gfFile")"
    fi

    if ! grep -qc "$str2" "$gfFile"; then
        sed "/\<item\>60<\/item\>/a\\        <item>1<\/item>" "$gfFile" > "${gfFile}.new"
        mv "${gfFile}.new" "$gfFile"
        info "Added 1hz to $(basename "$gfFile")"
    fi

    if ! grep -qc "$checkfps" "$gfFile"; then
        sed "/\<integer name=\"defaultFps\"\>60<\/integer\>/a\\    <bool name=\"support_smart_fps\">true<\/bool>\\\<integer name=\"smart_fps_value\">120<\/integer>" "$gfFile" > "${gfFile}.new"
        mv "${gfFile}.new" "$gfFile"
        info "Added SmartFPS to $(basename "$gfFile")"
    fi
done