WORK_DIR=$(pwd)
source "$WORK_DIR/functions.sh"

APPLIST="$WORK_DIR/bin/ddevice/DEBLOAT/APPLIST.txt"
if [[ ! -f "$APPLIST" ]]; then
    warn "APPLIST.txt not found at: $APPLIST"
    exit 0
fi

debloat_apps=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    debloat_apps+=("$line")
done < "$APPLIST"

if [[ ${#debloat_apps[@]} -eq 0 ]]; then
    info "No apps to debloat (APPLIST.txt is empty)"
    exit 0
fi

find "$WORK_DIR/build/baserom/images/product/" -type d -name "auto-install*" -exec rm -rf {} + 2>/dev/null
find "$WORK_DIR/build/baserom/images/product/" -path "*/app/Updater" -type d -exec rm -rf {} + 2>/dev/null
find "$WORK_DIR/build/baserom/images/product/" -path "*/permissions/cn.google.services.xml" -type f -delete 2>/dev/null

for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory in system, product, and mi_ext directories
    app_dirs=$(find "$WORK_DIR/build/baserom/images/system/" -type d -name "*${debloat_app}*" 2>/dev/null)
    app_dirs2=$(find "$WORK_DIR/build/baserom/images/product/" -type d -name "*${debloat_app}*" 2>/dev/null)
    app_dirs3=$(find "$WORK_DIR/build/baserom/images/mi_ext" -type d -name "*${debloat_app}*" 2>/dev/null)
    # Combine the directories into one list
    all_app_dirs=($app_dirs $app_dirs2 $app_dirs3)

    for app_dir in "${all_app_dirs[@]}"; do
        # Check if the directory exists before removing
        if [[ -d "$app_dir" ]]; then
            info "Removing directory: $app_dir"
            rm -rf "$app_dir"
        fi
    done
done
info "Debloat Done"
