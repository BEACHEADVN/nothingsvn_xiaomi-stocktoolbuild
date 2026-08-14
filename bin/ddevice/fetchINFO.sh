baserom="$1"
work_dir=$(pwd)
source "$work_dir/functions.sh"

regionTYPE=$(safe_cat "$work_dir/bin/ddevice/device_type.txt")
device_code=$(safe_cat "$work_dir/bin/ddevice/device_code.txt")
base_rom_code=$(safe_cat "$work_dir/bin/ddevice/base_rom_code.txt")
rom_os=$(safe_cat "$work_dir/bin/ddevice/rom_os.txt")
starxVER=$(safe_cat "$work_dir/Version" "1.0")
systemtype=$(safe_cat "$work_dir/bin/ddevice/fstype.txt")

# Find system build.prop and extract Android version info
system_build_prop=$(find "$work_dir/build/baserom/images/system" -type f -name "build.prop" -path "*/system/build.prop" | head -n 1)
if [[ -z "$system_build_prop" || ! -f "$system_build_prop" ]]; then
    warn "system/build.prop not found, trying fallback search..."
    system_build_prop=$(find "$work_dir/build/baserom/images/system" -type f -name "build.prop" | head -n 1)
fi

if [[ -n "$system_build_prop" && -f "$system_build_prop" ]]; then
    AndroidVer=$(< "$system_build_prop" grep "ro.system.build.version.release" | awk 'NR==1' | cut -d '=' -f 2)
    sdkLevel=$(< "$system_build_prop" grep "ro.system.build.version.sdk" | awk 'NR==1' | cut -d '=' -f 2)
else
    error "No build.prop found! Cannot determine Android version."
    AndroidVer="unknown"
    sdkLevel="unknown"
fi

if [ -f $work_dir/build/baserom/images/vendor/etc/init/hw/init.qcom.rc ]; then
   CHIP="Snapdragon"
   echo "$CHIP" > $work_dir/bin/script2flash/META-INF/A
else
   CHIP="Mediatek"
   echo "$CHIP" > $work_dir/bin/script2flash/META-INF/A
fi 

# Get device market name
name=$(find "$work_dir/build/baserom/images/" -type f -name "build.prop" -exec grep -h "ro.product.odm.marketname=" {} + 2>/dev/null | cut -d '=' -f 2 | head -n 1 | tr -d '\r')
if [ -z "$name" ]; then
    name="$device_code"
fi
echo "$name" > "$work_dir/bin/ddevice/name_devices.txt"

echo "$os_type" > "$work_dir/bin/ddevice/os_type.txt"
echo "$AndroidVer" > "$work_dir/bin/ddevice/androidver.txt"
echo "$sdkLevel" > "$work_dir/bin/ddevice/sdkLevel.txt"

echo "------------------Nothings BuildInfo ---------------------"
echo "- Device Name:\"$name\""
echo "- Codename:\"$device_code\""
echo "- Xiaomi Version:\"$rom_os\""  
echo "- BuildRegion:\"$regionTYPE\""
echo "- Android:\"$AndroidVer\""                                      
echo "- Xiaomi Version:\"$base_rom_code\""                                                                        
echo "- BuildTool Version:\"$starxVER\""
echo "- OS Type:\"$systemtype\""
echo "--------------------------------------------------------"

bash "$work_dir/bin/ddevice/genInstall.sh"