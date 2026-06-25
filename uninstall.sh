#!/bin/bash
set -e

UUID=gdm-user-search@kiko-gnome.async.com.br
INSTALL_DIR=/usr/local/share/gnome-shell/extensions/$UUID
DCONF_DB_DIR=/etc/dconf/db/gdm.d
DCONF_FILE=$DCONF_DB_DIR/99-gdm-user-search

if [[ $(id -u) -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

echo "Removing GDM User Search extension..."

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed $INSTALL_DIR"
fi

if [[ -f "$DCONF_FILE" ]]; then
    rm -f "$DCONF_FILE"
    dconf update
    echo "  Removed dconf config and updated database"
fi

echo "Done! Reboot to see the change on the login screen."
