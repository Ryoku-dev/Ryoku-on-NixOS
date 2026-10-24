# A herdr, tmux or zellij server keeps the environment of the login that started
# it. Started over SSH or from a TTY before the desktop, every pane it opens has
# no display, so Ctrl+V and every clipboard tool inside fail. A new pane borrows
# the running desktop's display from the user manager (Turnstile's env dir on
# Void); the bash and zsh twin is terminal-shell/desktop-display.sh.

function __ryoku_heal_desktop_display
    status is-interactive; or return
    if not set -q HERDR_ENV; and not set -q TMUX; and not set -q ZELLIJ
        return
    end

    set -l runtime_dir
    if set -q XDG_RUNTIME_DIR; and test -n "$XDG_RUNTIME_DIR"
        set runtime_dir "$XDG_RUNTIME_DIR"
    else
        set runtime_dir /run/user/(id -u)
    end

    set -l had_wayland
    if set -q WAYLAND_DISPLAY
        set had_wayland 1
        set -l current_socket "$WAYLAND_DISPLAY"
        if not string match -q '/*' -- "$current_socket"
            set current_socket "$runtime_dir/$current_socket"
        end
        test -S "$current_socket"; and return
    end

    set -l handles
    if command -q ryoku
        set -l printed_handles (ryoku wm handles 2>/dev/null)
        if test $status -eq 0
            for name in $printed_handles
                string match -rq '^[A-Za-z_][A-Za-z0-9_]*$' -- "$name"; or continue
                contains -- "$name" WAYLAND_DISPLAY DISPLAY; and continue
                contains -- "$name" $handles; or set -a handles "$name"
            end
        end
    end

    set -l source_kind
    set -l manager_env
    if command -q timeout; and command -q systemctl
        set manager_env (timeout 3s systemctl --user show-environment 2>/dev/null)
        test $status -eq 0; and set source_kind manager
    end

    set -l env_dir
    if test -z "$source_kind"
        if set -q TURNSTILE_ENV_DIR; and test -n "$TURNSTILE_ENV_DIR"
            set env_dir "$TURNSTILE_ENV_DIR"
        else
            set env_dir "$HOME/.config/service-env"
        end
        test -d "$env_dir"; and set source_kind envdir
    end

    set -l names WAYLAND_DISPLAY DISPLAY $handles
    set -l values
    for name in $names
        set -l value ''
        if test "$source_kind" = manager
            for line in $manager_env
                set -l pair (string split -m 1 = -- "$line")
                if test (count $pair) -eq 2; and test "$pair[1]" = "$name"
                    set value "$pair[2]"
                    break
                end
            end
        else if test "$source_kind" = envdir
            set -l path "$env_dir/$name"
            test -r "$path"; and set value (string collect < "$path")
        end
        test (count $value) -gt 0; or set value ''
        set -a values "$value"
    end

    set -l next_wayland "$values[1]"
    set -l next_socket "$next_wayland"
    if test -n "$next_socket"; and not string match -q '/*' -- "$next_socket"
        set next_socket "$runtime_dir/$next_socket"
    end

    if test -n "$next_wayland"; and test -S "$next_socket"
        for name in $names
            set -e $name
        end
        set -l index 1
        for name in $names
            set -l value "$values[$index]"
            test -n "$value"; and set -gx $name "$value"
            set index (math $index + 1)
        end
    else if test -n "$had_wayland"
        for name in $names
            set -e $name
        end
    end
end

__ryoku_heal_desktop_display
functions -e __ryoku_heal_desktop_display
