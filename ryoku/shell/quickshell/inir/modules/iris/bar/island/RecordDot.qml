pragma ComponentBehavior: Bound

import QtQuick
import inir.services
import inir.modules.common
import inir.modules.common.widgets
import inir.modules.iris.style
import inir.modules.iris.components

// The recording mark, breathing (IrisPulse).
IrisPulse {
    implicitWidth: 9 * IrisStyle.density
    implicitHeight: implicitWidth
    color: IrisStyle.danger
}
