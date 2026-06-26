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
    # Compile translations if po/ exists but .mo files missing
    if [[ -d "$SCRIPT_DIR/po" ]]; then
        MO_EXISTS=$(ls "$SCRIPT_DIR/$UUID/locale/"*.mo 2>/dev/null | head -1)
        if [[ -z "$MO_EXISTS" ]]; then
            echo "  Compiling translations..."
            make -C "$SCRIPT_DIR" mo 2>/dev/null || echo "  (msgfmt not available, skipping i18n)"
        fi
    fi
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

# The gdm user's personal dconf can hold disable-user-extensions=true
# which prevents our extension from loading.  Reset it.
for GDM_USER in gdm gdm-greeter; do
    GDM_HOME=$(getent passwd "$GDM_USER" 2>/dev/null | cut -d: -f6)
    GDM_DCONF_USER="$GDM_HOME/.config/dconf/user"
    if [[ -f "$GDM_DCONF_USER" ]]; then
        if grep -aq 'disable-user-extensions' "$GDM_DCONF_USER" 2>/dev/null; then
            echo "  Clearing disable-user-extensions in $GDM_USER dconf..."
            sudo -u "$GDM_USER" dbus-run-session \
                dconf reset /org/gnome/shell/disable-user-extensions \
                2>/dev/null || true
        fi
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

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "All checks passed. Restart GDM: sudo systemctl restart gdm"
else
    echo "Some checks failed — review errors above."
    exit 1
fi
