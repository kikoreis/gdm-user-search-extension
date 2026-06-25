import Clutter from 'gi://Clutter';
import St from 'gi://St';
import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const GLib = imports.gi.GLib;
const Gettext = imports.gettext;

let _ = s => s;

function _initTranslations(dir) {
    const domain = 'gdm-user-search@kiko-gnome.async.com.br';
    Gettext.bindtextdomain(domain, dir + '/locale');
    _ = Gettext.domain(domain).gettext;
}

function _itemMatchesFilter(item, text) {
    if (text === '') return true;
    const userName = item.user.get_user_name() || '';
    const realName = item.user.get_real_name() || '';
    return realName.toLowerCase().includes(text) ||
        userName.toLowerCase().includes(text);
}

function _applyFilterToItem(item, text) {
    const matches = _itemMatchesFilter(item, text);
    item.visible = matches;
    item.reactive = matches;
    item.can_focus = matches;
    return matches;
}

export default class GdmUserSearchExtension extends Extension {
    enable() {
        _initTranslations(this.dir.get_path());

        this._searchEntry = null;
        this._dialog = null;
        this._searchText = '';
        this._signalIds = [];
        this._origShowUserList = null;
        this._origHideUserList = null;

        const signal = Main.layoutManager.connect('startup-complete',
            () => this._onReady());
        this._signalIds.push({ obj: Main.layoutManager, id: signal });
        this._onReady();
    }

    _onReady() {
        if (this._searchEntry)
            return;
        this._dialog = this._findLoginDialog();
        if (!this._dialog)
            return;
        this._inject();
    }

    _findLoginDialog() {
        if (!Main.screenShield || !Main.screenShield._lockDialogGroup)
            return null;
        const children = Main.screenShield._lockDialogGroup.get_children();
        for (const child of children) {
            if (child._userList && child._userSelectionBox)
                return child;
        }
        return null;
    }

    _getHostname() {
        try {
            const f = Gio.File.new_for_path('/proc/sys/kernel/hostname');
            const [, contents] = f.load_contents(null);
            return contents.toString().trim() || 'localhost';
        } catch (_e) {}
        return 'localhost';
    }

    _getIpAddress() {
        try {
            const [ok, out] = GLib.spawn_command_line_sync('hostname -I');
            if (ok && out) {
                const ips = out.toString().trim().split(/\s+/);
                const ipv4 = ips.find(ip => ip.includes('.'));
                return ipv4 || ips[0] || null;
            }
        } catch (_e) {}
        return null;
    }

    _inject() {
        const d = this._dialog;

        this._searchEntry = new St.Entry({
            style_class: 'login-dialog-search-entry',
            hint_text: _('Search users\u2026'),
            can_focus: true,
            x_expand: true,
            visible: false,
        });

        this._searchEntry.clutter_text.connect('text-changed',
            () => this._onSearchTextChanged());
        this._searchEntry.clutter_text.connect('key-press-event',
            (actor, event) => this._onSearchKeyPress(event));
        this._searchEntry.clutter_text.connect('activate',
            () => this._onSearchActivate());

        d._userSelectionBox.insert_child_at_index(this._searchEntry, 0);

        const id = d._userList.connect('item-added', (list, item) => {
            _applyFilterToItem(item, this._searchText);
        });
        this._signalIds.push({ obj: d._userList, id });

        this._origShowUserList = d._showUserList.bind(d);
        d._showUserList = () => this._showUserList();
        this._origHideUserList = d._hideUserList.bind(d);
        d._hideUserList = () => this._hideUserList();

        // Hostname/IP label at bottom-right
        const infoLabel = new St.Label({
            style_class: 'login-dialog-info-label',
            text: this._getHostname(),
        });
        this._infoLabel = infoLabel;
        this._updateInfoLabel();

        const root = Main.screenShield._lockDialogGroup;
        root.add_child(infoLabel);

        const positionInfo = () => {
            if (!infoLabel || !infoLabel.get_stage())
                return;
            const [stageW, stageH] = global.stage.get_size();
            const [, , natW, natH] = infoLabel.get_preferred_size();
            infoLabel.set_position(stageW - natW - 16, stageH - natH - 16);
        };
        positionInfo();

        const posId = root.connect('notify::allocation', () => positionInfo());
        this._signalIds.push({ obj: root, id: posId });

        // Re-focus search entry when stage regains focus (screen wake)
        const stageFocusId = global.stage.connect('notify::focus', () => {
            if (global.stage.focus && this._searchEntry)
                this._searchEntry.grab_key_focus();
        });
        this._signalIds.push({ obj: global.stage, id: stageFocusId });

        // Constrain user list height to ~40% of screen
        const [, stageH] = global.stage.get_size();
        d._userList.y_expand = false;
        d._userList.set_height(Math.floor(stageH * 0.6));

        if (d._userSelectionBox.visible) {
            this._searchEntry.show();
            this._searchEntry.grab_key_focus();
        }
    }

