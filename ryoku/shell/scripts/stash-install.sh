#!/bin/bash
# stash app installer: makes whatever the user dropped in the Ryoku stash
# launchable. an AppImage or self-contained tarball gets a synthesized XDG
# desktop entry under ~/.local; an Arch package is handed to the host package
# seam through pkexec so it installs the normal way and the launcher reads the
# entry the package itself ships.
# on success we drop the source from the stash so it doesn't sit there as a
# duplicate (RYOKU_STASH_KEEP=1 keeps it).
# usage: stash-install.sh [file ...] | list | uninstall <id>
set -u

STASH="${STASH_DIR:-${XDG_DOWNLOAD_DIR:-$HOME/Downloads}/Stash}"
APPSTORE="$HOME/.local/share/ryoku-apps"        # installed payloads
APPDIR="$HOME/.local/share/applications"         # launcher reads .desktop from here
ICONDIR="$HOME/.local/share/icons"
MANIFEST_PREFIX=".stash-"
# successful install copies/extracts/installs the app out of the stash. the
# dropped source is then a pure duplicate; nuke it unless RYOKU_STASH_KEEP=1.
KEEP_SOURCE="${RYOKU_STASH_KEEP:-0}"
mkdir -p "$APPSTORE" "$APPDIR" "$ICONDIR"

LAST_NAME=""
LAST_ID=""
LAST_PAYLOAD=""
LAST_DESKTOP=""
LAST_ICON=""
LAST_DISPLAY_NAME=""

# --- helpers ---------------------------------------------------------------

# slug = name -> filesystem/desktop-id-safe chars.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

valid_id() {
  [ -n "$1" ] && [ "$1" != "." ] && [ "$1" != ".." ] || return 1
  case "$1" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

# Every managed path is a direct child of its owning directory. Resolving the
# parent catches traversal without following a final symlink outside the store.
safe_child() {
  local path="$1" root="$2" parent_real root_real
  parent_real=$(realpath -m -- "$(dirname -- "$path")") || return 1
  root_real=$(realpath -m -- "$root") || return 1
  [ "$parent_real" = "$root_real" ]
}

# cleanup_source FILE: drop a source we just installed, so we don't end up with
# both an install and a leftover stash copy. returns 0 only when it's actually
# gone, so the caller can count it.
cleanup_source() {
  [ "$KEEP_SOURCE" = 1 ] && return 1
  rm -f "$1" 2>/dev/null
  [ ! -e "$1" ]
}

classify() {
  case "$1" in
    *.AppImage|*.appimage) printf 'appimage'; return ;;
    *.pkg.tar.zst|*.pkg.tar.xz|*.pkg.tar.gz|*.pkg.tar) printf 'pacman'; return ;;
    *.flatpak) printf 'flatpak'; return ;;
    *.deb) printf 'deb'; return ;;
    *.rpm) printf 'rpm'; return ;;
  esac
  case "$1" in
    *.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.zst|*.tar.bz2)
      # a renamed Arch package is still a system pkg, not a self-contained app
      # tree; top-level .PKGINFO is the tell. route it to pacman, never to the
      # extract-into-~/.local path that can't produce a working /opt app.
      if is_pacman_pkg "$1"; then printf 'pacman'; else printf 'tarball'; fi ;;
    *) printf 'unknown' ;;
  esac
}

# is_pacman_pkg FILE: true if the archive carries a top-level .PKGINFO. that
# entry is the first member of every pacman package.
is_pacman_pkg() {
  { bsdtar -tf "$1" 2>/dev/null || tar -tf "$1" 2>/dev/null; } | head -n 8 | grep -qxF '.PKGINFO'
}

strip_appimage_ext() {
  case "$1" in
    *.AppImage) printf '%s' "${1%.AppImage}" ;;
    *.appimage) printf '%s' "${1%.appimage}" ;;
    *) printf '%s' "$1" ;;
  esac
}

strip_tar_ext() {
  case "$1" in
    *.tar.gz)  printf '%s' "${1%.tar.gz}" ;;
    *.tgz)     printf '%s' "${1%.tgz}" ;;
    *.tar.xz)  printf '%s' "${1%.tar.xz}" ;;
    *.tar.zst) printf '%s' "${1%.tar.zst}" ;;
    *.tar.bz2) printf '%s' "${1%.tar.bz2}" ;;
    *.tar)     printf '%s' "${1%.tar}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

