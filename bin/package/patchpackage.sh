work_dir=$(pwd)
source "$work_dir/functions.sh"

mods "Add Package..."
target_dir="$work_dir/bin/package/"

bash "$target_dir/DISABLE_AVB/DISABLEavb.sh" || warn "DISABLE_AVB step failed"
bash "$target_dir/RefreshRate/1hz.sh" || warn "RefreshRate step failed"
bash "$target_dir/NOTIFICATION_FIX/notificationFIX.sh" || warn "Notification FIX step failed"
bash "$target_dir/COREPATCH/update.sh" || warn "CorePatch step failed"
mods "Add Package Done"
