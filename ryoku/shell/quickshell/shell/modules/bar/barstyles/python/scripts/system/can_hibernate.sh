#!/usr/bin/env bash

if command -v dbus-send &>/dev/null; then
    reply=$(dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.CanHibernate 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$reply" ]; then
        if echo "$reply" | grep -qE 'string "(yes|challenge)"'; then
            echo "yes"
        else
            echo "no"
        fi
        exit 0
    fi
fi

if command -v loginctl &>/dev/null; then
    reply=$(loginctl can-hibernate 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$reply" ]; then
        if [[ "$reply" == "yes" || "$reply" == "challenge" ]]; then
            echo "yes"
        else
            echo "no"
        fi
        exit 0
    fi
fi

if [ -f /sys/power/state ] && grep -qw disk /sys/power/state; then
    if [ -f /proc/swaps ] && [ "$(wc -l < /proc/swaps)" -gt 1 ]; then
        if [ -f /sys/power/resume ] && [ "$(cat /sys/power/resume 2>/dev/null)" != "0:0" ]; then
            echo "yes"
            exit 0
        fi
    fi
fi

echo "no"
