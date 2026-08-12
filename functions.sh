#!/bin/bash
WORK_DIR=$(pwd)

mods() {
    if [ "$#" -eq 1 ] ; then
        echo -e [MODS] - $1
    else
        echo "Usage: mods <string>"
    fi
}

info() {
    if [ "$#" -eq 1 ] ; then
        echo -e [INFO] - $1
    else
        echo "Usage: info <string>"
    fi
}

warn() {
    if [ "$#" -eq 1 ] ; then
        echo -e [WARN] - $1
    else
        echo "Usage: warn <string>"
    fi
}

error() {
    if [ "$#" -eq 1 ] ; then
        echo -e [ERROR] - $1
    else
        echo "Usage: error <string>"
    fi
}

unpack() {
    if [ "$#" -eq 1 ] ; then
        echo -e [UNPACK] - $1
    else
        echo "Usage: unpack <string>"
    fi
}

unpack_erofs() {
    if [ "$#" -eq 1 ] ; then
        echo -e [UNPACK - EROFS] - $1
    else
        echo "Usage: unpack_erofs <string>"
    fi
}

unpack_ext() {
    if [ "$#" -eq 1 ] ; then
        echo -e [UNPACK - EXT4] - $1
    else
        echo "Usage: unpack_ext <string>"
    fi
}

repack() {
    if [ "$#" -eq 1 ] ; then
        echo -e [REPACK] - $1
    else
        echo "Usage: repack <string>"
    fi
}

upload() {
    if [ "$#" -eq 1 ] ; then
        echo -e [UPLOADING] - $1
    else
        echo "Usage: upload <string>"
    fi
}

patch() {
    if [ "$#" -eq 1 ] ; then
        echo -e [PATCH] - $1
    else
        echo "Usage: patch <string>"
    fi
}



# --- Shared Utility Functions ---

# Safely read a file's content, returning a fallback value if the file
# does not exist or is empty. Prevents errors from missing .txt configs.
# Usage: value=$(safe_cat "/path/to/file.txt" "default_value")
safe_cat() {
    local file="$1"
    local fallback="${2:-}"
    if [[ -f "$file" ]] && [[ -s "$file" ]]; then
        cat "$file" | tr -d '\r\n'
    else
        echo "$fallback"
    fi
}

# Load all device information from bin/ddevice/*.txt into exported
# environment variables. Call once per script instead of repeating
# cat commands everywhere.
# Usage: load_device_info
load_device_info() {
    local work_dir
    work_dir=$(pwd)
    local dd="$work_dir/bin/ddevice"

    export device_code=$(safe_cat "$dd/device_code.txt")
    export device_f=$(safe_cat "$dd/device_f.txt")
    export base_rom_code=$(safe_cat "$dd/base_rom_code.txt")
    export rom_os=$(safe_cat "$dd/rom_os.txt")
    export os_type=$(safe_cat "$dd/os_type.txt")
    export regionTYPE=$(safe_cat "$dd/device_type.txt")
    export androidVER=$(safe_cat "$dd/androidver.txt")
    export PACK_TYPE=$(safe_cat "$dd/fstype.txt")
    export baserom_type=$(safe_cat "$dd/romtype.txt")
    export sdkLevel=$(safe_cat "$dd/sdkLevel.txt")
}

# Determine build version and status from git branch.
# Sets global variables: polyxver, status
# Usage: get_build_status
get_build_status() {
    local work_dir
    work_dir=$(pwd)
    polyxver=$(safe_cat "$work_dir/Version" "1.0")
    if [[ $(git branch --show-current 2>/dev/null) == "beta" ]]; then
        status="Development"
    else
        status="Official"
    fi
    export polyxver
    export status
}

# Determine OS type string from rom_os variable.
# Returns "MIUI" or "HyperOS" via stdout.
# Usage: os_type=$(get_os_type)
get_os_type() {
    local ros="${rom_os:-$(safe_cat "$(pwd)/bin/ddevice/rom_os.txt")}"
    if [[ "$ros" == "MIUI" ]]; then
        echo "MIUI"
    else
        echo "HyperOS"
    fi
}

# Execute all .sh scripts found within a directory, skipping any
# whose basename (without .sh) matches the skip list.
# Replaces the duplicated find-loop pattern in 5+ insmod/insfile scripts.
# Usage: run_scripts_in_dir "/path/to/dir" "skip_name1" "skip_name2" ...
run_scripts_in_dir() {
    local target_dir="$1"
    shift
    local -a skip_list=("$@")

    if [[ ! -d "$target_dir" ]]; then
        warn "Directory not found: $target_dir"
        return 1
    fi

    while IFS= read -r -d '' script; do
        local base
        base="$(basename "$script" .sh)"

        local should_skip=false
        for skip_name in "${skip_list[@]}"; do
            if [[ "$base" == "$skip_name" ]]; then
                should_skip=true
                break
            fi
        done

        if [[ "$should_skip" == false ]]; then
            info "Executing: $script"
            bash "$script" || warn "Script failed: $script"
        fi
    done < <(find "$target_dir" -type f -name "*.sh" -print0)
}

