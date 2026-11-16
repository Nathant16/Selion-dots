#!/usr/bin/env bash

# Reset DriftWM canvas bookmarks 1..9 to default positions (0,0), (2500,0), ...
for i in 1 2 3 4 5 6 7 8 9; do
    x=$(( (i - 1) * 2500 ))
    driftwm msg bookmark "$i" "$x" 0 2>/dev/null
done

if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "DriftWM" "Bookmarks Reset" "Canvas bookmarks 1..9 reset to default positions" -i preferences-desktop-display
fi
