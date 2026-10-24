pragma Singleton

import QtQuick
import Quickshell
import shell.services as Ryoku

// StatusNotifier view for the vendored frame. Ryoku's daemon owns the SNI
// host (one watcher on the bus, resolved icons, dbusmenu trees); this shim
// exposes those streamed items in the shape the frame's tray widgets already
// read, so a second watcher never registers. Every rebind rebuilds the list,
// so delegates refresh through the item-model binding.
Singleton {
    id: root

    property var items: ({ values: root._build() })

    function _build() {
        const out = [];
        for (const raw of (Ryoku.Tray.items ?? []))
            out.push(_proxy(raw));
        return out;
    }

    function _proxy(raw) {
        const self = {
            id: String(raw.service ?? raw.id ?? ""),
            service: String(raw.service ?? ""),
            title: String(raw.title ?? ""),
            status: String(raw.status ?? "active"),
            iconName: String(raw.iconName ?? ""),
            iconPath: String(raw.iconPath ?? ""),
            icon: String(raw.iconPath ?? raw.iconName ?? ""),
            tooltipTitle: String(raw.tooltip?.title ?? ""),
            tooltipDescription: String(raw.tooltip?.description ?? ""),
            category: String(raw.category ?? ""),
            isMenu: raw.itemIsMenu === true,
            onlyMenu: raw.itemIsMenu === true,
            hasMenu: raw.menu !== undefined && raw.menu !== null,
            menu: raw.menu ?? null,
            activate: function (x, y) { Ryoku.Tray.activate(self.service, x ?? 0, y ?? 0); },
            secondaryActivate: function (x, y) { Ryoku.Tray.contextMenu(self.service, x ?? 0, y ?? 0); },
            contextMenu: function (x, y) { Ryoku.Tray.contextMenu(self.service, x ?? 0, y ?? 0); },
            scroll: function (delta, horiz) {
                Ryoku.Tray.scroll(self.service, delta, (horiz === true || String(horiz) === "horizontal")
                    ? "horizontal" : "vertical");
            },
            aboutToShow: function () { Ryoku.Tray.aboutToShow(self.service); },
            menuEvent: function (id) { Ryoku.Tray.menuEvent(self.service, Number(id) || 0); },
            closeMenu: function () { }
        };
        return self;
    }

    Connections {
        target: Ryoku.Tray
        function onItemsChanged() {
            root.items = ({ values: root._build() });
        }
    }
}
