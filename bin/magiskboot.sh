#!/bin/bash

# --- IMPORT FUNCTIONS ---
if [ -f "$(pwd)/functions.sh" ]; then
    source "$(pwd)/functions.sh"
elif [ -f "$(dirname "$0")/../functions.sh" ]; then
    source "$(dirname "$0")/../functions.sh"
fi

# --- CẤU HÌNH CƠ BẢN ---
EXTRACT_DIR="ramdisk_extracted"

# --- HÀM KIỂM TRA MAGISKBOOT ---
check_magiskboot() {
    if command -v magiskboot &> /dev/null; then
        MAGISKBOOT="magiskboot"
    elif [ -f "$(pwd)/magiskboot" ]; then
        MAGISKBOOT="$(pwd)/magiskboot"
    elif [ -f "$(pwd)/bin/magiskboot" ]; then
        MAGISKBOOT="$(pwd)/bin/magiskboot"
    elif [ -f "$(dirname "$0")/magiskboot" ]; then
        MAGISKBOOT="$(dirname "$0")/magiskboot"
    else
        error "magiskboot command not found."
        error "Please add magiskboot to PATH or place it in the same directory as this script."
        return 1
    fi
}

# --- HÀM TÌM ĐƯỜNG DẪN THỰC TẾ CỦA FILE IMG ---
resolve_img_path() {
    local target="$1"
    local work_dir
    work_dir=$(pwd)

    # 1. Nếu là đường dẫn tồn tại trực tiếp
    if [ -f "$target" ]; then
        echo "$(realpath "$target")"
        return 0
    fi

    # 2. Chuẩn hóa tên file (thêm .img nếu chưa có)
    local filename="$target"
    if [[ ! "$filename" =~ \.img$ ]]; then
        filename="${filename}.img"
    fi

    # 3. Tìm trong build/baserom/images/
    if [ -f "$work_dir/build/baserom/images/$filename" ]; then
        echo "$(realpath "$work_dir/build/baserom/images/$filename")"
        return 0
    fi

    # 4. Tìm trong build/baserom/
    if [ -f "$work_dir/build/baserom/$filename" ]; then
        echo "$(realpath "$work_dir/build/baserom/$filename")"
        return 0
    fi

    # 5. Tìm trong thư mục hiện tại với phần mở rộng .img
    if [ -f "$work_dir/$filename" ]; then
        echo "$(realpath "$work_dir/$filename")"
        return 0
    fi

    return 1
}

# --- HÀM UNPACK ---
do_unpack() {
    local full_path="$1"
    local filename=$(basename "$full_path")
    
    unpack "UNPACK START: $filename"
    
    # Sao chép file gốc vào thư mục hiện tại nếu đường dẫn khác nhau
    if [ "$full_path" != "$(pwd)/$filename" ]; then
        cp -f "$full_path" "$(pwd)/$filename"
    fi
    
    "$MAGISKBOOT" unpack "$filename"

    # Nhận diện file CPIO do magiskboot xuất ra
    CPIO_FILE=""
    if [ -f "vendor_ramdisk.cpio" ]; then
        CPIO_FILE="vendor_ramdisk.cpio"
    elif [ -f "ramdisk.cpio" ]; then
        CPIO_FILE="ramdisk.cpio"
    else
        error "CPIO file (vendor_ramdisk.cpio or ramdisk.cpio) not found!"
        return 1
    fi

    # Lưu lại tên file gốc để dùng cho quá trình repack sau này
    echo "$CPIO_FILE" > .cpio_name

    FILE_INFO=$(file -b "$CPIO_FILE")
    CPIO_TARGET="$CPIO_FILE"

    # Xử lý nếu là LZ4
    if echo "$FILE_INFO" | grep -iq "lz4"; then
        unpack "LZ4 compression detected. Decompressing..."
        if ! command -v lz4 &> /dev/null; then
            error "'lz4' command not found. Please install: sudo apt-get install lz4"
            return 1
        fi
        lz4 -d -q "$CPIO_FILE" ramdisk_uncompressed.cpio
        CPIO_TARGET="ramdisk_uncompressed.cpio"
    fi

    # Tạo thư mục và xả nén CPIO
    unpack "Extracting ramdisk into: $EXTRACT_DIR..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    cd "$EXTRACT_DIR" || return 1

    # Bung CPIO (Ưu tiên magiskboot, dự phòng bằng cpio gốc)
    if ! "$MAGISKBOOT" cpio "../$CPIO_TARGET" "extract" &>/dev/null; then
        warn "Magiskboot extract failed. Trying Linux cpio..."
        cpio -idm < "../$CPIO_TARGET" 2>/dev/null
    fi

    cd ..
    # Dọn dẹp file tạm không cần thiết
    [ -f "ramdisk_uncompressed.cpio" ] && rm -f ramdisk_uncompressed.cpio
    
    unpack "UNPACK COMPLETE!"
    unpack "You can now edit files in: $EXTRACT_DIR"

    # Kiểm tra file fstab trong ramdisk
    local fstab_files
    fstab_files=$(find "$EXTRACT_DIR" -type f \( -name "*fstab*" -o -name "*.fstab" \) 2>/dev/null)
    
    if [ -n "$fstab_files" ]; then
        patch "Found fstab in ramdisk. Disabling AVB verify..."
        disable_avb_verify "$EXTRACT_DIR"
    else
        warn "No fstab file found in ramdisk. Repacking immediately..."
        do_repack "$full_path"
        return 0
    fi
}

