work_dir=$(pwd) 
source $work_dir/functions.sh

# Define ROM infomation
androidVer=$(cat $work_dir/bin/ddevice/androidver.txt)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt)
deviceTYPE=$(cat $work_dir/bin/ddevice/device_type.txt)
MAIN_FOLDER="$work_dir/build/baserom/images"


mods "Fix Fonts"
if [[ $deviceTYPE == "China" ]];then
    if [[ $rom_os == "MIUI" ]];then
        mods "Detect MIUI!Adding..."
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/MIUI/fonts.xml $work_dir/build/baserom/images/system/system/etc/
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/MIUI/*.ttf $work_dir/build/baserom/images/system/system/fonts/
    elif [[ $rom_os == "OS1" ]] && [[ $androidVer -le "13" ]];then
        mods "Detect HyperOS A13!Adding..."
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansLatinVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF_Overlay.ttf
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/*.ttf $work_dir/build/baserom/images/system/system/fonts/
	elif [[ $rom_os == "OS1" ]] && [[ $androidVer -le "14" ]];then
        mods "Detect HyperOS!Adding..."
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansLatinVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF_Overlay.ttf
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/*.ttf $work_dir/build/baserom/images/system/system/fonts/
		cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/A14/*.ttf $work_dir/build/baserom/images/product/fonts/
	elif [[ $rom_os == "OS2" ]] && [[ $androidVer -le "14" ]];then
        mods "Detect HyperOS!Adding..."
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansLatinVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF_Overlay.ttf
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/*.ttf $work_dir/build/baserom/images/system/system/fonts/
		cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/A14/*.ttf $work_dir/build/baserom/images/product/fonts/
	elif [[ $rom_os == "OS2" ]] && [[ $androidVer -le "15" ]];then
        mods "Detect HyperOS!Adding..."
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansLatinVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF_Overlay.ttf
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/*.ttf $work_dir/build/baserom/images/system/system/fonts/
		cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/A14/*.ttf $work_dir/build/baserom/images/product/fonts/
	elif [[ $rom_os == "OS3" ]] && [[ $androidVer -le "16" ]];then
        mods "Detect HyperOS!Adding..."
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansLatinVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF.ttf
		rm $work_dir/build/baserom/images/system/system/fonts/MiSansVF_Overlay.ttf
        cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/*.ttf $work_dir/build/baserom/images/system/system/fonts/
		cp -rf $work_dir/bin/modfile/UpdateFile/Fonts/HyperOS/A14/*.ttf $work_dir/build/baserom/images/product/fonts/
    fi
else
mods "Global ROM!No Adding..."
fi
mods "Done"
# ======================================================================
# ĐOẠN CHÈN THÊM: XỬ LÝ FONT TỰ ĐỘNG CHO TẤT CẢ CÁC NỀN ROM (OS3)
# ======================================================================
FONT_SOURCE="$work_dir/bin/modfile/UpdateFile/Fonts/HyperOS"
SYS_TARGET="$work_dir/build/baserom/images/system/system/fonts"
PROD_TARGET="$work_dir/build/baserom/images/product/fonts"

copy_bauhaus_from_list() {
    local list_file="$1"
    local target_dir="$2"
    local label="$3"
    if [ -f "$list_file" ]; then
        mods "Checking list: $(basename $list_file)"
        while IFS= read -r target_name || [ -n "$target_name" ]; do
            [[ -z "$target_name" || "$target_name" =~ ^# ]] && continue
            target_name=$(echo "$target_name" | tr -d '\r' | xargs)
            if [ -f "$FONT_SOURCE/Bauhaus.ttf" ]; then
                cp -rf "$FONT_SOURCE/Bauhaus.ttf" "$target_dir/$target_name"
                echo " -> [Font $label] Copied Bauhaus.ttf to $target_name"
            fi
        done < "$list_file"
    fi
}

# Thực thi lệnh copy danh sách font bắt buộc cho OS3 (áp dụng mọi vùng miền)
if [[ $rom_os == "OS3" ]] && [[ $androidVer -le "16" ]]; then
    mods "Force processing Font List for OS3..."
    copy_bauhaus_from_list "$FONT_SOURCE/system_fonts.list" "$SYS_TARGET" "System"
    copy_bauhaus_from_list "$FONT_SOURCE/product_fonts.list" "$PROD_TARGET" "Product"
fi
# ======================================================================
