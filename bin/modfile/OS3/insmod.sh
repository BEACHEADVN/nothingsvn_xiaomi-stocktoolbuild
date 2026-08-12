work_dir=$(pwd)
source "$work_dir/functions.sh"
rom_os=$(safe_cat "$work_dir/bin/ddevice/rom_os.txt")

if [[ "$rom_os" == "OS3" ]]; then
    mods "Starting Apply OS3 Custom Mods File..."
    run_scripts_in_dir "$work_dir/bin/modfile/OS3" "insmod"
fi