# desktop_get FILE KEY: first value of an unlocalized KEY from [Desktop Entry].
# restricting to that group avoids picking up Name=/Icon= from Desktop Action groups.
desktop_get() {
  awk -v k="$2" '
    /^\[/ { inentry = ($0 == "[Desktop Entry]"); next }
    inentry {
      eq = index($0, "=")
      if (eq > 0) {
        key = substr($0, 1, eq - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (key == k) { print substr($0, eq + 1); exit }
      }
    }
  ' "$1" 2>/dev/null
}

# exec_field PATH: double-quote the program token if it has whitespace, per
# the desktop entry Exec syntax.
exec_field() {
  case "$1" in
    *[[:space:]]*) printf '"%s"' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

# find_icon_file ROOT ICONVALUE: best-effort find an icon file for ICONVALUE
# under ROOT. prefer scalable SVG, then the highest-res themed PNG.
find_icon_file() {
  local root="$1" icon="$2" bn found=""
  [ -n "$icon" ] || { printf ''; return; }
  [ -f "$icon" ] && { printf '%s' "$icon"; return; }   # value is already a path
  bn=$(basename "$icon"); bn="${bn%.*}"
  found=$(find "$root" -type f -ipath '*/icons/*' -iname "$bn.svg" 2>/dev/null | head -n1)
  [ -z "$found" ] && found=$(find "$root" -type f -ipath '*/icons/*' -iname "$bn.png" 2>/dev/null \
    | awk '{ n=$0; sz=0; if (match(n, /\/[0-9]+x[0-9]+\//)) { s=substr(n, RSTART+1, RLENGTH-2); split(s, a, "x"); sz=a[1] } print sz"\t"n }' \
    | sort -rn | head -n1 | cut -f2-)
  [ -z "$found" ] && found=$(find "$root" -maxdepth 4 -type f \( -iname "$bn.png" -o -iname "$bn.svg" -o -iname "$bn.xpm" \) 2>/dev/null | head -n1)
  printf '%s' "$found"
}

# install_icon SRC APPNAME: copy SRC to the icon dir as APPNAME.<ext>; prints
# the installed path on success.
install_icon() {
  local src="$1" appname="$2" ext
  [ -n "$src" ] && [ -f "$src" ] || { printf ''; return; }
  case "$src" in
    *.png) ext=png ;; *.svg) ext=svg ;; *.xpm) ext=xpm ;;
    *) ext=png ;;   # .DirIcon and friends are conventionally PNG
  esac
  cp -f "$src" "$ICONDIR/$appname.$ext" 2>/dev/null && printf '%s' "$ICONDIR/$appname.$ext"
}

# write_desktop OUT NAME EXEC ICON COMMENT CATEGORIES
write_desktop() {
  local out="$1" nm="$2" ex="$3" ic="$4" cm="$5" cat="$6"
  case "${cat:-}" in
    "") cat="Utility;" ;;
    *\;) ;;
    *) cat="$cat;" ;;   # Categories must be a semicolon-terminated list
  esac
  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Version=1.0\n'
    printf 'Name=%s\n' "$nm"
    [ -n "$cm" ] && printf 'Comment=%s\n' "$cm"
    printf 'Exec=%s\n' "$ex"
    printf 'Icon=%s\n' "${ic:-$nm}"
    printf 'Terminal=false\n'
    printf 'Categories=%s\n' "$cat"
    printf 'X-Ryoku-Stash=true\n'
  } > "$out" || return 1
  LAST_DESKTOP="$out"
  LAST_DISPLAY_NAME="$nm"
}

manifest_value() {
  awk -F '\t' -v wanted="$2" '$1 == wanted { print substr($0, index($0, "\t") + 1); exit }' "$1" 2>/dev/null
}

desktop_exec_target() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  case "$value" in
    \"*) value=${value#\"}; printf '%s' "${value%%\"*}" ;;
    \'*) value=${value#\'}; printf '%s' "${value%%\'*}" ;;
    *) printf '%s' "${value%%[[:space:]]*}" ;;
  esac
}

