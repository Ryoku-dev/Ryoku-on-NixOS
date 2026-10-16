import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import stage.modules.common
import stage.modules.common.widgets
import stage.services
import ".."
import Ryoku.Ui.Singletons

Scope {
    id: root

    LazyLoader {
        id: popupLoader
        active: GlobalStates.localSendPopupOpen

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: true
            screen: Quickshell.screens.find(s => s.name === (Wm.focusedOutput ?? ""))
                ?? Quickshell.screens[0] ?? null

            WlrLayershell.namespace: "quickshell:localSendPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // Keep incoming requests visible without assuming a compositor or bar edge.
            anchors {
                top: true
                right: true
            }
            margins {
                top: 12
                right: 12
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            LocalSendPopupContent {
                id: popupContent
                transfer: GlobalStates.localSendPopupTransfer

                onDismissed: LocalSend.denyTransfer()
                onAcceptRequested: {
                    LocalSend.acceptTransfer();
                }
                onRejectRequested: {
                    LocalSend.denyTransfer();
                }
            }
        }
    }
}
