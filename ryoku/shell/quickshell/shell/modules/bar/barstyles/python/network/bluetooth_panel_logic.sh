#!/usr/bin/env bash

pactl list cards 2>/dev/null | awk '
    /Name: bluez_card/ {
        match($0, /bluez_card\.[0-9A-Fa-f_]+/)
        mac = substr($0, RSTART+11, RLENGTH-11)
        gsub(/_/, ":", mac)
        mac = tolower(mac)
        found=1
    }
    found && /Active Profile:/ {
        sub(/.*Active Profile: /, "")
        prof = $0
        if (prof ~ /a2dp/) prof = "Hi-Fi (A2DP)"
        else if (prof ~ /headset|hfp|hsp/) prof = "Headset (HFP)"
        else if (prof == "off") prof = "None"
        else prof = "Connected"

        printf "%s\037%s\n", mac, prof
        found=0
    }
' | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\u001f")) | map({(.[0]): .[1]}) | add // {}
'
