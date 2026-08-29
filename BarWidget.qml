import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "novique.lists"

  readonly property var lists: bar && bar.shell
    ? bar.shell.serviceFor("novique.lists") : null
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property bool windowOpen: !!lists && lists.windowOpen === true

  function openWindow() {
    if (!bar || !bar.shell) return
    if (typeof bar.shell.toggle === "function") bar.shell.toggle("novique.lists", "{}")
    else if (typeof bar.shell.summon === "function") bar.shell.summon("novique.lists", "{}")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.lists && root.lists.glyph ? root.lists.glyph : String.fromCodePoint(0xF0DC9)
    tooltipText: root.lists ? root.lists.tooltip : "Lists"
    foreground: root.foreground
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openWindow()
    }
  }

  Rectangle {
    id: openIndicator
    readonly property bool vertical: !!root.bar && root.bar.vertical
    visible: root.windowOpen
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: vertical ? Style.space(2) : Style.space(10)
    height: vertical ? Style.space(10) : Style.space(2)
    x: vertical
      ? (root.bar.position === "left" ? root.width - width - Style.space(2) : Style.space(2))
      : Math.round((root.width - width) / 2)
    y: vertical
      ? Math.round((root.height - height) / 2)
      : (root.bar && root.bar.position === "top"
        ? root.height - height - Style.space(2) : Style.space(2))
  }
}
