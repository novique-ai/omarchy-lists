import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// Application window for Lists. The shell loads this when the plugin is
// summoned and calls open()/close(); the FloatingWindow follows.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false

  property bool editingTitle: false
  property string editingItemId: ""
  property string editingDueId: ""
  property string focusedItemId: ""
  property string pendingDeleteId: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "novique.lists"
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color dim: Color.muted
  readonly property string fontFamily: Style.font.family
  readonly property var lists: service
  readonly property var currentList: lists ? lists.currentList : null
  readonly property var currentItems: lists ? lists.currentItems : []
  readonly property var openLists: lists ? lists.openLists : []
  readonly property var archivedLists: lists ? lists.archivedLists : []
  readonly property bool archivedView: !!currentList && currentList.archived === true
  readonly property bool fieldActive: editingTitle || editingItemId !== ""
    || editingDueId !== ""
    || (addField && addField.activeFocus) || (titleField && titleField.activeFocus)

  function open(_payloadJson) {
    closingFromHost = false
    opened = true
    if (lists) lists.windowOpen = true
    editingTitle = false
    editingItemId = ""
    editingDueId = ""
    focusedItemId = ""
    pendingDeleteId = ""
    Qt.callLater(function() {
      if (addField && currentList && !currentList.archived) addField.forceActiveFocus()
      else if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    closingFromHost = true
    opened = false
    if (lists) lists.windowOpen = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function startNewList() {
    if (!lists) return
    lists.createList("Untitled")
    editingTitle = true
    Qt.callLater(function() {
      if (titleField) {
        titleField.text = lists.currentList ? lists.currentList.title : "Untitled"
        titleField.forceActiveFocus()
        titleField.selectAll()
      }
    })
  }

  function commitTitle() {
    if (!lists || !currentList) {
      editingTitle = false
      return
    }
    lists.renameList(currentList.id, titleField.text)
    editingTitle = false
    if (addField && !currentList.archived) addField.forceActiveFocus()
  }

  function commitItem(itemId, text) {
    if (!lists) return
    lists.renameItem(itemId, text)
    editingItemId = ""
  }

  function confirmDelete(listObj) {
    if (!listObj) return
    pendingDeleteId = listObj.id
    confirmDialog.message = "Delete “" + listObj.title + "” permanently?"
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Lists"
    color: root.background
    implicitWidth: Style.space(840)
    implicitHeight: Style.space(560)
    minimumSize: Qt.size(Style.space(640), Style.space(420))

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      Keys.priority: confirmDialog.opened ? Keys.BeforeItem : Keys.AfterItem
      Keys.onPressed: function(event) {
        if (confirmDialog.opened && confirmDialog.handleKey(event))
          event.accepted = true
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.fieldActive || confirmDialog.opened

        onCloseRequested: root.requestClose()
        onTextKey: function(t) {
          if (t === "n") root.startNewList()
          else if (t === "a" && currentList && !currentList.archived && addField)
            addField.forceActiveFocus()
          else if (t === "e" && currentList && lists) {
            if (currentList.archived) lists.unarchiveList(currentList.id)
            else lists.archiveList(currentList.id)
          }
        }
        onDeleteRequested: {
          if (currentList && currentList.archived) root.confirmDelete(currentList)
        }
        onTabRequested: function(direction) {
          var id = root.editingItemId || root.focusedItemId
          if (!id || !lists) return
          if (direction < 0) lists.outdentItem(id)
          else lists.indentItem(id)
        }

        Row {
          anchors.fill: parent
          spacing: 0

          // ------------------------------------------------ sidebar
          Item {
            id: sidebar
            width: Style.space(228)
            height: parent.height

            Column {
              id: sidebarHeader
              width: parent.width
              spacing: Style.space(10)
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: Style.spacing.panelPadding
              anchors.leftMargin: Style.spacing.panelPadding
              anchors.rightMargin: Style.space(12)

              Text {
                text: "Lists"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Button {
                width: parent.width
                text: "New list"
                iconText: "+"
                leftAlign: true
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.startNewList()
              }
            }

            Flickable {
              id: sideFlick
              anchors.top: sidebarHeader.bottom
              anchors.topMargin: Style.space(12)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(12)
              contentWidth: width
              contentHeight: sideColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: sideColumn
                x: Style.spacing.panelPadding
                width: sideFlick.width - Style.spacing.panelPadding - Style.space(12)
                spacing: Style.space(2)

                PanelSectionHeader {
                  text: "Open"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  visible: openLists.length > 0
                  width: parent.width
                }

                Repeater {
                  model: openLists
                  delegate: navRow
                }

                Item {
                  visible: openLists.length === 0
                  width: parent.width
                  height: Style.space(28)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "None yet"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Item { width: 1; height: Style.space(10); visible: archivedLists.length > 0 }

                PanelSectionHeader {
                  text: "Archived"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  visible: archivedLists.length > 0
                  width: parent.width
                }

                Repeater {
                  model: archivedLists
                  delegate: navRow
                }
              }
            }

            PanelSeparator {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 1
              implicitHeight: parent.height
              foreground: root.foreground
            }
          }

          // ------------------------------------------------ main
          Item {
            id: main
            width: parent.width - sidebar.width
            height: parent.height
            clip: true

            // Empty — no lists at all
            Column {
              visible: !currentList
              anchors.centerIn: parent
              spacing: Style.space(12)
              width: Math.min(parent.width - Style.space(48), Style.space(320))

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "No lists yet"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Make a checklist. Tick things off. Archive it when you’re done."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "New list"
                iconText: "+"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: root.startNewList()
              }
            }

            Item {
              visible: !!currentList
              anchors.fill: parent
              anchors.margins: Style.spacing.panelPadding

              Row {
                id: titleRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(8)
                height: Math.max(titleLabel.implicitHeight, titleField.implicitHeight,
                  archiveBtn.implicitHeight, Style.space(32))

                Item {
                  width: parent.width - archiveBtn.width
                    - (deleteBtn.visible ? deleteBtn.width + parent.spacing : 0)
                    - parent.spacing
                  height: parent.height

                  Text {
                    id: titleLabel
                    visible: !root.editingTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentList ? currentList.title : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.IBeamCursor
                      onClicked: {
                        root.editingTitle = true
                        titleField.text = currentList ? currentList.title : ""
                        titleField.forceActiveFocus()
                        titleField.selectAll()
                      }
                    }
                  }

                  TextField {
                    id: titleField
                    visible: root.editingTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentList ? currentList.title : ""
                    font.family: root.fontFamily
                    foreground: root.foreground
                    accent: root.accent
                    onAccepted: root.commitTitle()
                    Keys.onEscapePressed: function(event) {
                      event.accepted = true
                      root.editingTitle = false
                    }
                    onActiveFocusChanged: {
                      if (root.editingTitle && !activeFocus) root.commitTitle()
                    }
                  }
                }

                Button {
                  id: archiveBtn
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!currentList
                  text: root.archivedView ? "Unarchive" : "Archive"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  onClicked: {
                    if (!lists || !currentList) return
                    if (currentList.archived) lists.unarchiveList(currentList.id)
                    else lists.archiveList(currentList.id)
                  }
                }

                Button {
                  id: deleteBtn
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.archivedView
                  text: "Delete"
                  bordered: true
                  foreground: Color.urgent
                  accent: Color.urgent
                  onClicked: root.confirmDelete(currentList)
                }
              }

              Text {
                id: progressLabel
                anchors.top: titleRow.bottom
                anchors.topMargin: Style.space(6)
                text: lists && currentItems.length > 0 ? lists.progressFor(currentList) : " "
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: currentItems.length > 0 ? 1 : 0
              }

              Text {
                id: hint
                visible: !!currentList
                anchors.bottom: parent.bottom
                width: parent.width
                text: "n new list   Tab nest   Shift+Tab un-nest   click due   e archive   Esc close"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: addField
                visible: !!currentList && !root.archivedView
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: hint.top
                anchors.bottomMargin: Style.space(8)
                placeholderText: "Add an item"
                font.family: root.fontFamily
                foreground: root.foreground
                accent: root.accent
                onAccepted: {
                  if (!lists) return
                  lists.addItem(text)
                  text = ""
                  forceActiveFocus()
                }
                Keys.onEscapePressed: function(event) {
                  event.accepted = true
                  text = ""
                  keyCatcher.forceActiveFocus()
                }
              }

              Flickable {
                id: itemFlick
                anchors.top: progressLabel.bottom
                anchors.topMargin: Style.space(10)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: addField.visible ? addField.top : hint.top
                anchors.bottomMargin: Style.space(10)
                contentWidth: width
                contentHeight: itemColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                  id: itemColumn
                  width: itemFlick.width
                  spacing: Style.space(2)

                  Repeater {
                    model: currentItems
                    delegate: CheckRow {
                      required property var modelData
                      width: itemColumn.width
                      itemId: modelData.id
                      itemText: modelData.text
                      checked: modelData.checked === true
                      editing: root.editingItemId === modelData.id
                      editingDue: root.editingDueId === modelData.id
                      dimmed: root.archivedView
                      depth: Number(modelData.depth || 0)
                      due: modelData.due || ""
                      dueLabel: modelData.dueLabel || ""
                      dueKind: modelData.dueKind || "none"
                      background: root.background
                      fontFamily: root.fontFamily
                      foreground: root.foreground
                      accent: root.accent
                      onToggled: if (lists) lists.toggleItem(itemId)
                      onEditRequested: {
                        root.editingDueId = ""
                        root.editingItemId = itemId
                      }
                      onDeleteRequested: if (lists) lists.deleteItem(itemId)
                      onRenamed: function(text) { root.commitItem(itemId, text) }
                      onEditCanceled: root.editingItemId = ""
                      onIndentRequested: if (lists) lists.indentItem(itemId)
                      onOutdentRequested: if (lists) lists.outdentItem(itemId)
                      onDueEditRequested: {
                        root.editingItemId = ""
                        root.editingDueId = itemId
                      }
                      onDueChanged: function(due) {
                        if (lists) lists.setDue(itemId, due)
                        root.editingDueId = ""
                      }
                      onDueEditCanceled: root.editingDueId = ""
                      onHovered: function(isHovered) {
                        if (isHovered) root.focusedItemId = itemId
                      }
                    }
                  }

                  Text {
                    visible: currentItems.length === 0
                    width: parent.width
                    topPadding: Style.space(8)
                    text: root.archivedView
                      ? "This archived list is empty."
                      : "Add the first item below."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        background: root.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        cancelText: "Cancel"
        confirmText: "Delete"
        onCanceled: {
          opened = false
          root.pendingDeleteId = ""
        }
        onConfirmed: {
          opened = false
          if (lists && root.pendingDeleteId) lists.deleteList(root.pendingDeleteId)
          root.pendingDeleteId = ""
        }
      }
    }
  }

  Component {
    id: navRow

    CursorSurface {
      id: row
      required property var modelData
      width: sideColumn.width
      implicitHeight: Style.space(32)
      radius: Style.cornerRadius
      current: currentList && currentList.id === modelData.id
      hasCursor: navMouse.containsMouse
      foreground: root.foreground
      accent: root.accent

      MouseArea {
        id: navMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (lists) lists.selectList(modelData.id)
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(4)
        spacing: Style.space(6)

        Text {
          width: parent.width - action.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.title
          color: modelData.archived ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        PanelActionButton {
          id: action
          anchors.verticalCenter: parent.verticalCenter
          iconText: modelData.archived ? "↩" : "↓"
          tooltipText: modelData.archived ? "Unarchive" : "Archive"
          foreground: root.foreground
          opacity: navMouse.containsMouse ? 1 : 0
          enabled: opacity > 0
          onClicked: {
            if (!lists) return
            if (modelData.archived) lists.unarchiveList(modelData.id)
            else lists.archiveList(modelData.id)
          }
        }
      }
    }
  }
}
