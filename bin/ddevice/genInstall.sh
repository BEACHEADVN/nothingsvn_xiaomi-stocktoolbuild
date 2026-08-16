#!/bin/bash
work_dir=$(pwd)

# Load device information
device_code=$(cat $work_dir/bin/ddevice/device_code.txt 2>/dev/null)
name=$(cat $work_dir/bin/ddevice/name_devices.txt 2>/dev/null)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt 2>/dev/null)
base_rom_code=$(cat $work_dir/bin/ddevice/base_rom_code.txt 2>/dev/null)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt 2>/dev/null)
AndroidVer=$(cat $work_dir/bin/ddevice/androidver.txt 2>/dev/null)
starxVER=$(cat $work_dir/Version 2>/dev/null)
build_date=$(date +"%Y-%m-%d")

# If device_code is empty, fallback to unknown
if [ -z "$device_code" ]; then
    device_code="unknown"
fi

# Define output file
OUTPUT_FILE="$work_dir/bin/script2flash/${device_code}.install"

# Format ROM Type (e.g. OS3 -> HyperOS)
if [[ "$rom_os" == *"OS"* ]]; then
    rom_type="HyperOS"
else
    rom_type="MIUI"
fi

cat <<EOF > "$OUTPUT_FILE"
{
    "Devices": {
        "Name": "${name:-Unknown}",
        "Brand": "Xiaomi",
        "Codename": "${device_code}"
    },
    "ROM": {
        "Type": "${rom_type}",
        "Version": "${base_rom_code:-Unknown}",
        "Region": "${regionTYPE:-Unknown}",
        "Android": "${AndroidVer:-Unknown}"
    },
    "ToolBuild": {
        "Version": "${starxVER:-1.0}",
        "BuildDate": "${build_date}",
        "Author": "${builder_name:-Nothings}",
        "BuildType": "PureStock-Release"
    },
    "Directory": {
        "Firmware": "images",
        "System": "super"
    }
}
EOF

echo "Generated $OUTPUT_FILE"
