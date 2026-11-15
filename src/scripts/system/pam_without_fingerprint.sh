#!/usr/bin/env bash

SRC_DIR="${1:-/etc/pam.d}"
DEST_DIR="$2"
SERVICE="${3:-serpantinum}"

[ -n "$DEST_DIR" ] || exit 1
[ -d "$SRC_DIR" ] || exit 1

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR" || exit 1

for file in "$SRC_DIR"/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    if grep -qs "pam_fprintd" "$file"; then
        grep -v "pam_fprintd" "$file" | grep -v "pam_deny\.so" > "$DEST_DIR/$name"
    else
        ln -sf "$(readlink -f "$file")" "$DEST_DIR/$name"
    fi
done

if [ -f "$SRC_DIR/serpantinum-nofp" ]; then
    rm -f "$DEST_DIR/serpantinum-nofp"
    cp -L "$SRC_DIR/serpantinum-nofp" "$DEST_DIR/serpantinum-nofp"
elif [ -f "$SRC_DIR/system-auth" ]; then
    rm -f "$DEST_DIR/serpantinum-nofp"
    printf 'auth        include      system-auth\naccount     include      system-auth\n' > "$DEST_DIR/serpantinum-nofp"
elif [ -f "$SRC_DIR/common-auth" ]; then
    rm -f "$DEST_DIR/serpantinum-nofp"
    printf 'auth        include      common-auth\naccount     include      common-auth\n' > "$DEST_DIR/serpantinum-nofp"
elif [ -f "$SRC_DIR/login" ]; then
    rm -f "$DEST_DIR/serpantinum-nofp"
    printf 'auth        include      login\naccount     include      login\n' > "$DEST_DIR/serpantinum-nofp"
fi
