# Implementation Notes

## Architecture

The extension monkey-patches `LoginDialog._showUserList` and
`_hideUserList` to inject a search `St.Entry` above the user list in
`_userSelectionBox`. A hostname/IP label is added to
`_lockDialogGroup` as an overlay.

## GDM Caveats

GDM extensions differ from user-session extensions in several ways.

### Root installation

Extensions that target the login screen must be installed in
`/usr/local/share/gnome-shell/extensions/` (root-owned), not
`~/.local/share/gnome-shell/extensions/`.  The dconf database at
`/etc/dconf/db/gdm.d/` must also be updated as a system administrator.

### ESM vs legacy imports

`import GLib from 'gi://GLib'` crashes module load in the GDM
context.  Use `const GLib = imports.gi.GLib` (legacy global) instead.
Other `gi://` and `resource://` ESM imports (Clutter, St, Gio, Main,
Extension) work fine.

### insert_child_before silently fails

`_userSelectionBox.insert_child_before(entry, userList)` compiles but
the entry never appears.  Use
`_userSelectionBox.insert_child_at_index(entry, 0)` to reliably
insert at the top.

### LoginDialog allocation

`LoginDialog` implements a custom `vfunc_allocate` that only lays out
known children (`_userSelectionBox`, `_bottomButtonGroup`, etc.).
Unknown children passed to `add_child()` are ignored.  To add an
overlay label, parent it to `Main.screenShield._lockDialogGroup`
instead and call `set_position()` manually during allocation.

### User list height

The user list is a `St.ScrollView` inside the `_userSelectionBox`
`St.BoxLayout`.  By default `vfunc_allocate` expands it to fill all
remaining vertical space.  To limit its height:

```js
const [, stageH] = global.stage.get_size();
d._userList.y_expand = false;
d._userList.set_height(Math.floor(stageH * 0.6));
```

### Debug reload requires GDM restart

After changing extension files, a simple lock/unlock is not
sufficient.  Run `sudo systemctl restart gdm` to reload the
extension for the login screen.

### dconf changes require restart

Changing `enabled-extensions` in the GDM dconf database also
requires a GDM restart to take effect.

### install.sh must handle locale/ directories

The zip bundle contains a `locale/` subtree with compiled `.mo`
files.  The install script's `cp` must use `-r` to copy
directories, or the locale data will be silently skipped.

### global.log is not available

`global.log()` does not exist in the GDM greeter context and
will crash the extension with "TypeError: global.log is not a
function".  Use bare `log()` (global scope) instead.

### Hostname and IP

Hostname is read via `GLib.get_host_name()`.  IP addresses are
obtained by spawning `hostname -I` via
`GLib.spawn_command_line_sync()` (the sole reason the legacy
`imports.gi.GLib` import is needed).  Only the first IPv4 address
is displayed.

### Overlay label positioning

The info label position is recalculated on every
`notify::allocation` of `_lockDialogGroup`.  The margin from the
bottom-left corner is hardcoded at 16px.

### Version differences in UserList internals

The `UserList._items` property changed type between GNOME Shell
versions:
- GNOME 46: plain object (`this._items = {}`)
- GNOME 50: `Map` (`this._items = new Map()`)

The user items themselves (UserListItem actors) live in the inner
`St.BoxLayout` (`_box`), not directly in the `St.ScrollView`.  To
iterate user items across all versions, traverse via `_box`:

```js
const box = this._dialog._userList._box;
if (box)
    return box.get_children().filter(c => c.user);
```

The `UserList.get_children()` method returns scroller internals
(scrollbars, viewport), not the user items themselves.

### Session modes

Metadata must include `"session-modes": ["gdm"]` to prevent
activation on the lock screen or user session.

### disable-user-extensions in greeter dconf

The GDM greeter's personal dconf database can hold
`disable-user-extensions=true`, which silently blocks **all**
GDM-mode extensions from reaching ACTIVE state.  The extension
goes straight to INITIALIZED — the module is never even imported.

**Mechanism.** In `extensionSystem.js`, `_getEnabledExtensions()`:

```js
if (!global.settings.get_boolean(DISABLE_USER_EXTENSIONS_KEY))
    extensions = extensions.concat(
        global.settings.get_strv(ENABLED_EXTENSIONS_KEY));
```

When `disable-user-extensions=true`, the `enabled-extensions` key
is ignored entirely.  Our UUID never enters `_enabledExtensions`,
so `loadExtension()` sets `INITIALIZED` without importing the
module or calling `enable()`.

**Why it is hard to find.** There is no log message when
`disable-user-extensions` blocks the `enabled-extensions` key.
The extension silently lands at INITIALIZED.  gnome-shell's `Eval`
D-Bus method is disabled in GDM mode (returns `false, ''`), so the
runtime state cannot be inspected via D-Bus.  The only way to
confirm the live value is GDB:

```
set $s = (void*)g_settings_new("org.gnome.shell")
set $d = g_settings_get_boolean($s, "disable-user-extensions")
printf "disable-user = %d\n", $d
```

**The greeter dconf path is not $HOME.** GDM sets
`XDG_CONFIG_HOME=/var/lib/gdm3/seat<NN>/config` at runtime, so the
personal dconf database lives at
`/var/lib/gdm3/seat0/config/dconf/user`, **not**
`~gdm-greeter/.config/dconf/user`.  The `gdm-greeter` user's home
(`/run/gdm3/home/gdm-greeter`) is a tmpfs path with no persistent
dconf.  Checking `getent passwd gdm-greeter` and looking at
`$HOME/.config/dconf/user` will find nothing.

**Upgrade-specific.** This stale key is a leftover from 24.04
upgrades to 26.04.  Fresh 26.04 installs do not have the
`/var/lib/gdm3/seat0/config/dconf/user` file at all.  The
discrepancy between upgraded and fresh installs makes the bug
reproducible only on upgraded systems.

**Confirming in the filesystem:**

```bash
sudo strings /var/lib/gdm3/seat0/config/dconf/user | grep disable-user
```

**The dconf profile chain** for the greeter (from
`/etc/dconf/profile/gdm`):

1. `user-db:user` → `/var/lib/gdm3/seat0/config/dconf/user`
   (highest priority — holds the stale key)
2. `system-db:gdm` → `/etc/dconf/db/gdm` (where install.sh writes
   `enabled-extensions`)
3. `file-db:/usr/share/gdm/greeter-dconf-defaults`

Layer 1 takes priority, so `disable-user-extensions=true` in the
personal database overrides everything in layer 2.

**Fix.** Reset the key with the correct `XDG_CONFIG_HOME`:

```bash
sudo -u gdm-greeter \
    XDG_CONFIG_HOME=/var/lib/gdm3/seat0/config \
    DCONF_PROFILE=gdm \
    dbus-run-session \
    dconf reset /org/gnome/shell/disable-user-extensions
```

`install.sh` checks both `$HOME/.config/dconf/user` and
`/var/lib/gdm3/seat*/config/dconf/user` (globbed for multi-seat)
and resets the key when found.

## i18n

The extension uses `imports.gettext` with UUID as the domain. `.mo`
files live under `locale/LANG/LC_MESSAGES/` inside the extension
directory.  The `Makefile` compiles `.po` → `.mo` during `make
build`.

## Debugging

### Enabling verbose extension logging

To see "Loading extension" / "Changing state" messages from the
GDM greeter's gnome-shell, set `G_MESSAGES_DEBUG=all` in
`/etc/environment` and **reboot**.  The gnome-shell process
inherits its environment from the GDM launch environment, not from
the user's session or PAM, so a simple `systemctl restart gdm` is
not sufficient — only a full reboot propagates the change.

### Reading logs

Restart GDM and check logs.  The GDM greeter's unit varies by
distribution and version:

- Ubuntu 24.04 (X11 GDM): `journalctl -u gdm -b`
- Ubuntu 26.04 (Wayland GDM): `journalctl -u user@$(id -u gdm-greeter).service -b`

Or find the greeter PID (`ps aux | grep 'gnome-shell.*mode=gdm'`)
then `journalctl -b _PID=<pid>`.

In all cases pipe through `grep gdm-user-search`.  There is no way
to test GDM extensions from a user session.