desktop_points_to_payload() {
  local desktop="$1" payload="$2" key value target
  for key in Exec TryExec; do
    value=$(desktop_get "$desktop" "$key")
    [ -n "$value" ] || continue
    target=$(desktop_exec_target "$value")
    if [ -d "$payload" ]; then
      case "$target" in "$payload"/*) return 0 ;; esac
    elif [ "$target" = "$payload" ]; then
      return 0
    fi
  done
  return 1
}

remove_icon_value() {
  local icon="$1" ext
  [ -n "$icon" ] || return 0
  case "$icon" in
    /*)
      safe_child "$icon" "$ICONDIR" && rm -f -- "$icon"
      ;;
    */*) ;;
    *)
      valid_id "$icon" || return 0
      case "$icon" in
        *.png|*.svg|*.xpm) rm -f -- "$ICONDIR/$icon" ;;
        *) for ext in png svg xpm; do rm -f -- "$ICONDIR/$icon.$ext"; done ;;
      esac
      ;;
  esac
}

remove_desktop() {
  local desktop="$1" icon marker
  safe_child "$desktop" "$APPDIR" || return 0
  icon=$(desktop_get "$desktop" Icon)
  marker=$(desktop_get "$desktop" X-Ryoku-Stash)
  case "$icon" in
    "$ICONDIR"/*) remove_icon_value "$icon" ;;
    *) [ "$marker" = true ] && remove_icon_value "$icon" ;;
  esac
  rm -f -- "$desktop"
}

remove_linked_desktops() {
  local payload="$1" desktop
  shopt -s nullglob
  for desktop in "$APPDIR"/*.desktop; do
    [ -f "$desktop" ] || continue
    desktop_points_to_payload "$desktop" "$payload" && remove_desktop "$desktop"
  done
  shopt -u nullglob
}

has_linked_desktop() {
  local payload="$1" desktop
  shopt -s nullglob
  for desktop in "$APPDIR"/*.desktop; do
    if [ -f "$desktop" ] && desktop_points_to_payload "$desktop" "$payload"; then
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

name_for_payload() {
  local payload="$1" fallback="$2" desktop name
  shopt -s nullglob
  for desktop in "$APPDIR"/*.desktop; do
    [ -f "$desktop" ] || continue
    if desktop_points_to_payload "$desktop" "$payload"; then
      name=$(desktop_get "$desktop" Name)
      if [ -n "$name" ]; then
        shopt -u nullglob
        printf '%s' "$name"
        return
      fi
    fi
  done
  shopt -u nullglob
  printf '%s' "$fallback"
}

write_manifest() {
  local manifest tmp name
  [ -n "$LAST_ID" ] && [ -n "$LAST_PAYLOAD" ] || return 0
  valid_id "$LAST_ID" || return 1
  safe_child "$LAST_PAYLOAD" "$APPSTORE" || return 1
  manifest="$APPSTORE/$MANIFEST_PREFIX$LAST_ID.manifest"
  tmp="$manifest.tmp.$$"
  name="${LAST_DISPLAY_NAME:-$LAST_NAME}"
  name=${name//$'\t'/ }
  name=${name//$'\n'/ }
  {
    printf 'id\t%s\n' "$LAST_ID"
    printf 'name\t%s\n' "$name"
    printf 'payload\t%s\n' "$LAST_PAYLOAD"
    [ -n "$LAST_DESKTOP" ] && printf 'desktop\t%s\n' "$LAST_DESKTOP"
    [ -n "$LAST_ICON" ] && printf 'icon\t%s\n' "$LAST_ICON"
  } > "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$manifest"
}

list_installed() {
  local manifest id name payload item base
  declare -A seen=()
  shopt -s nullglob
  for manifest in "$APPSTORE"/"$MANIFEST_PREFIX"*.manifest; do
    id=$(manifest_value "$manifest" id)
    payload=$(manifest_value "$manifest" payload)
    valid_id "$id" || continue
    safe_child "$payload" "$APPSTORE" || continue
    [ -e "$payload" ] || continue
    name=$(manifest_value "$manifest" name)
    [ -n "$name" ] || name=$(name_for_payload "$payload" "$id")
    name=${name//$'\t'/ }
    name=${name//$'\n'/ }
    printf '%s\t%s\n' "$id" "$name"
    seen["$id"]=1
  done
  for item in "$APPSTORE"/*; do
    if [ -d "$item" ]; then
      id=$(basename -- "$item")
    elif [ -f "$item" ] && [ "${item##*.}" = AppImage ]; then
      base=$(basename -- "$item")
      id=${base%.AppImage}
    else
      continue
    fi
    valid_id "$id" || continue
    [ -n "${seen[$id]:-}" ] && continue
    has_linked_desktop "$item" || continue
    name=$(name_for_payload "$item" "$id")
    name=${name//$'\t'/ }
    name=${name//$'\n'/ }
    printf '%s\t%s\n' "$id" "$name"
    seen["$id"]=1
  done
  shopt -u nullglob
}

uninstall_app() {
  local id="$1" manifest payload="" desktop="" icon="" dir_payload image_payload
  if ! valid_id "$id"; then
    printf 'Invalid Stash app id: %s\n' "$id" >&2
    return 2
  fi

  manifest="$APPSTORE/$MANIFEST_PREFIX$id.manifest"
  if [ -f "$manifest" ]; then
    payload=$(manifest_value "$manifest" payload)
    desktop=$(manifest_value "$manifest" desktop)
    icon=$(manifest_value "$manifest" icon)
  else
    dir_payload="$APPSTORE/$id"
    image_payload="$APPSTORE/$id.AppImage"
    if [ -e "$dir_payload" ] && [ -e "$image_payload" ]; then
      printf 'Ambiguous Stash app id: %s\n' "$id" >&2
      return 1
    elif [ -e "$dir_payload" ]; then
      payload="$dir_payload"
    elif [ -e "$image_payload" ]; then
      payload="$image_payload"
    fi
  fi

  if [ -z "$payload" ] || ! safe_child "$payload" "$APPSTORE"; then
    printf 'Stash app not found: %s\n' "$id" >&2
    return 1
  fi

  remove_linked_desktops "$payload"
  [ -n "$desktop" ] && remove_desktop "$desktop"
  [ -n "$icon" ] && safe_child "$icon" "$ICONDIR" && rm -f -- "$icon"
  rm -rf -- "$payload"
  rm -f -- "$manifest"
  update-desktop-database "$APPDIR" 2>/dev/null || true
  notify-send "Stash" "Uninstalled $id. App data was kept." -i emblem-ok-symbolic
  printf 'OK\t%s\n' "$id"
}

extract_tar() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$src" -C "$dst"
  else
    tar -xf "$src" -C "$dst"   # GNU tar auto-detects gz/xz/zst/bz2
  fi
}

# pick_executable ROOT WANT: an executable named WANT, else the sole executable
# in the tree, else "" (ambiguous).
pick_executable() {
  local root="$1" want="$2" list match
  list=$(find "$root" -type f -perm -u+x ! -iname '*.desktop' 2>/dev/null)
  [ -n "$list" ] || { printf ''; return; }
  match=$(printf '%s\n' "$list" | while IFS= read -r f; do
            [ "$(basename "$f")" = "$want" ] && { printf '%s' "$f"; break; }
          done)
  [ -n "$match" ] && { printf '%s' "$match"; return; }
  [ "$(printf '%s\n' "$list" | wc -l)" -eq 1 ] && printf '%s' "$list"
}

# install_appimage PATH: rip the embedded metadata out of the executable
# AppImage and write a cleaned desktop entry (Exec -> PATH). sets LAST_NAME.
install_appimage() {
  local app="$1" appname out tmp squash="" edesk="" icv="" iconfile="" iconinstalled=""
  local nm="" cm="" cat=""
  appname=$(slug "$(strip_appimage_ext "$(basename "$app")")")
  [ -n "$appname" ] || appname="app"
  out="$APPDIR/$appname.desktop"

  # Type-2 AppImages self-extract via --appimage-extract (no FUSE). it dumps
  # squashfs-root into CWD, so run it inside a throwaway tempdir.
  tmp=$(mktemp -d 2>/dev/null) || tmp=""
  if [ -n "$tmp" ]; then
    if ( cd "$tmp" && "$app" --appimage-extract >/dev/null 2>&1 ) && [ -d "$tmp/squashfs-root" ]; then
      squash="$tmp/squashfs-root"
      edesk=$(find "$squash" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | head -n1)
      if [ -n "$edesk" ]; then
        nm=$(desktop_get "$edesk" Name)
        cm=$(desktop_get "$edesk" Comment)
        cat=$(desktop_get "$edesk" Categories)
        icv=$(desktop_get "$edesk" Icon)
      fi
      iconfile=$(find_icon_file "$squash" "$icv")
      [ -z "$iconfile" ] && [ -f "$squash/.DirIcon" ] && iconfile="$squash/.DirIcon"
      if [ -n "$iconfile" ]; then
        iconinstalled=$(install_icon "$iconfile" "$appname")
        [ -n "$iconinstalled" ] && LAST_ICON="$iconinstalled"
      fi
    fi
    rm -rf "$tmp"
  fi

  # even when extraction fails (squash empty) this still emits the minimum entry.
  write_desktop "$out" "${nm:-$appname}" "$(exec_field "$app") %U" "${iconinstalled:-$appname}" "$cm" "$cat" || return 1
  LAST_NAME="$appname"
}

# install_tar_desktop ROOT DESKTOP FALLBACK: install a .desktop found in an
# extracted tree, rewriting Exec to the absolute binary path inside the tree.
install_tar_desktop() {
  local root="$1" ed="$2" fallback="$3" appname nm cm cat icv oexec
  appname=$(slug "$(basename "$ed" .desktop)")
  [ -n "$appname" ] || appname="$fallback"
  nm=$(desktop_get "$ed" Name)
  cm=$(desktop_get "$ed" Comment)
  cat=$(desktop_get "$ed" Categories)
  icv=$(desktop_get "$ed" Icon)
  oexec=$(desktop_get "$ed" Exec)

  local tok rest="" binbase abs="" execval
  if [ -n "$oexec" ]; then
    tok=${oexec%% *}                                   # program token
    case "$oexec" in *" "*) rest=${oexec#* } ;; esac   # preserve %U/%F and flags
    # an absolute Exec (a .deb/.rpm ships /opt/... or /usr/bin/...) maps straight
    # onto the extracted FHS tree; prefer that exact file over a tree-wide
    # basename find, which can match an unrelated same-named payload file (a
    # cron job etc.) that happens to sort first.
    case "$tok" in
      /*) [ -f "$root$tok" ] && abs="$root$tok" ;;
    esac
    if [ -z "$abs" ]; then
      binbase=$(basename "$tok")
      abs=$(find "$root" -type f -name "$binbase" 2>/dev/null | head -n1)
    fi
    [ -z "$abs" ] && abs="$tok"                        # keep original if not bundled
  else
    abs=$(pick_executable "$root" "$fallback")
  fi
  [ -f "$abs" ] && chmod +x "$abs" 2>/dev/null
  execval="$(exec_field "$abs")"
  [ -n "$rest" ] && execval="$execval $rest"

  local iconfile iconinstalled=""
  iconfile=$(find_icon_file "$root" "$icv")
  if [ -n "$iconfile" ]; then
    iconinstalled=$(install_icon "$iconfile" "$appname")
    [ -n "$iconinstalled" ] && LAST_ICON="$iconinstalled"
  fi

  write_desktop "$APPDIR/$appname.desktop" "${nm:-$fallback}" "$execval" "${iconinstalled:-${icv:-$appname}}" "$cm" "$cat" || return 1
  LAST_NAME="$appname"
}

# dispatch_extracted ROOT NAME FALLBACK: from an already-extracted app tree,
# synthesize a launcher entry. prefer a bundled AppImage, then a shipped
# .desktop (Exec rewritten to the bundled binary), then a lone executable. sets
# LAST_NAME. best-effort: an app that hardcodes /usr or /opt may still need its
# native package, but a relocatable tree becomes launchable here.
dispatch_extracted() {
  local dst="$1" name="$2" rawname="$3" ai ed exe
  ai=$(find "$dst" -type f \( -iname '*.AppImage' -o -iname '*.appimage' \) 2>/dev/null | head -n1)
  if [ -n "$ai" ]; then
    chmod +x "$ai" 2>/dev/null
    install_appimage "$ai"
    return 0
  fi
  ed=$(find "$dst" -type f -name '*.desktop' 2>/dev/null | head -n1)
  if [ -n "$ed" ]; then
    install_tar_desktop "$dst" "$ed" "$rawname"
    return 0
  fi
  exe=$(pick_executable "$dst" "$rawname")
  if [ -n "$exe" ]; then
    chmod +x "$exe" 2>/dev/null
    write_desktop "$APPDIR/$name.desktop" "$rawname" "$(exec_field "$exe")" "$name" "" "Utility;" || return 1
    LAST_NAME="$name"
    return 0
  fi
  return 1
}

# app_store_dir RAWNAME: fresh per-app dir under the app store; echoes its path.
app_store_dir() {
  local name dst
  name=$(slug "$1"); [ -n "$name" ] || name="app"
  dst="$APPSTORE/$name"
  rm -rf "$dst"; mkdir -p "$dst"
  printf '%s' "$dst"
}

# install_tarball SRC: extract a self-contained tarball + synthesize an entry.
install_tarball() {
  local src rawname name dst
  src="$1"
  rawname=$(strip_tar_ext "$(basename "$src")")
  name=$(slug "$rawname"); [ -n "$name" ] || name="app"
  dst=$(app_store_dir "$rawname")
  LAST_ID="$name"
  LAST_PAYLOAD="$dst"
  extract_tar "$src" "$dst" >/dev/null 2>&1 || return 1
  dispatch_extracted "$dst" "$name" "$rawname"
}

# install_deb / install_rpm SRC: pull a foreign package's payload (its usr/ tree)
# and synthesize an entry from it. On Fedora, an RPM is native and goes through
# the host package seam instead. bsdtar reads Debian payloads and foreign RPMs;
# this stays best-effort because a native package or Flatpak is the better route
# for an app that hardcodes system paths.
install_deb() {
  local src rawname name dst tmp data
  src="$1"
  rawname=$(basename "$src" .deb)
  name=$(slug "$rawname"); [ -n "$name" ] || name="app"
  command -v bsdtar >/dev/null 2>&1 || return 1
  dst=$(app_store_dir "$rawname")
  LAST_ID="$name"
  LAST_PAYLOAD="$dst"
  tmp=$(mktemp -d) || return 1
  bsdtar -xf "$src" -C "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
  data=$(find "$tmp" -maxdepth 1 -name 'data.tar*' 2>/dev/null | head -n1)
  [ -n "$data" ] && bsdtar -xf "$data" -C "$dst" >/dev/null 2>&1
  rm -rf "$tmp"
  dispatch_extracted "$dst" "$name" "$rawname"
}

install_rpm() {
  local src rawname name dst status
  src="$1"
  if [ "$(ryoku-host pkgmgr 2>/dev/null)" = dnf ]; then
    command -v pkexec >/dev/null 2>&1 || return 1
    printf '@AUTH\n'
    pkexec ryoku-host pkg install-file "$src" >/dev/null 2>&1
    status=$?
    [ "$status" -eq 0 ] || return 1
    name=$(rpm -qp --qf '%{NAME}' "$src" 2>/dev/null)
    LAST_NAME="${name:-$(slug "$(basename "$src" .rpm)")}"
    return 0
  fi
  rawname=$(basename "$src" .rpm)
  name=$(slug "$rawname"); [ -n "$name" ] || name="app"
  command -v bsdtar >/dev/null 2>&1 || return 1
  dst=$(app_store_dir "$rawname")
  LAST_ID="$name"
  LAST_PAYLOAD="$dst"
  bsdtar -xf "$src" -C "$dst" >/dev/null 2>&1 || return 1
  dispatch_extracted "$dst" "$name" "$rawname"
}

# install_flatpak SRC: install a single-file Flatpak bundle into the user
# installation. ensure the flathub remote first so the bundle's runtime can
# resolve; flatpak then exports the app's desktop entry under
# ~/.local/share/flatpak/exports (on XDG_DATA_DIRS), which the launcher reads.
install_flatpak() {
  local src="$1"
  command -v flatpak >/dev/null 2>&1 || return 1
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  flatpak install --user --noninteractive "$src" >/dev/null 2>&1 || return 1
  LAST_NAME=$(slug "$(basename "$src" .flatpak)")
}

# install_pacman SRC: install an Arch package through the host package seam. the
# stash runs with no tty, so escalate through pkexec (polkit agent raises the GUI
# prompt). the package ships its own /usr/share/applications entry, which the
# launcher reads, so nothing's synthesized here. sets LAST_NAME.
install_pacman() {
  local src="$1" name status
  command -v ryoku-host >/dev/null 2>&1 || return 1
  command -v pkexec >/dev/null 2>&1 || return 1
  # tell the shell to step the control deck aside before the polkit prompt.
  # the deck is a top overlay layer with a keyboard grab, so the prompt would
  # land behind it and could not take the password. shell reads this off stdout.
  printf '@AUTH\n'
  pkexec ryoku-host pkg install-file "$src" >/dev/null 2>&1
  status=$?
  if [ "$status" -eq 5 ]; then
    printf 'Arch packages cannot be installed on this system.\n' >&2
    return 1
  fi
  [ "$status" -eq 0 ] || return 1
  name=$(pacman_pkgname "$src")
  LAST_NAME="${name:-$(slug "$(basename "$src")")}"
}

# pacman_pkgname FILE: the pkgname out of the package's .PKGINFO.
pacman_pkgname() {
  { bsdtar -xOf "$1" .PKGINFO 2>/dev/null || tar -xOf "$1" .PKGINFO 2>/dev/null; } \
    | sed -n 's/^pkgname = //p' | head -n1
}

# install_one FILE: 0 ok, 1 fail, 2 unsupported extension.
install_one() {
  local f="$1" kind appname dest
  LAST_NAME=""
  LAST_ID=""
  LAST_PAYLOAD=""
  LAST_DESKTOP=""
  LAST_ICON=""
  LAST_DISPLAY_NAME=""
  [ -f "$f" ] || return 1
  kind=$(classify "$f")
  case "$kind" in
    appimage)
      appname=$(slug "$(strip_appimage_ext "$(basename "$f")")")
      [ -n "$appname" ] || appname="app"
      dest="$APPSTORE/$appname.AppImage"
      cp -f "$f" "$dest" 2>/dev/null || return 1
      chmod +x "$dest" 2>/dev/null
      LAST_ID="$appname"
      LAST_PAYLOAD="$dest"
      install_appimage "$dest"
      ;;
    tarball)
      install_tarball "$f" || return 1
      ;;
    pacman)
      install_pacman "$f" || return 1
      ;;
    flatpak)
      install_flatpak "$f" || return 1
      ;;
    deb)
      install_deb "$f" || return 1
      ;;
    rpm)
      install_rpm "$f" || return 1
      ;;
    *)
      return 2
      ;;
  esac
}

# --- main ------------------------------------------------------------------

case "${1:-}" in
  list)
    [ "$#" -eq 1 ] || { printf 'Usage: stash-install.sh list\n' >&2; exit 2; }
    list_installed
    exit 0
    ;;
  uninstall)
    [ "$#" -eq 2 ] || { printf 'Usage: stash-install.sh uninstall <id>\n' >&2; exit 2; }
    uninstall_app "$2"
    exit $?
    ;;
esac

# targets: explicit paths (from the in-shell picker) use those; no args falls
# back to every installable file in the stash.
targets=()
case "${1:-}" in
  "")
    shopt -s nullglob
    for f in "$STASH"/*; do
      [ -f "$f" ] || continue
      case "$(classify "$f")" in appimage|tarball|pacman|flatpak|deb|rpm) targets+=("$f") ;; esac
    done
    shopt -u nullglob
    ;;
  *)
    targets=("$@")
    ;;
esac
single=0; [ "${#targets[@]}" -eq 1 ] && single=1

NAMES=()
attempted=0
cleaned=0
if [ "${#targets[@]}" -gt 0 ]; then
  for t in "${targets[@]}"; do
    install_one "$t"; rc=$?
    if [ "$rc" -eq 0 ]; then
      attempted=$((attempted + 1))
      NAMES+=("$LAST_NAME")
      write_manifest || true
      cleanup_source "$t" && cleaned=$((cleaned + 1))
      echo "OK $LAST_NAME"
    elif [ "$rc" -eq 2 ]; then
      # unsupported extension: hard error only when the user named the file
      # explicitly; silently skipped during a whole-stash sweep.
      [ "$single" -eq 1 ] && attempted=$((attempted + 1))
    else
      attempted=$((attempted + 1))
    fi
  done
fi

if [ "${#NAMES[@]}" -gt 0 ]; then
  update-desktop-database "$APPDIR" 2>/dev/null || true
  names_str=$(printf '%s, ' "${NAMES[@]}"); names_str=${names_str%, }
  msg="Installed $names_str"
  [ "$cleaned" -gt 0 ] && msg="$msg, cleared from stash"
  notify-send "Stash" "$msg" -i emblem-ok-symbolic
  echo "$msg"
  exit 0
fi

if [ "$attempted" -gt 0 ]; then
  notify-send "Stash" "Install failed" -i dialog-error
  echo "Install failed" >&2
  exit 1
fi

echo "Nothing to install"
exit 0
