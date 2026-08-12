#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source "$work_dir/functions.sh"

# Validate input
if [[ -z "$baserom" ]]; then
    error "No ROM file or URL specified."
    error "Usage: $0 <rom_file_or_url>"
    exit 1
fi

# Check whether it is a local package or a link
if [ ! -f "${baserom}" ] && [[ "$baserom" == *"http"* ]]; then
    info "Download link detected, starting a download..."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 "${baserom}"
    baserom=$(basename "${baserom}" | sed 's/\?t.*//')
    if [ ! -f "${baserom}" ]; then
        error "Download failed! File not found: ${baserom}"
        exit 1
    fi
    info "BASEROM: ${baserom}"
elif [ -f "${baserom}" ]; then
    info "BASEROM: ${baserom}"
else
    error "BASEROM: Invalid parameter - file not found and not a URL"
    exit 1
fi


# Get ROM Info
if [[ "$baserom" == *"miui_"* ]]; then
    device_code=$(basename "$baserom" | cut -d '_' -f 2)
    base_rom_code=$(echo "$baserom" | awk -F'_' '{print $3}')
elif [[ "$baserom" == *"xiaomi.eu_"* ]]; then
    device_code=$(basename "$baserom" | cut -d '_' -f 3)
    base_rom_code=$(echo "$baserom" | awk -F'_' '{print $3}')
elif echo "$baserom" | grep -qE '.*-ota_full-.*'; then
    device_code=$(basename "$baserom" | cut -d '-' -f 1)
    base_rom_code=$(basename "$baserom" | cut -d '-' -f 3)

    # Transform device_code
    device_code=$(echo "$device_code" | awk -F '_' '{
        if (NF == 1) {
            # If one part, e.g., shennong
            print toupper($1)
        } else if (NF == 2) {
            # If two parts, e.g., tapas_global
            print toupper($1) toupper(substr($2, 1, 1)) substr($2, 2)
        } else if (NF == 3) {
            # If three parts, e.g., houji_tw_global
            printf toupper($1) toupper($2) toupper(substr($3, 1, 1)) substr($3, 2)
        }
    }')
else
    device_code="YourDevice"
    base_rom_code="Unknown"
fi

device_f=$(echo "$device_code" | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' | tr '[:upper:]' '[:lower:]')

# Determine Device Type
# NOTE: Specific region matches (EEAGlobal, TWGlobal, etc.) MUST come
# before the generic "Global" check to avoid false matches.
info "Get Device Type"
if echo "$device_code" | grep -q 'EEAGlobal'; then
    DEVICE_TYPE="EEAGlobal"
elif echo "$device_code" | grep -q 'INGlobal'; then
    DEVICE_TYPE="INGlobal"
elif echo "$device_code" | grep -q 'IDGlobal'; then
    DEVICE_TYPE="IDGlobal"
elif echo "$device_code" | grep -q 'RUGlobal'; then
    DEVICE_TYPE="RUGlobal"
elif echo "$device_code" | grep -q 'JPGlobal'; then
    DEVICE_TYPE="JPGlobal"
elif echo "$device_code" | grep -q 'TWGlobal'; then
    DEVICE_TYPE="TWGlobal"
elif echo "$device_code" | grep -q 'TRGlobal'; then
    DEVICE_TYPE="TRGlobal"
elif echo "$device_code" | grep -q 'Global'; then
    DEVICE_TYPE="Global"
else
    DEVICE_TYPE="China"
fi

#Check MIUI or Hyper
if echo "$base_rom_code" | grep -q "OS1"; then
    ROM_OS="OS1"
elif echo "$base_rom_code" | grep -q "OS2"; then
    ROM_OS="OS2"
elif echo "$base_rom_code" | grep -q "OS3"; then
    ROM_OS="OS3"
elif echo "$base_rom_code" | grep -q "V14"; then
    ROM_OS="MIUI"
elif echo "$base_rom_code" | grep -q "V13"; then
    ROM_OS="MIUI"
else
    error "Unsupported ROM type in: $base_rom_code"
    exit 1
fi

echo "$base_rom_code" > "$work_dir/bin/ddevice/base_rom_code.txt"
echo "$base_rom_code" > "$work_dir/bin/ddevice/os_code.txt"
echo "$device_code" > "$work_dir/bin/ddevice/device_code.txt"
echo "$DEVICE_TYPE" > "$work_dir/bin/ddevice/device_type.txt"
echo "$ROM_OS" > "$work_dir/bin/ddevice/rom_os.txt"

info "Device: $device_code | Region: $DEVICE_TYPE | ROM: $ROM_OS | Version: $base_rom_code"
