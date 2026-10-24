#!/usr/bin/env bash
# shellcheck shell=bash

: "${RYOKU_FULLNAME:=}"
: "${RYOKU_ROOT_MODE:=locked}"
: "${RYOKU_ROOT_PASSWORD_HASH:=}"
: "${RYOKU_EXTRA_USERS_FILE:=}"
: "${RYOKU_HOME_LIMIT_BYTES:=0}"

declare -ga RYOKU_ACCOUNT_NAMES=()
declare -ga RYOKU_ACCOUNT_FULL_NAMES=()
declare -ga RYOKU_ACCOUNT_ROLES=()
declare -ga RYOKU_ACCOUNT_PERMISSIONS=()
declare -ga RYOKU_ACCOUNT_PASSWORD_HASHES=()
declare -ga RYOKU_ACCOUNT_LIMITS=()
declare -gA RYOKU_ACCOUNT_SEEN=()
declare -ga RYOKU_ACCOUNT_GROUPS=()

ryoku_account_validate_username() {
  local name=$1
  [[ $name =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
    || die 'invalid account name: %s' "$name"
  case $name in
    root|nobody|nogroup|bin|daemon|adm|mail|ftp|http|operator|shutdown|halt|sync|games|man|lp|news|uucp|proxy|backup|list|irc|gnats|systemd-*|dbus|polkitd)
      die 'account name is reserved: %s' "$name" ;;
  esac
}

ryoku_account_validate_hash() {
  local name=$1 hash=$2
  [[ -n $hash && $hash != *:* && $hash != *$'\n'* && $hash != *$'\r'* ]] \
    || die 'password hash for %s is empty or malformed' "$name"
  [[ -n ${RYOKU_DRYRUN:-} || $hash =~ ^\$6\$(rounds=[0-9]+\$)?[./0-9A-Za-z]{1,16}\$[./0-9A-Za-z]{86}$ ]] \
    || die 'password hash for %s is not SHA-512 crypt' "$name"
}

ryoku_account_validate_limit() {
  local label=$1 limit=$2
  [[ $limit == 0 || $limit =~ ^[1-9][0-9]*$ ]] \
    || die '%s must be a non-negative byte count' "$label"
  ((${#limit} < 19)) && return 0
  ((${#limit} == 19)) || die '%s exceeds the supported byte count' "$label"
  local high=${limit:0:18} low=${limit:18:1}
  ((high < 922337203685477580 || (high == 922337203685477580 && low <= 7))) \
    || die '%s exceeds the supported byte count' "$label"
}

ryoku_account_validate_permissions() {
  local name=$1 role=$2 permissions=$3 permission
  local -A seen=()
  [[ -n $permissions ]] || return 0
  [[ $permissions != ,* && $permissions != *, && $permissions != *,,* ]] \
    || die 'account %s has an empty permission id' "$name"
  local -a requested=()
  IFS=, read -r -a requested <<<"$permissions"
  for permission in "${requested[@]}"; do
    case $permission in
      admin)
        [[ $role == admin ]] || die 'standard account %s cannot request admin permission' "$name" ;;
      devices|audio|virtualization|containers) ;;
      '') die 'account %s has an empty permission id' "$name" ;;
      *) die 'account %s has unknown permission id: %s' "$name" "$permission" ;;
    esac
    [[ -z ${seen[$permission]+x} ]] \
      || die 'account %s repeats permission id: %s' "$name" "$permission"
    seen[$permission]=1
  done
}

ryoku_account_target_has_name() {
  local wanted=$1 name _
  [[ -r /mnt/etc/passwd ]] || return 1
  while IFS=: read -r name _; do
    [[ $name != "$wanted" ]] || return 0
  done </mnt/etc/passwd
  return 1
}

ryoku_account_target_has_group_name() {
  local wanted=$1 group _
  [[ -r /mnt/etc/group ]] || return 1
  while IFS=: read -r group _; do
    [[ $group != "$wanted" ]] || return 0
  done </mnt/etc/group
  return 1
}

ryoku_account_add_plan() {
  local name=$1 full_name=$2 role=$3 permissions=$4 password_hash=$5 limit=$6
  # Every desktop account needs raw input/uinput and panel-backlight access.
  # Keep them in the typed devices permission so admin and standard users match.
  if [[ ,$permissions, != *,devices,* ]]; then
    permissions=devices${permissions:+,$permissions}
  fi
  ryoku_account_validate_username "$name"
  [[ $full_name != *:* && $full_name != *$'\n'* && $full_name != *$'\r'* && $full_name != *$'\t'* ]] \
    || die 'full name for %s contains an unsupported character' "$name"
  case $role in admin|standard) ;; *) die 'account %s has invalid role: %s' "$name" "$role" ;; esac
  ryoku_account_validate_permissions "$name" "$role" "$permissions"
  ryoku_account_validate_hash "$name" "$password_hash"
  ryoku_account_validate_limit "home limit for $name" "$limit"
  [[ -z ${RYOKU_ACCOUNT_SEEN[$name]+x} ]] || die 'account name is repeated: %s' "$name"
  ryoku_account_target_has_name "$name" && die 'account already exists in target: %s' "$name"
  ryoku_account_target_has_group_name "$name" \
    && die 'account name conflicts with an existing target group: %s' "$name"

  RYOKU_ACCOUNT_SEEN[$name]=1
  RYOKU_ACCOUNT_NAMES+=("$name")
  RYOKU_ACCOUNT_FULL_NAMES+=("$full_name")
  RYOKU_ACCOUNT_ROLES+=("$role")
  RYOKU_ACCOUNT_PERMISSIONS+=("$permissions")
  RYOKU_ACCOUNT_PASSWORD_HASHES+=("$password_hash")
  RYOKU_ACCOUNT_LIMITS+=("$limit")
}

ryoku_accounts_read_extra_file() {
  [[ -n $RYOKU_EXTRA_USERS_FILE ]] || return 0
  [[ -r $RYOKU_EXTRA_USERS_FILE && -f $RYOKU_EXTRA_USERS_FILE ]] \
    || die 'extra-users TSV is not a readable file: %s' "$RYOKU_EXTRA_USERS_FILE"

  local line rest name full_name role permissions password_hash limit tabs line_number=0
  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    [[ -n $line ]] || continue
    rest=$line
    tabs=0
    while [[ $rest == *$'\t'* ]]; do
      rest=${rest#*$'\t'}
      ((tabs += 1))
    done
    ((tabs == 5)) \
      || die 'extra-users TSV line %s must contain exactly six tab-separated fields' "$line_number"

    rest=$line
    name=${rest%%$'\t'*}; rest=${rest#*$'\t'}
    full_name=${rest%%$'\t'*}; rest=${rest#*$'\t'}
    role=${rest%%$'\t'*}; rest=${rest#*$'\t'}
    permissions=${rest%%$'\t'*}; rest=${rest#*$'\t'}
    password_hash=${rest%%$'\t'*}; limit=${rest#*$'\t'}
    [[ -n $limit ]] || limit=$RYOKU_HOME_LIMIT_BYTES
    ryoku_account_add_plan "$name" "$full_name" "$role" "$permissions" "$password_hash" "$limit"
  done <"$RYOKU_EXTRA_USERS_FILE"
}

ryoku_accounts_validate() {
  ryoku_account_validate_limit RYOKU_HOME_LIMIT_BYTES "$RYOKU_HOME_LIMIT_BYTES"
  case $RYOKU_ROOT_MODE in
    locked) ;;
    password) ryoku_account_validate_hash root "$RYOKU_ROOT_PASSWORD_HASH" ;;
    *) die 'RYOKU_ROOT_MODE must be locked or password' ;;
  esac

  RYOKU_ACCOUNT_NAMES=()
  RYOKU_ACCOUNT_FULL_NAMES=()
  RYOKU_ACCOUNT_ROLES=()
  RYOKU_ACCOUNT_PERMISSIONS=()
  RYOKU_ACCOUNT_PASSWORD_HASHES=()
  RYOKU_ACCOUNT_LIMITS=()
  RYOKU_ACCOUNT_SEEN=()
  ryoku_account_add_plan "$RYOKU_USERNAME" "$RYOKU_FULLNAME" admin devices "$RYOKU_PASSWORD_HASH" 0
  ryoku_accounts_read_extra_file
}

ryoku_account_target_group_exists() {
  local wanted=$1 group _
  [[ -n ${RYOKU_DRYRUN:-} ]] && return 0
  [[ -r /mnt/etc/group ]] || return 1
  while IFS=: read -r group _; do
    [[ $group != "$wanted" ]] || return 0
  done </mnt/etc/group
  return 1
}

ryoku_account_add_group() {
  local account=$1 group=$2 existing
  for existing in "${RYOKU_ACCOUNT_GROUPS[@]}"; do
    [[ $existing != "$group" ]] || return 0
  done
  if ryoku_account_target_group_exists "$group"; then
    RYOKU_ACCOUNT_GROUPS+=("$group")
  else
    log 'account %s: target group %s is unavailable; skipping it' "$account" "$group"
  fi
}

ryoku_account_resolve_groups() {
  local account=$1 role=$2 permissions=$3 permission group
  local -a requested=()
  RYOKU_ACCOUNT_GROUPS=()
  if [[ $role == admin ]]; then
    ryoku_account_target_group_exists wheel \
      || die 'target has no wheel group for administrator %s' "$account"
    RYOKU_ACCOUNT_GROUPS+=(wheel)
  fi
  [[ -n $permissions ]] || return 0
  IFS=, read -r -a requested <<<"$permissions"
  for permission in "${requested[@]}"; do
    case $permission in
      admin) ryoku_account_add_group "$account" wheel ;;
      devices)
        ryoku_account_add_group "$account" input
        ryoku_account_add_group "$account" video ;;
      audio) ryoku_account_add_group "$account" audio ;;
      virtualization)
        for group in kvm libvirt; do ryoku_account_add_group "$account" "$group"; done ;;
      containers) ryoku_account_add_group "$account" docker ;;
    esac
  done
}

