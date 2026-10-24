# shellcheck shell=sh

# A herdr, tmux or zellij server keeps the environment of the login that started
# it. Started over SSH or from a TTY before the desktop, every pane it opens has
# no display, so paste and every clipboard tool inside fail. A new pane borrows
# the running desktop's display from the user manager (Turnstile's env dir on
# Void); the fish twin is fish/conf.d/desktop-display.fish.

case $- in
  *i*) ;;
  *) return ;;
esac
[ -n "${HERDR_ENV:-}${TMUX:-}${ZELLIJ:-}" ] || return

_ryoku_desktop_value() {
  case $_ryoku_desktop_source in
    manager)
      while IFS= read -r _ryoku_desktop_line; do
        case $_ryoku_desktop_line in
          "$1="*)
            printf '%s' "${_ryoku_desktop_line#*=}"
            return 0
            ;;
        esac
      done <<EOF
$_ryoku_desktop_manager
EOF
      ;;
    envdir)
      if [ -r "$_ryoku_desktop_envdir/$1" ]; then
        cat -- "$_ryoku_desktop_envdir/$1"
        return 0
      fi
      ;;
  esac
  return 1
}

_ryoku_desktop_valid_name() {
  case $1 in
    [A-Za-z_]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!A-Za-z0-9_]*) return 1 ;;
  esac
}

_ryoku_desktop_clear_handles() {
  while IFS= read -r _ryoku_desktop_name; do
    _ryoku_desktop_valid_name "$_ryoku_desktop_name" || continue
    case $_ryoku_desktop_name in
      WAYLAND_DISPLAY|DISPLAY) continue ;;
    esac
    unset "$_ryoku_desktop_name"
  done <<EOF
$_ryoku_desktop_handles
EOF
}

_ryoku_desktop_heal() {
  _ryoku_desktop_runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  _ryoku_desktop_had_wayland=
  if [ "${WAYLAND_DISPLAY+x}" = x ]; then
    _ryoku_desktop_had_wayland=1
    case $WAYLAND_DISPLAY in
      /*) _ryoku_desktop_current_socket=$WAYLAND_DISPLAY ;;
      *) _ryoku_desktop_current_socket=$_ryoku_desktop_runtime/$WAYLAND_DISPLAY ;;
    esac
    [ -S "$_ryoku_desktop_current_socket" ] && return 0
  fi

  _ryoku_desktop_handles=
  if command -v ryoku >/dev/null 2>&1; then
    _ryoku_desktop_handles=$(ryoku wm handles 2>/dev/null) || _ryoku_desktop_handles=
  fi

  _ryoku_desktop_source=
  _ryoku_desktop_manager=
  if command -v timeout >/dev/null 2>&1 &&
     command -v systemctl >/dev/null 2>&1; then
    if _ryoku_desktop_manager=$(timeout 3s systemctl --user show-environment 2>/dev/null); then
      _ryoku_desktop_source=manager
    fi
  fi

  _ryoku_desktop_envdir=
  if [ -z "$_ryoku_desktop_source" ]; then
    _ryoku_desktop_envdir=${TURNSTILE_ENV_DIR:-$HOME/.config/service-env}
    [ -d "$_ryoku_desktop_envdir" ] && _ryoku_desktop_source=envdir
  fi

  _ryoku_desktop_next_wayland=$(_ryoku_desktop_value WAYLAND_DISPLAY) ||
    _ryoku_desktop_next_wayland=
  _ryoku_desktop_next_display=$(_ryoku_desktop_value DISPLAY) ||
    _ryoku_desktop_next_display=
  case $_ryoku_desktop_next_wayland in
    /*) _ryoku_desktop_next_socket=$_ryoku_desktop_next_wayland ;;
    ?*) _ryoku_desktop_next_socket=$_ryoku_desktop_runtime/$_ryoku_desktop_next_wayland ;;
    *) _ryoku_desktop_next_socket= ;;
  esac

  if [ -n "$_ryoku_desktop_next_wayland" ] &&
     [ -S "$_ryoku_desktop_next_socket" ]; then
    unset WAYLAND_DISPLAY DISPLAY
    _ryoku_desktop_clear_handles

    WAYLAND_DISPLAY=$_ryoku_desktop_next_wayland
    export WAYLAND_DISPLAY
    if [ -n "$_ryoku_desktop_next_display" ]; then
      DISPLAY=$_ryoku_desktop_next_display
      export DISPLAY
    fi

    while IFS= read -r _ryoku_desktop_name; do
      _ryoku_desktop_valid_name "$_ryoku_desktop_name" || continue
      case $_ryoku_desktop_name in
        WAYLAND_DISPLAY|DISPLAY) continue ;;
      esac
      _ryoku_desktop_handle_value=$(_ryoku_desktop_value "$_ryoku_desktop_name") ||
        continue
      [ -n "$_ryoku_desktop_handle_value" ] || continue
      export "$_ryoku_desktop_name=$_ryoku_desktop_handle_value"
    done <<EOF
$_ryoku_desktop_handles
EOF
  elif [ -n "$_ryoku_desktop_had_wayland" ]; then
    unset WAYLAND_DISPLAY DISPLAY
    _ryoku_desktop_clear_handles
  fi
}

_ryoku_desktop_heal

unset -f _ryoku_desktop_value _ryoku_desktop_valid_name \
  _ryoku_desktop_clear_handles _ryoku_desktop_heal 2>/dev/null || :
unset _ryoku_desktop_runtime _ryoku_desktop_had_wayland
unset _ryoku_desktop_current_socket _ryoku_desktop_handles
unset _ryoku_desktop_source _ryoku_desktop_manager _ryoku_desktop_envdir
unset _ryoku_desktop_next_wayland _ryoku_desktop_next_display
unset _ryoku_desktop_next_socket _ryoku_desktop_name
unset _ryoku_desktop_line _ryoku_desktop_handle_value
