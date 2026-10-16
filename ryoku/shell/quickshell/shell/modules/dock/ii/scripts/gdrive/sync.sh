#!/usr/bin/env bash

set -u
set -o pipefail

REMOTE="ii-gdrive"
base_path=""
bandwidth_kbps=0
keep_versions=0
delete_orphans=false
max_age=""
exclude_file=""
folders=()
generated_exclude_file=""
active_rclone_pid=""
active_parser_pid=""
active_fifo=""
active_folder_log=""

json_escape() {
    local value=${1-}
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    value=${value//$'\r'/ }
    printf '%s' "$value"
}

emit() {
    local type=$1
    local folder=${2-}
    local file=${3-}
    local status=${4-}
    local files=${5:-0}
    local bytes=${6:-0}
    local error=${7-}
    local files_total=${8:-0}
    local bytes_total=${9:-0}
    printf '{"type":"%s","folder":"%s","file":"%s","status":"%s","filesTransferred":%s,"filesTotal":%s,"bytesTransferred":%s,"bytesTotal":%s,"error":"%s"}\n' \
        "$(json_escape "$type")" "$(json_escape "$folder")" "$(json_escape "$file")" \
        "$(json_escape "$status")" "$files" "$files_total" "$bytes" "$bytes_total" "$(json_escape "$error")"
}

usage_error() {
    local message=$1
    emit "complete" "" "" "error" 0 0 "$message"
    exit 2
}

while (($# > 0)); do
    case "$1" in
        --base-path)
            (($# >= 2)) || usage_error "missing value for --base-path"
            base_path=$2
            shift 2
            ;;
        --bandwidth-kbps)
            (($# >= 2)) || usage_error "missing value for --bandwidth-kbps"
            bandwidth_kbps=$2
            shift 2
            ;;
        --keep-versions)
            (($# >= 2)) || usage_error "missing value for --keep-versions"
            keep_versions=$2
            shift 2
            ;;
        --delete-orphans)
            (($# >= 2)) || usage_error "missing value for --delete-orphans"
            delete_orphans=$2
            shift 2
            ;;
        --max-age)
            (($# >= 2)) || usage_error "missing value for --max-age"
            max_age=$2
            shift 2
            ;;
        --exclude-file)
            (($# >= 2)) || usage_error "missing value for --exclude-file"
            exclude_file=$2
            shift 2
            ;;
        --folder)
            (($# >= 2)) || usage_error "missing value for --folder"
            folders+=("$2")
            shift 2
            ;;
        --help|-h)
            printf '%s\n' 'Usage: sync.sh --base-path PATH --bandwidth-kbps N --keep-versions N --delete-orphans true|false --exclude-file FILE --folder PATH [--folder PATH ...]'
            exit 0
            ;;
        *)
            usage_error "unknown argument: $1"
            ;;
    esac
done

if [[ ! "$base_path" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "$base_path" == *..* ]]; then
    usage_error "invalid Drive base path"
fi
if [[ ! "$bandwidth_kbps" =~ ^[0-9]+$ || ! "$keep_versions" =~ ^[0-9]+$ ]]; then
    usage_error "bandwidth and version limits must be non-negative integers"
fi
if [[ "$delete_orphans" != "true" && "$delete_orphans" != "false" ]]; then
    usage_error "delete-orphans must be true or false"
fi
if [[ -n "$exclude_file" && ! -r "$exclude_file" ]]; then
    usage_error "exclude file is not readable"
fi
if ((${#folders[@]} == 0)); then
    usage_error "at least one backup folder is required"
fi
if ! command -v rclone >/dev/null 2>&1; then
    usage_error "rclone is not installed or is not in PATH"
fi

if [[ -z "$exclude_file" && -n "${GDRIVE_EXCLUDE_PATTERNS:-}" ]]; then
    generated_exclude_file=$(mktemp)
    printf '%s\n' "$GDRIVE_EXCLUDE_PATTERNS" > "$generated_exclude_file"
    exclude_file="$generated_exclude_file"
fi
cleanup() {
    if [[ -n "$generated_exclude_file" ]]; then
        rm -f -- "$generated_exclude_file"
    fi
    if [[ -n "$active_fifo" ]]; then
        rm -f -- "$active_fifo"
    fi
    if [[ -n "$active_folder_log" ]]; then
        rm -f -- "$active_folder_log"
    fi
}
terminate_sync() {
    local exit_code=$1
    trap - HUP INT TERM
    if [[ -n "$active_rclone_pid" ]]; then
        kill -TERM "$active_rclone_pid" 2>/dev/null || true
    fi
    if [[ -n "$active_parser_pid" ]]; then
        kill -TERM "$active_parser_pid" 2>/dev/null || true
    fi
    if [[ -n "$active_rclone_pid" ]]; then
        wait "$active_rclone_pid" 2>/dev/null || true
    fi
    if [[ -n "$active_parser_pid" ]]; then
        wait "$active_parser_pid" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT
trap 'terminate_sync 129' HUP
trap 'terminate_sync 130' INT
trap 'terminate_sync 143' TERM

for folder in "${folders[@]}"; do
    if [[ ! -d "$folder" ]]; then
        usage_error "backup folder is not a directory: $folder"
    fi
done

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/illogical-impulse/gdrive"
if ! mkdir -p -- "$state_root"; then
    usage_error "could not create the gdrive state directory"
fi
run_stamp=$(date +%Y%m%d-%H%M%S)
log_path="$state_root/sync-$run_stamp.log"
: > "$log_path" || usage_error "could not create sync log"

total_files=0
total_bytes=0
any_failed=false
first_failure=""

prune_versions() {
    local folder_name=$1
    local version_root="${REMOTE}:${base_path}/.versions"
    local version_listing=""
    local -a version_dirs=()
    local old_dir

    ((keep_versions > 0)) || return 0
    emit "maintenance" "$folder_name" "" "running" 0 0 "Finalizing remote version cleanup"
    if ! version_listing=$(timeout --foreground 20s rclone lsf --dirs-only --max-depth 1 "$version_root" 2>/dev/null); then
        emit "warning" "$folder_name" "" "warning" 0 0 "Remote version cleanup timed out; backup files were kept"
        return 0
    fi
    mapfile -t version_dirs < <(printf '%s\n' "$version_listing" | sed 's:/$::' | sort -r)
    if ((${#version_dirs[@]} <= keep_versions)); then
        return 0
    fi
    for old_dir in "${version_dirs[@]:keep_versions}"; do
        [[ -n "$old_dir" ]] || continue
        if ! timeout --foreground 20s rclone purge "${version_root}/${old_dir}/${folder_name}" >/dev/null 2>&1; then
            emit "warning" "$folder_name" "" "warning" 0 0 "Could not prune an old backup version"
        fi
    done
}

collect_folder_summary() {
    local folder=$1
    local summary_json=""
    local -a size_command=(rclone size "$folder" --json)

    if [[ -n "$exclude_file" ]]; then
        size_command+=(--exclude-from "$exclude_file")
    fi
    if ! summary_json=$(timeout --foreground 30s "${size_command[@]}" 2>/dev/null); then
        return 0
    fi
    if [[ "$summary_json" =~ \"count\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        folder_files=${BASH_REMATCH[1]}
        folder_total_files=${BASH_REMATCH[1]}
    fi
    if [[ "$summary_json" =~ \"bytes\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
        folder_bytes=${BASH_REMATCH[1]}
    fi
}

for folder in "${folders[@]}"; do
    normalized_folder=${folder%/}
    folder_name=${normalized_folder##*/}
    [[ -n "$folder_name" ]] || folder_name="root"
    destination="${REMOTE}:${base_path}/${folder_name}"
    emit "start" "$folder_name"

    command=(rclone)
    if [[ "$delete_orphans" == "true" ]]; then
        command+=(sync)
    else
        command+=(copy)
    fi
    # `--progress` redraws on nearly every discovered file even when stdout is
    # a pipe, flooding Quickshell with thousands of events in a few seconds.
    # Regular NOTICE-level stats honor the 2s cadence and still include the
    # final 100% line, keeping the UI responsive and accurately informed.
    command+=("$folder" "$destination" --stats-one-line-date --stats 2s --stats-log-level NOTICE)
    if [[ -n "$exclude_file" ]]; then
        command+=(--exclude-from "$exclude_file")
    fi
    if ((bandwidth_kbps > 0)); then
        command+=(--bwlimit "${bandwidth_kbps}k")
    fi
    if ((keep_versions > 0)); then
        command+=(--backup-dir "${REMOTE}:${base_path}/.versions/${run_stamp}/${folder_name}")
    fi
    if [[ -n "$max_age" ]]; then
        command+=(--max-age "$max_age")
    fi

    folder_files=0
    folder_total_files=0
    folder_bytes=0
    folder_log=$(mktemp)
    active_folder_log="$folder_log"
    active_fifo=$(mktemp)
    rm -f -- "$active_fifo"
    if ! mkfifo -- "$active_fifo"; then
        usage_error "could not create progress pipe"
    fi
    set +e
    tr '\r' '\n' < "$active_fifo" | while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line//$'\r'/}
        [[ -n "$line" ]] || continue
        printf '%s\n' "$line" >> "$log_path"
        printf '%s\n' "$line" >> "$folder_log"
        if [[ "$line" =~ [0-9]{1,3}% ]] || [[ "$line" == *"ETA "* ]] || [[ "$line" == Transferred:* || "$line" == Checks:* || "$line" == Errors:* || "$line" == Elapsed* ]]; then
            if [[ "$line" =~ \(xfr\#([0-9]+)/([0-9]+)\) ]]; then
                folder_files=${BASH_REMATCH[1]}
                folder_total_files=${BASH_REMATCH[2]}
            elif [[ "$line" =~ Transferred:[[:space:]]*([0-9]+)[[:space:]]*/ ]]; then
                folder_files=${BASH_REMATCH[1]}
            fi
            emit "stats" "$folder_name" "" "running" "$folder_files" "$folder_bytes" "$line" "$folder_total_files" 0
        elif [[ ! "$line" =~ (NOTICE|INFO|ERROR):[[:space:]] ]]; then
            emit "file" "$folder_name" "$line" "running" "$folder_files" "$folder_bytes"
        fi
    done &
    active_parser_pid=$!
    "${command[@]}" > "$active_fifo" 2>&1 &
    active_rclone_pid=$!
    wait "$active_rclone_pid"
    command_status=$?
    active_rclone_pid=""
    wait "$active_parser_pid" || true
    active_parser_pid=""
    set -u
    rm -f -- "$active_fifo"
    active_fifo=""

    last_transfer=$(grep -E '(\(xfr#[0-9]+/[0-9]+\)|^Transferred:)' "$folder_log" | tail -n 1 || true)
    if [[ "$last_transfer" =~ \(xfr\#([0-9]+)/([0-9]+)\) ]]; then
        folder_files=${BASH_REMATCH[1]}
        folder_total_files=${BASH_REMATCH[2]}
    elif [[ "$last_transfer" =~ Transferred:[[:space:]]*([0-9]+)[[:space:]]*/ ]]; then
        folder_files=${BASH_REMATCH[1]}
    fi
    if ((command_status == 0)); then
        folder_status="success"
        emit "maintenance" "$folder_name" "" "running" "$folder_files" "$folder_bytes" "Collecting backup summary" "$folder_total_files" 0
        collect_folder_summary "$folder"
    else
        folder_status="error"
        any_failed=true
        rclone_error=$(grep -E '(CRITICAL|ERROR|NOTICE):[[:space:]]' "$folder_log" | tail -n 1 || true)
        if [[ -z "$rclone_error" ]]; then
            rclone_error=$(tail -n 1 "$folder_log" || true)
        fi
        rclone_error=$(printf '%s' "$rclone_error" | sed -E 's/^[0-9]{4}[/.-][0-9]{2}[/.-][0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+//; s/^(CRITICAL|ERROR|NOTICE):[[:space:]]*//')
        [[ -n "$rclone_error" ]] || rclone_error="rclone exited with status $command_status"
        if [[ -z "$first_failure" ]]; then
            first_failure="$folder_name: $rclone_error"
        fi
    fi
    rm -f -- "$folder_log"
    active_folder_log=""
    total_files=$((total_files + folder_files))
    total_bytes=$((total_bytes + folder_bytes))
    if ((command_status == 0)); then
        prune_versions "$folder_name"
        emit "done" "$folder_name" "" "$folder_status" "$folder_files" "$folder_bytes" "" "$folder_total_files" 0
    else
        emit "done" "$folder_name" "" "$folder_status" "$folder_files" "$folder_bytes" "$rclone_error" "$folder_total_files" 0
    fi
done

if [[ "$any_failed" == "true" ]]; then
    emit "complete" "" "" "error" "$total_files" "$total_bytes" "${first_failure:-one or more backup folders failed}"
    exit 1
fi
emit "complete" "" "" "success" "$total_files" "$total_bytes"
exit 0