ryoku_account_create_one() {
  local index=$1 name=${RYOKU_ACCOUNT_NAMES[$1]} full_name=${RYOKU_ACCOUNT_FULL_NAMES[$1]}
  local role=${RYOKU_ACCOUNT_ROLES[$1]} permissions=${RYOKU_ACCOUNT_PERMISSIONS[$1]}
  local password_hash=${RYOKU_ACCOUNT_PASSWORD_HASHES[$1]} limit=${RYOKU_ACCOUNT_LIMITS[$1]}
  local login_shell="/usr/bin/$RYOKU_LOGIN_SHELL" groups_csv
  local -a useradd_args=(-M -U -d "/home/$name" -s "$login_shell")

  ryoku_account_resolve_groups "$name" "$role" "$permissions"
  if ((${#RYOKU_ACCOUNT_GROUPS[@]})); then
    groups_csv=$(IFS=,; printf '%s' "${RYOKU_ACCOUNT_GROUPS[*]}")
    useradd_args+=(-G "$groups_csv")
  else
    groups_csv=none
  fi
  [[ -z $full_name ]] || useradd_args+=(-c "$full_name")
  useradd_args+=("$name")

  log 'account: %s (%s; groups %s; shell %s)' "$name" "$role" "$groups_csv" "$login_shell"
  run btrfs subvolume create "/mnt/home/$name"
  run "$RYOKU_TARGET_CHROOT" /mnt useradd "${useradd_args[@]}"
  run "$RYOKU_TARGET_CHROOT" /mnt cp -a /etc/skel/. "/home/$name/"
  run "$RYOKU_TARGET_CHROOT" /mnt chown -R "$name:$name" "/home/$name"
  run "$RYOKU_TARGET_CHROOT" /mnt chmod 0700 "/home/$name"
  printf '%s:%s\n' "$name" "$password_hash" | run_secret \
    "$RYOKU_TARGET_CHROOT /mnt chpasswd -e (account:hash via stdin)" \
    "$RYOKU_TARGET_CHROOT" /mnt chpasswd -e
  if ((limit > 0)); then
    run btrfs qgroup limit "$limit" "/mnt/home/$name"
  fi
}

ryoku_accounts_root() {
  if [[ $RYOKU_ROOT_MODE == locked ]]; then
    log 'root account: locked (administrators use sudo)'
    run "$RYOKU_TARGET_CHROOT" /mnt passwd -l root
    return 0
  fi
  log 'root account: separate password'
  printf 'root:%s\n' "$RYOKU_ROOT_PASSWORD_HASH" | run_secret \
    "$RYOKU_TARGET_CHROOT /mnt chpasswd -e (root:hash via stdin)" \
    "$RYOKU_TARGET_CHROOT" /mnt chpasswd -e
}

ryoku_accounts_create() {
  local index quota_requested=0 login_shell="/usr/bin/$RYOKU_LOGIN_SHELL"
  ryoku_accounts_validate
  if [[ -z ${RYOKU_DRYRUN:-} && ! -x /mnt$login_shell ]]; then
    die 'login shell %s is missing from the target' "$login_shell"
  fi
  run mkdir -p /mnt/home
  for index in "${!RYOKU_ACCOUNT_LIMITS[@]}"; do
    ((RYOKU_ACCOUNT_LIMITS[index] == 0)) || quota_requested=1
  done
  if ((quota_requested)); then
    log 'home storage: enabling Btrfs quotas'
    run btrfs quota enable /mnt/home
  fi
  for index in "${!RYOKU_ACCOUNT_NAMES[@]}"; do
    ryoku_account_create_one "$index"
  done
  ryoku_accounts_root
}