# --- HÀM REPACK ---
do_repack() {
    local full_path="$1"
    local filename=$(basename "$full_path")
    repack "REPACK START: $filename"

    if [ ! -d "$EXTRACT_DIR" ]; then
        error "Directory '$EXTRACT_DIR' not found."
        return 1
    fi

    # Đảm bảo file gốc tồn tại ở thư mục hiện tại để magiskboot repack
    if [ ! -f "$(pwd)/$filename" ]; then
        if [ -f "$full_path" ]; then
            cp -f "$full_path" "$(pwd)/$filename"
        else
            error "Original file '$filename' not found for repack."
            return 1
        fi
    fi

    # Đọc lại tên file CPIO gốc lúc unpack
    if [ -f ".cpio_name" ]; then
        TARGET_CPIO=$(cat .cpio_name)
    else
        TARGET_CPIO="ramdisk.cpio" # Giá trị mặc định nếu mất file
    fi

    repack "1. Packaging $EXTRACT_DIR directory into raw CPIO..."
    cd "$EXTRACT_DIR" || return 1
    find . | cpio -H newc -o > ../ramdisk_raw.cpio 2>/dev/null
    cd ..

    repack "2. Compressing raw CPIO to LZ4 format (using magiskboot)..."
    rm -f "$TARGET_CPIO"
    "$MAGISKBOOT" compress=lz4 ramdisk_raw.cpio "$TARGET_CPIO"

    if [ ! -f "$TARGET_CPIO" ]; then
        error "LZ4 compression failed!"
        return 1
    fi

    repack "3. Repacking back into $filename structure..."
    "$MAGISKBOOT" repack "$(pwd)/$filename" "$(pwd)/new-$filename"

    repack "4. Cleaning up temporary files..."
    rm -f ramdisk_raw.cpio dtb kernel dtb.* header config ".cpio_name" "$TARGET_CPIO" vendor_ramdisk.cpio ramdisk.cpio

    if [ -f "$(pwd)/new-$filename" ]; then
        repack "REPACK COMPLETE!"
        # Sao chép/di chuyển đè lên file nguồn gốc
        cp -f "$(pwd)/new-$filename" "$full_path"
        repack "New file updated at: $full_path"
        # Cập nhật cả ở thư mục hiện tại
        mv -f "$(pwd)/new-$filename" "$(pwd)/$filename"
    else
        error "Failed to create new-$filename."
    fi
}

# --- MAIN FUNCTION ---
main() {
    if [ "$#" -lt 2 ]; then
        info "Syntax error!"
        info "Usage:"
        info "  Unpack: $0 unpack <image_file.img>"
        info "  Repack: $0 repack <original_image_file.img>"
        info ""
        info "Examples:"
        info "  $0 unpack vendor_boot.img"
        info "  $0 repack vendor_boot.img"
        return 1
    fi

    local ACTION="$1"
    local TARGET_IMG="$2"

    check_magiskboot || return 1

    # Tìm đường dẫn thực tế của target image
    local RESOLVED_IMG
    RESOLVED_IMG=$(resolve_img_path "$TARGET_IMG")
    if [ $? -ne 0 ] || [ ! -f "$RESOLVED_IMG" ]; then
        error "File '$TARGET_IMG' not found in current directory or build/baserom/images/."
        return 1
    fi

    case "$ACTION" in
        unpack)
            do_unpack "$RESOLVED_IMG"
            ;;
        repack)
            do_repack "$RESOLVED_IMG"
            ;;
        *)
            error "Invalid command '$ACTION'. Use 'unpack' or 'repack'."
            return 1
            ;;
    esac
}

main "$@"