# Check for required dependencies
exists() {
    command -v "$1" > /dev/null 2>&1
}

abort() {
    yellow "--> Missing $1 ! installing..."
    apt install $1 -y
}

check() {
    for b in "$@"; do
        exists "$b" || abort "$b"
    done
}

# Check for a prop's existence
is_property_exists () {
    if [ $(grep -c "$1" "$2") -ne 0 ] ; then
        return 0
    else
        return 1
    fi
}

disable_avb_verify() {
    fstab_files=$(find "$1" -type f -name "*fstab*")
    info "Disabling avb_verify in files: $fstab_files"
    if [[ -z "$fstab_files" ]]; then
        warn "No fstab files found in $1"
        return
    fi
    for fstab in $fstab_files; do
        if [[ -f $fstab ]]; then
            info "Processing $fstab"
		    sed -i "s/,avb_keys=.*avbpubkey//g" $fstab
            sed -i "s/,avb=vbmeta_system//g" $fstab
		    sed -i "s/,avb=vbmeta_vendor//g" $fstab
            sed -i "s/,avb=vbmeta//g" $fstab
            sed -i "s/,avb//g" $fstab
            sed -i 's/,avb.*system//g' $fstab
            sed -i 's/,avb,/,/g' $fstab
            sed -i 's/,avb=.*a,/,/g' $fstab
            sed -i 's/,avb_keys.*key//g' $fstab
        else
            warn "$fstab not found, please check it manually"
        fi
    done
}

remove_data_encrypt() {
    fstab_files=$(find "$1" -type f -name "*fstab*")
    info "Disabling data enc in files: $fstab_files"
    if [[ -z "$fstab_files" ]]; then
        yellow "No fstab files found in $1"
        return
    fi
    for fstab in $fstab_files; do
        if [[ -f $fstab ]]; then
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
            sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
            sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
            sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
            sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
            sed -i "s/,fileencryption=aes-256-xts//g" $fstab
            sed -i "s/fileencryption/encryptable/g" $fstab
            sed -i "s/,fileencryption=ice//g" $fstab
        else
            yellow "$fstab not found, please check it manually"
        fi
    done
}

extract_partition() {
    part_img=$1
    part_name=$(basename ${part_img})
    target_dir=$2
    if [[ -f ${part_img} ]]; then 
        if [[ $(${WORK_DIR}/bin/Linux/x86_64/gettype -i ${part_img}) == "ext" ]]; then
            pack_type="EXT"
            echo $pack_type > ${WORK_DIR}/bin/ddevice/fstype.txt
            sudo python3 ${WORK_DIR}/bin/imgextractor/imgextractor.py ${part_img} ${target_dir} >/dev/null 2>&1 || { error "Extracting ${part_name} failed."; exit 1; }
            unpack "File ${part_name} extracted."
            rm -rf ${part_img}      
        elif [[ $(${WORK_DIR}/bin/Linux/x86_64/gettype -i ${part_img}) == "erofs" ]]; then
            pack_type="EROFS"
            echo $pack_type > ${WORK_DIR}/bin/ddevice/fstype.txt
            extract.erofs -x -i ${part_img} -o ${target_dir}/${part_name%.*} > /dev/null 2>&1 || { error "Extracting ${part_name} failed." ; exit 1; }
            unpack "File ${part_name} extracted."
            rm -rf ${part_img}
            # Create compatibility symlinks for EROFS double-nested structure
            create_compat_symlinks "${target_dir}/${part_name%.*}"
        else
            error "Unable to handle img, exit."
            exit 1
        fi
    fi    
}

