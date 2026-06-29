#!/bin/bash
set -e

UUID=gdm-user-search@kiko-gnome.async.com.br
INSTALL_DIR=/usr/local/share/gnome-shell/extensions/$UUID
DCONF_DB_DIR=/etc/dconf/db/gdm.d
DCONF_FILE=$DCONF_DB_DIR/99-gdm-user-search
DCONF_PROFILE=/etc/dconf/profile/gdm

if [[ $(id -u) -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

echo "Installing GDM User Search extension..."

# Remove any old extension installations with conflicting UUIDs
for old in /usr/local/share/gnome-shell/extensions/gdm-user-search*; do
    if [[ -d "$old" && "$old" != "$INSTALL_DIR" ]]; then
        echo "  Removing old extension: $old"
        rm -rf "$old"
    fi
done

mkdir -p "$INSTALL_DIR"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ZIP_NAME="$UUID.shell-extension.zip"

if [[ -d "$SCRIPT_DIR/$UUID" ]]; then
    cp -r "$SCRIPT_DIR/$UUID"/* "$INSTALL_DIR/"
elif [[ -f "$SCRIPT_DIR/extension.js" ]]; then
    cp "$SCRIPT_DIR"/extension.js "$INSTALL_DIR/"
    cp "$SCRIPT_DIR"/metadata.json "$INSTALL_DIR/"
    cp "$SCRIPT_DIR"/stylesheet.css "$INSTALL_DIR/"
elif [[ -f "$SCRIPT_DIR/$ZIP_NAME" ]]; then
    echo "  Extracting $ZIP_NAME..."
    TMP_DIR=$(mktemp -d)
    unzip -oq "$SCRIPT_DIR/$ZIP_NAME" -d "$TMP_DIR"
    cp -r "$TMP_DIR"/* "$INSTALL_DIR/"
    rm -rf "$TMP_DIR"
else
    echo "ERROR: Cannot find extension files or zip archive in $SCRIPT_DIR"
    echo "Expected: $UUID/ directory, or individual .js/.json/.css files, or $ZIP_NAME"
    exit 1
fi

echo "  Files installed to $INSTALL_DIR"

mkdir -p "$DCONF_DB_DIR"

cat > "$DCONF_FILE" << HERE
[org/gnome/shell]
enabled-extensions=['$UUID']
HERE

if [[ ! -f "$DCONF_PROFILE" ]]; then
    cat > "$DCONF_PROFILE" << HERE
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
HERE
    echo "  Created dconf profile $DCONF_PROFILE"
fi

dconf update
echo "  dconf updated — extension enabled for GDM"

# The greeter's personal dconf can hold disable-user-extensions=true
# which silently blocks ALL GDM-mode extensions from reaching ACTIVE.
# This is a common stale leftover after 24.04 -> 26.04 upgrades.
#
# The greeter dconf lives at $XDG_CONFIG_HOME/dconf/user, NOT
# $HOME/.config/dconf/user.  GDM sets XDG_CONFIG_HOME to
# /var/lib/gdm3/seat<NN>/config at runtime.  Check both paths.

DCONF_RESET_PATH=/org/gnome/shell/disable-user-extensions

# Path 1: traditional $HOME/.config/dconf/user
for GDM_USER in gdm gdm-greeter; do
    GDM_HOME=$(getent passwd "$GDM_USER" 2>/dev/null | cut -d: -f6)
    GDM_DCONF_USER="$GDM_HOME/.config/dconf/user"
    if [[ -f "$GDM_DCONF_USER" ]]; then
        if grep -aq 'disable-user-extensions' "$GDM_DCONF_USER" 2>/dev/null; then
            echo "  Clearing disable-user-extensions in $GDM_USER home dconf..."
            sudo -u "$GDM_USER" dbus-run-session \
                dconf reset "$DCONF_RESET_PATH" \
                2>/dev/null || true
        fi
    fi
done

# Path 2: /var/lib/gdm3/seat*/config/dconf/user (greeter path)
for SEAT_DCONF in /var/lib/gdm3/seat*/config/dconf/user; do
    [[ -f "$SEAT_DCONF" ]] || continue
    if grep -aq 'disable-user-extensions' "$SEAT_DCONF" 2>/dev/null; then
        SEAT_CONFIG=$(dirname "$(dirname "$SEAT_DCONF")")
        echo "  Clearing disable-user-extensions in $SEAT_DCONF..."
        sudo -u gdm-greeter \
            XDG_CONFIG_HOME="$SEAT_CONFIG" \
            DCONF_PROFILE=gdm \
            dbus-run-session \
            dconf reset "$DCONF_RESET_PATH" \
            2>/dev/null || true
    fi
done

echo ""
echo "--- Verification ---"

FAIL=0

for f in extension.js metadata.json stylesheet.css; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        echo "  [OK] $f"
    else
        echo "  [FAIL] $f not found in $INSTALL_DIR"
        FAIL=1
    fi
done

INSTALLED_UUID=$(grep -oP '"uuid":\s*"\K[^"]+' "$INSTALL_DIR/metadata.json" 2>/dev/null || true)
if [[ "$INSTALLED_UUID" == "$UUID" ]]; then
    echo "  [OK] UUID: $INSTALLED_UUID"
else
    echo "  [FAIL] UUID mismatch: expected '$UUID', got '$INSTALLED_UUID'"
    FAIL=1
fi

DCONF_UUID=$(grep -oP "'\K[^']+(?=')" "$DCONF_FILE" 2>/dev/null || true)
if [[ "$DCONF_UUID" == "$UUID" ]]; then
    echo "  [OK] dconf enables: $DCONF_UUID"
else
    echo "  [FAIL] dconf UUID mismatch: expected '$UUID', got '$DCONF_UUID'"
    FAIL=1
fi

if [[ -f "$DCONF_PROFILE" ]]; then
    echo "  [OK] dconf profile exists at $DCONF_PROFILE"
else
    echo "  [FAIL] dconf profile missing at $DCONF_PROFILE"
    FAIL=1
fi

LOCALE_FILES=$(find "$INSTALL_DIR/locale" -name '*.mo' 2>/dev/null | wc -l)
if [[ "$LOCALE_FILES" -gt 0 ]]; then
    echo "  [OK] $LOCALE_FILES .mo files installed"
else
    echo "  [WARN] No .mo files found — translations won't work"
fi

# Check greeter dconf for stale disable-user-extensions.
# Try reading the live greeter's XDG_CONFIG_HOME from /proc,
# fall back to globbing /var/lib/gdm3/seat*/config/dconf/user.
GREETER_DCONF_DIRS=()
GREETER_PID=$(pgrep -u gdm-greeter -f gnome-shell 2>/dev/null | head -1)
if [[ -n "$GREETER_PID" ]] && [[ -r "/proc/$GREETER_PID/environ" ]]; then
    GREETER_XDG=$(tr '\0' '\n' < "/proc/$GREETER_PID/environ" \
        | grep '^XDG_CONFIG_HOME=' | cut -d= -f2-)
    if [[ -n "$GREETER_XDG" ]]; then
        GREETER_DCONF_DIRS+=("$GREETER_XDG/dconf")
    fi
else
    # Fall back to glob (covers multi-seat and no-greeter-running cases)
    for SEAT_DCONF in /var/lib/gdm3/seat*/config/dconf; do
        [[ -d "$SEAT_DCONF" ]] || continue
        GREETER_DCONF_DIRS+=("$SEAT_DCONF")
    done
fi

DCONF_STALE_FOUND=0
for DCONF_DIR in "${GREETER_DCONF_DIRS[@]}"; do
    DCONF_USER="$DCONF_DIR/user"
    [[ -f "$DCONF_USER" ]] || continue
    if grep -aq 'disable-user-extensions' "$DCONF_USER" 2>/dev/null; then
        echo "  [FAIL] stale disable-user-extensions in $DCONF_USER"
        DCONF_STALE_FOUND=1
    else
        echo "  [OK] greeter dconf clean: $DCONF_USER"
    fi
done
if [[ $DCONF_STALE_FOUND -ne 0 ]]; then
    FAIL=1
    echo "         Manual fix:"
    echo "           sudo -u gdm-greeter \\"
    echo "             XDG_CONFIG_HOME=<seat-config-dir> \\"
    echo "             DCONF_PROFILE=gdm dbus-run-session \\"
    echo "             dconf reset /org/gnome/shell/disable-user-extensions"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "All checks passed. Restart GDM: sudo systemctl restart gdm"
else
    echo "Some checks failed — review errors above."
    exit 1
fi
