import QtQuick
import qs.Commons
import qs.Ui

// One checklist row: check button, nested indent, text, due date, delete.
CursorSurface {
  id: root

  property string itemId: ""
  property string itemText: ""
  property bool checked: false
  property bool editing: false
  property bool editingDue: false
  property bool dimmed: false
  property int depth: 0
  property int childCount: 0
  property bool collapsed: false
  property bool focused: false
  property bool dragging: false
  property string due: ""
  property string dueLabel: ""
  property string dueKind: "none"
  property color background: Color.background
  property string fontFamily: Style.font.family

  signal toggled()
  signal editRequested()
  signal deleteRequested()
  signal renamed(string text)
  signal editCanceled()
  signal indentRequested()
  signal outdentRequested()
  signal dueEditRequested()
  signal dueSubmitted(string due)
  signal dueEditCanceled()
  signal collapseRequested()
  signal rowHovered(bool isHovered)
  signal gripStarted()
  signal gripMoved(real x, real y)
  signal gripReleased()
  signal gripCanceled()

  readonly property color dueColor: {
    if (root.checked || root.dimmed) return Color.muted
    if (root.dueKind === "overdue") return Color.urgent
    if (root.dueKind === "today") return root.accent
    return Color.muted
  }

  function beginEdit() {
    editField.text = root.itemText
    editField.forceActiveFocus()
    editField.selectAll()
  }

  function beginDueEdit() {
    dueField.text = root.due
    dueField.forceActiveFocus()
    dueField.selectAll()
  }

  implicitHeight: Math.max(Style.space(34), row.implicitHeight + Style.space(8))
  radius: Style.cornerRadius
  current: root.focused
  opacity: root.dragging ? 0.35 : 1
  hasCursor: rowHover.containsMouse && !root.editing && !root.editingDue

  MouseArea {
    id: rowHover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: root.rowHovered(containsMouse)
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8) + root.depth * Style.space(20)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(6)

    Item {
      id: gripSlot
      width: Style.space(14)
      height: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.centerIn: parent
        text: "⋮"
        color: root.foreground
        opacity: grip.pressed || rowHover.containsMouse ? 0.85 : 0.28
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: grip
        anchors.fill: parent
        anchors.margins: -6
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX: 0
        property real pressY: 0
        property bool armed: false

        onPressed: function(mouse) {
          pressX = mouse.x
          pressY = mouse.y
          armed = false
        }
        onPositionChanged: function(mouse) {
          if (!(mouse.buttons & Qt.LeftButton)) return
          if (!armed) {
            var distance = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
            if (distance < Style.space(4)) return
            armed = true
            root.gripStarted()
          }
          var mapped = mapToItem(root, mouse.x, mouse.y)
          root.gripMoved(mapped.x, mapped.y)
        }
        onReleased: {
          if (armed) root.gripReleased()
          armed = false
        }
        onCanceled: {
          armed = false
          root.gripCanceled()
        }
      }
    }

    Item {
      id: foldSlot
      width: Style.space(14)
      height: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.childCount > 0

      Text {
        anchors.centerIn: parent
        text: root.collapsed ? "▸" : "▾"
        color: root.foreground
        opacity: 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: root.collapseRequested()
      }
    }

    BorderSurface {
      id: box
      width: Style.space(18)
      height: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      radius: Math.min(4, Style.cornerRadius)
      color: root.checked ? root.accent : "transparent"
      borderSpec: Border.flat(root.checked
        ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45), 1)

      Behavior on color { ColorAnimation { duration: 90 } }

      Text {
        visible: root.checked
        anchors.centerIn: parent
        text: "✓"
        color: root.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
      }
    }

    Item {
      width: Math.max(0, parent.width - gripSlot.width - (foldSlot.visible ? foldSlot.width + parent.spacing : 0)
        - box.width - dueChip.width - trash.width - parent.spacing * 4)
      height: Math.max(editField.implicitHeight, label.implicitHeight)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: label
        visible: !root.editing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.itemText
        color: root.checked || root.dimmed ? Color.muted : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.strikeout: root.checked
        elide: Text.ElideRight
        wrapMode: Text.NoWrap

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onClicked: root.editRequested()
        }
      }

      TextField {
        id: editField
        visible: root.editing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.itemText
        font.family: root.fontFamily
        foreground: root.foreground
        accent: root.accent
        verticalPadding: Style.space(3)
        horizontalPadding: Style.space(6)
        onVisibleChanged: if (visible) root.beginEdit()
        onAccepted: root.renamed(text)
        Keys.onTabPressed: function(event) {
          event.accepted = true
          root.renamed(text)
          root.indentRequested()
        }
        Keys.onBacktabPressed: function(event) {
          event.accepted = true
          root.renamed(text)
          root.outdentRequested()
        }
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.editCanceled()
        }
        onActiveFocusChanged: {
          if (root.editing && !activeFocus) root.renamed(text)
        }
      }
    }

    Item {
      id: dueChip
      width: Math.max(Style.space(64), dueLabelText.implicitWidth, dueField.visible ? dueField.implicitWidth : 0)
      height: Math.max(dueLabelText.implicitHeight, dueField.implicitHeight, Style.space(22))
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: dueLabelText
        visible: !root.editingDue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.dueLabel !== "" ? root.dueLabel : "due"
        color: root.dueLabel !== "" ? root.dueColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        opacity: rowHover.containsMouse || root.dueLabel !== "" ? 1 : 0

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.IBeamCursor
          onClicked: root.dueEditRequested()
        }
      }

      TextField {
        id: dueField
        visible: root.editingDue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(108)
        placeholderText: "today, +3"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        foreground: root.foreground
        accent: root.accent
        verticalPadding: Style.space(2)
        horizontalPadding: Style.space(6)
        onVisibleChanged: if (visible) root.beginDueEdit()
        onAccepted: root.dueSubmitted(text)
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.dueEditCanceled()
        }
        onActiveFocusChanged: {
          if (root.editingDue && !activeFocus) root.dueSubmitted(text)
        }
      }
    }

    PanelActionButton {
      id: trash
      iconText: "×"
      tooltipText: "Remove"
      foreground: root.foreground
      hoverColor: Color.urgent
      opacity: rowHover.containsMouse && !root.editing && !root.editingDue ? 1 : 0
      enabled: opacity > 0
      onClicked: root.deleteRequested()
    }
  }
}