    _updateInfoLabel() {
        if (!this._infoLabel)
            return;
        const hostname = this._getHostname();
        const ip = this._getIpAddress();
        this._infoLabel.text = ip ? `${hostname}\n${ip}` : hostname;
    }

    _showUserList() {
        this._origShowUserList();
        this._searchEntry.text = '';
        this._searchEntry.show();
        this._searchEntry.grab_key_focus();
    }

    _hideUserList() {
        this._origHideUserList();
        this._searchEntry.text = '';
        this._searchEntry.hide();
        this._resetFilter();
    }

    _onSearchTextChanged() {
        if (!this._searchEntry)
            return;
        this._searchText = this._searchEntry.text.toLowerCase().trim();
        this._filterItems();
    }

    _onSearchKeyPress(event) {
        const symbol = event.get_key_symbol();
        if (symbol === Clutter.KEY_Down) {
            const first = this._getFirstVisibleItem();
            if (first) {
                first.grab_key_focus();
                return Clutter.EVENT_STOP;
            }
        } else if (symbol === Clutter.KEY_Escape) {
            if (this._searchEntry.text !== '') {
                this._searchEntry.text = '';
                return Clutter.EVENT_STOP;
            }
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _onSearchActivate() {
        if (!this._dialog)
            return;
        this._searchText = this._searchEntry.text.toLowerCase().trim();
        const { count, first } = this._filterItems();
        if (count === 1 && first)
            first.emit('activate');
    }

    _filterItems() {
        let count = 0;
        let first = null;
        const items = this._dialog._userList._items;
        for (const userName in items) {
            const item = items[userName];
            if (_applyFilterToItem(item, this._searchText)) {
                count++;
                if (!first)
                    first = item;
            }
        }
        return { count, first };
    }

    _resetFilter() {
        this._searchText = '';
        if (!this._dialog)
            return;
        const items = this._dialog._userList._items;
        for (const userName in items) {
            const item = items[userName];
            item.visible = true;
            item.reactive = true;
            item.can_focus = true;
        }
    }

    _getFirstVisibleItem() {
        if (!this._dialog)
            return null;
        const items = this._dialog._userList._items;
        for (const userName in items) {
            if (items[userName].visible)
                return items[userName];
        }
        return null;
    }

    disable() {
        for (const { obj, id } of this._signalIds)
            obj.disconnect(id);
        this._signalIds = [];

        if (this._dialog) {
            if (this._origShowUserList)
                this._dialog._showUserList = this._origShowUserList;
            if (this._origHideUserList)
                this._dialog._hideUserList = this._origHideUserList;
        }
        if (this._infoLabel) {
            this._infoLabel.destroy();
            this._infoLabel = null;
        }
        if (this._searchEntry) {
            this._searchEntry.destroy();
            this._searchEntry = null;
        }
        this._dialog = null;
        this._origShowUserList = null;
        this._origHideUserList = null;
    }
}
