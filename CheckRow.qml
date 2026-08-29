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
  signal dueChanged(string due)
  signal dueEditCanceled()
  signal hovered(bool isHovered)

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
  current: false
  hasCursor: rowHover.containsMouse && !root.editing && !root.editingDue

  MouseArea {
    id: rowHover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: root.hovered(containsMouse)
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8) + root.depth * Style.space(20)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)

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
      width: parent.width - box.width - dueChip.width - trash.width - parent.spacing * 3
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
        placeholderText: "YYYY-MM-DD"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        foreground: root.foreground
        accent: root.accent
        verticalPadding: Style.space(2)
        horizontalPadding: Style.space(6)
        onVisibleChanged: if (visible) root.beginDueEdit()
        onAccepted: root.dueChanged(text)
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.dueEditCanceled()
        }
        onActiveFocusChanged: {
          if (root.editingDue && !activeFocus) root.dueChanged(text)
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
