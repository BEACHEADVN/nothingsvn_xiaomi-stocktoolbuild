work_dir=$(pwd)
source "$work_dir/functions.sh"

mods "Starting Update File..."
run_scripts_in_dir "$work_dir/bin/modfile/UpdateFile" "insupdate"
