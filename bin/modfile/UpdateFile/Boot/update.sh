work_dir=$(pwd) 
source $work_dir/functions.sh

# Define ROM infomation
androidVer=$(cat $work_dir/bin/ddevice/androidver.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
deviceTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
MAIN_FOLDER="$work_dir/build/baserom/images"

BOOT_SOURCE="$work_dir/bin/modfile/UpdateFile/Boot"
MEDIA_TARGET="$work_dir/build/baserom/images/product/media"

mods "Copy Boot Media"

# Đã loại bỏ điều kiện check deviceTYPE == "China" ở đây
if [[ $rom_os == "MIUI" ]];then
    mods "Detect MIUI! Skipping..."
elif [[ $rom_os == "OS1" ]] && [[ $androidVer -le "13" ]];then
    mods "Detect HyperOS A13! Skipping..."
elif [[ $rom_os == "OS1" ]] && [[ $androidVer -le "14" ]];then
    mods "Detect HyperOS! Skipping..."
elif [[ $rom_os == "OS2" ]] && [[ $androidVer -le "14" ]];then
    mods "Detect HyperOS! Skipping..."
elif [[ $rom_os == "OS2" ]] && [[ $androidVer -le "15" ]];then
    mods "Detect HyperOS! Skipping..."
elif [[ $rom_os == "OS3" ]] && [[ $androidVer -le "16" ]];then
    mods "Detect HyperOS OS3! Copying files..."
    
    # Đảm bảo thư mục đích product/media tồn tại
    mkdir -p "$MEDIA_TARGET"

    # Kiểm tra và copy file bootanimation.zip kèm log
    if [ -f "$BOOT_SOURCE/bootanimation.zip" ]; then
        cp -rf "$BOOT_SOURCE/bootanimation.zip" "$MEDIA_TARGET/"
        echo " -> [Boot Media] Copied bootanimation.zip thành công!"
    else
        echo " -> ❌ Không tìm thấy bootanimation.zip trong thư mục Boot!"
    fi

    # Kiểm tra và copy file bootaudio.mp3 kèm log
    if [ -f "$BOOT_SOURCE/bootaudio.mp3" ]; then
        cp -rf "$BOOT_SOURCE/bootaudio.mp3" "$MEDIA_TARGET/"
        echo " -> [Boot Media] Copied bootaudio.mp3 thành công!"
    else
        echo " -> ❌ Không tìm thấy bootaudio.mp3 trong thư mục Boot!"
    fi
fi

mods "Done"
