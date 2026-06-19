work_dir=$(pwd) 
source $work_dir/functions.sh
product="$work_dir/build/baserom/images/product"
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)

if [[ $regionTYPE == *"Global"* ]]; then
    if [[ $rom_os == "OS3" ]]; then
        mods "Disable POCO Theme OS3"
        rm -rf "$product/media/theme"
        cp -rf "$work_dir/bin/modfile/UpdateFile/Global_POCO2Xiaomi-Icon/OS3/theme" "$product/media"
        mods "Done"
    elif [[ $rom_os == "OS2" || $rom_os == "OS1" ]]; then
        mods "Disable POCO Theme OS2 Below"
        rm -rf "$product/media/theme"
        cp -rf "$work_dir/bin/modfile/UpdateFile/Global_POCO2Xiaomi-Icon/OS2BL/theme" "$product/media"
        mods "Done"
    fi
fi