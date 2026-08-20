#xu-ly-device_code
baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh

regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
AndroidVer=$(< $work_dir/build/baserom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
sdkLevel=$(< $work_dir/build/baserom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)

device_code=$(cat $work_dir/bin/ddevice/device_code.txt | tr -d '\r\n')
device_code="${device_code%EEAGlobal}"
device_code="${device_code%EEAGLOBAL}"
device_code="${device_code%Global}"
device_code="${device_code%GLOBAL}"
device_code="${device_code%EEA}"
device_code="${device_code%IN}"
device_code="${device_code%RU}"
device_code="${device_code%TR}"
device_code="${device_code%TW}"
device_code="${device_code%ID}"
device_code="${device_code%JP}"
device_code="${device_code%KR}"

name=$(find $work_dir/build/baserom/images/ -type f -name "build.prop" -exec grep -h "ro.product.odm.marketname=" {} + 2>/dev/null | cut -d '=' -f 2 | head -n 1 | tr -d '\r')
if [ -z "$name" ]; then
    name=$(cat $work_dir/bin/ddevice/device_code.txt)
fi
echo "$name" > $work_dir/bin/ddevice/name_devices.txt
base_rom_code=$(cat $work_dir/bin/ddevice/base_rom_code.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
starxVER=$(cat $work_dir/Version)
systemtype=$(cat $work_dir/bin/ddevice/fstype.txt)

echo "$os_type" > $work_dir/bin/ddevice/os_type.txt
echo "$AndroidVer" > $work_dir/bin/ddevice/androidver.txt
echo "$sdkLevel" > $work_dir/bin/ddevice/sdkLevel.txt


echo "------------------Nothings BuildInfo ---------------------"
echo "- Device Name: $name"
echo "- Codename: $device_code"
echo "- Xiaomi Version: $rom_os"  
echo "- BuildRegion: $regionTYPE"
echo "- Android: $AndroidVer"                                      
echo "- Xiaomi Version: $base_rom_code"                                                                        
echo "- BuildTool Version: $starxVER"
echo "- OS Type: $systemtype"
echo "--------------------------------------------------------"

bash $work_dir/bin/ddevice/genInstall.sh
