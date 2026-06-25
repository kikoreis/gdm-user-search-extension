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

### Hostname and IP

Hostname is read from `/proc/sys/kernel/hostname` via
`Gio.File.load_contents()`.  IP addresses are obtained by spawning
`hostname -I` via `GLib.spawn_command_line_sync()` (the sole reason
the legacy `imports.gi.GLib` import is needed).  Only the first IPv4
address is displayed.

### Overlay label positioning

The info label position is recalculated on every
`notify::allocation` of `_lockDialogGroup`.  The margin from the
bottom-right corner is hardcoded at 16px.

### Session modes

Metadata must include `"session-modes": ["gdm"]` to prevent
activation on the lock screen or user session.

## i18n

The extension uses `imports.gettext` with UUID as the domain. `.mo`
files live under `locale/LANG/LC_MESSAGES/` inside the extension
directory.  The `Makefile` compiles `.po` → `.mo` during `make
build`.

## Debugging

Restart GDM and check journalctl:

```bash
journalctl -u gdm -b --no-pager | grep gdm-user-search
```

There is no way to test GDM extensions from a user session.