# Create compatibility symlinks after EROFS extraction.
# EROFS extracts partition content into a nested subdirectory
# (e.g., images/product/ contains product/ inside).
# Many scripts reference paths without the nested layer, so we
# create symlinks from the parent to the nested subdirectories.
create_compat_symlinks() {
    local part_dir="$1"
    local part_basename=$(basename "$part_dir")

    # The nested directory (e.g., images/product/product/)
    local nested_dir="${part_dir}/${part_basename}"

    if [[ ! -d "$nested_dir" ]]; then
        return
    fi

    # For non-system partitions (product, vendor, system_ext, odm, mi_ext, etc.)
    # Symlink subdirectories from parent level for compatibility
    # e.g., images/product/etc -> images/product/product/etc
    if [[ "$part_basename" != "system" ]]; then
        for item in "$nested_dir"/*; do
            local item_name=$(basename "$item")
            local link_target="${part_dir}/${item_name}"
            if [[ ! -e "$link_target" ]] && [[ "$item_name" != "$part_basename" ]]; then
                ln -sf "${part_basename}/${item_name}" "$link_target" 2>/dev/null || true
            fi
        done
    else
        # For system partition: content is at images/system/system/system/
        # Scripts expect images/system/system/build.prop etc.
        local sys_inner="${nested_dir}/system"
        if [[ -d "$sys_inner" ]]; then
            for item in "$sys_inner"/*; do
                local item_name=$(basename "$item")
                local link_target="${nested_dir}/${item_name}"
                if [[ ! -e "$link_target" ]]; then
                    ln -sf "system/${item_name}" "$link_target" 2>/dev/null || true
                fi
            done
        fi
    fi
}

setprop_rc() {
    local target_section="$1"    # e.g., "on boot"
    local insert_value="$2"      # e.g., "setprop com.exx.c true"
    local file="$3"              # e.g., "a.rc"

    if [[ ! -f "$file" ]]; then
        echo "Error: file '$file' not found"
        return 1
    fi

    local temp_file="${file}.tmp"
    local matched=0

    > "$temp_file"

    while IFS= read -r line; do
        echo "$line" >> "$temp_file"

        if [[ "$matched" -eq 0 && "$line" == "$target_section" ]]; then
            matched=1
            while IFS= read -r next_line; do
                if [[ "$next_line" =~ ^[[:space:]] ]]; then
                    echo "$next_line" >> "$temp_file"
                else
                    # Insert your new value and break
                    while IFS= read -r value_line; do
                        [[ -n "$value_line" ]] && echo "    $value_line" >> "$temp_file"
                    done <<< "$insert_value"
                    echo "$next_line" >> "$temp_file"
                    break
                fi
            done
        fi
    done < "$file"

    mv "$temp_file" "$file"
}

change_prop() {
    local key="$1"
    local new_value="$2"
    local base_dir="$work_dir/build/baserom/images"

    if [[ -z "$key" || -z "$new_value" ]]; then
        echo "[INFO] - Usage: change_prop <property_key> <new_value>" >&2
        return 1
    fi

    if [[ ! -d "$base_dir" ]]; then
        echo "[ERROR] -  Directory '$base_dir' not found!" >&2
        return 1
    fi

    new_value=$(echo "$new_value" | tr -d '\r\n')
    local escaped_value
    escaped_value=$(printf '%s\n' "$new_value" | sed 's/[\/&#]/\\&/g')

    local found_file=""
    while IFS= read -r -d '' file; do
        if grep -q -E "^$key=" "$file"; then
            sed -i -E "s#^($key)=.*#\1=$escaped_value#" "$file"
            echo "[SYSTEM] - Updated '$key'"
            return 0
        fi
    done < <(find "$base_dir" -type f -name "build.prop" -print0)

    # If key not found in any file, append to the first build.prop
    local first_file
    first_file=$(find "$base_dir" -type f -name "build.prop" | head -n1)

    if [[ -n "$first_file" ]]; then
        echo "$key=$new_value" >> "$first_file"
        echo "[INFO] - Appended '$key=$new_value' to $first_file"
        return 0
    else
        echo "[INFO] - No build.prop files found to update or append." >&2
        return 1
    fi
}


mvsml() {
    local file_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    file_path=$(find "$framework_dir" -type f -name "$file_name")

    if [ -z "$file_path" ]; then
        echo "File $file_name not found in any dex folder within $framework_dir."
        return 1
    fi

    parent_dex_folder=$(dirname "$file_path" | sed "s|$framework_dir/||" | cut -d/ -f1)
    relative_path=$(echo "$file_path" | sed "s|$framework_dir/$parent_dex_folder/||")

    target_path="$target_folder/$relative_path"

    mkdir -p "$(dirname "$target_path")"

    mv "$file_path" "$target_path"

    echo "Moved $file_name to $target_path"
}

mvdir() {
    local folder_name="$1"
    local target_folder="$2"
    local framework_dir="$3"

    folder_path=$(find "$framework_dir" -type d -name "$folder_name")

    if [ -z "$folder_path" ]; then
        echo "Folder $folder_name not found in any dex folder within $framework_dir."
        return 1
    fi

    find "$folder_path" -type f -name "*.smali" | while read -r file_path; do
        parent_dex_folder=$(dirname "$file_path" | sed "s|$framework_dir/||" | cut -d/ -f1)
        relative_path=$(echo "$file_path" | sed "s|$framework_dir/$parent_dex_folder/||")

        target_path="$target_folder/$relative_path"

        mkdir -p "$(dirname "$target_path")"

        mv "$file_path" "$target_path"
    done

    echo "Moved all .smali files from $folder_name to $target_folder"
}