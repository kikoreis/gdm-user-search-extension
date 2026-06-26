# GDM User Search

A GNOME Shell extension that adds a type-as-you-find case-insensitive filter to the GDM login screen, letting you quickly find your account and log in.

![screenshot](screenshot.png)

## Features

- Filter users by username or real name as you type
- Up/down arrow navigation to select a user
- Enter to log in (auto-activates when only one user matches)
- Escape to clear search
- Shows hostname and IP address in the bottom-left corner

## Requirements

- GNOME Shell 46–50
- GDM (the extension only activates on the login screen, not the lock screen)

## Installation

### From source

```bash
git clone https://github.com/kikoreis/gdm-user-search-extension
cd gdm-user-search
sudo ./install.sh
sudo systemctl restart gdm
```

The install script copies the extension to `/usr/local/share/gnome-shell/extensions/`
and enables it for GDM via dconf.

### Manual

```bash
sudo mkdir -p /usr/local/share/gnome-shell/extensions/gdm-user-search@kiko-gnome.async.com.br
sudo cp -r gdm-user-search@kiko-gnome.async.com.br/* /usr/local/share/gnome-shell/extensions/gdm-user-search@kiko-gnome.async.com.br/
sudo dconf update
```

Then create `/etc/dconf/db/gdm.d/99-gdm-user-search` with:

```
[org/gnome/shell]
enabled-extensions=['gdm-user-search@kiko-gnome.async.com.br']
```

Then `sudo dconf update && sudo systemctl restart gdm`.

## Building

```bash
make build
```

Creates `gdm-user-search@kiko-gnome.async.com.br.shell-extension.zip`.

## Uninstall

```bash
sudo ./uninstall.sh
sudo systemctl restart gdm
```

## License

GPL-2.0-or-later
