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
  property string pendingAction: ""
  property bool helpOpen: false
  property bool returnEdits: false

  property string dragKind: ""
  property string dragId: ""
  property string dragLabel: ""
  property bool dragArchived: false
  property bool dragActive: false
  property string dropId: ""
  property string dropPlace: ""
  property real dropY: 0
  property real dropH: 0
  property real ghostX: 0
  property real ghostY: 0

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
    || (searchField && searchField.activeFocus)
  readonly property int doneCount: {
    var rev = lists ? lists.revision : 0
    if (!lists || !currentList || rev < 0) return 0
    return lists.progressParts(currentList).done
  }
  readonly property int totalCount: {
    var rev = lists ? lists.revision : 0
    if (!lists || !currentList || rev < 0) return 0
    return lists.progressParts(currentList).total
  }
  readonly property int completedCount: {
    var rev = lists ? lists.revision : 0
    if (!lists || !currentList || rev < 0) return 0
    return lists.completedFor(currentList)
  }
  readonly property bool hideCompleted: !!(lists && lists.hideCompleted)

  function clearDrag() {
    dragKind = ""
    dragId = ""
    dragLabel = ""
    dragArchived = false
    dragActive = false
    dropId = ""
    dropPlace = ""
  }

  function childRows(column, idName) {
    var rows = []
    if (!column) return rows
    var kids = column.children
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      var id = ""
      if (child && idName === "listId") id = child.listId
      else if (child && idName === "itemId") id = child.itemId
      if (id) rows.push(child)
    }
    return rows
  }

  function rowAt(column, y, idName) {
    var rows = childRows(column, idName)
    var found = null
    for (var i = 0; i < rows.length; i++) {
      var child = rows[i]
      if (y >= child.y && y < child.y + child.height) found = child
    }
    return found
  }

  function moveFocus(dy) {
    var items = currentItems || []
    if (!items.length) return
    var idx = -1
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === focusedItemId) { idx = i; break }
    }
    var next = idx < 0 ? (dy < 0 ? items.length - 1 : 0) : idx + dy
    if (next < 0) next = 0
    if (next >= items.length) next = items.length - 1
    focusedItemId = items[next].id
    Qt.callLater(root.revealFocused)
  }

  function revealFocused() {
    if (!itemColumn || !itemFlick || !focusedItemId) return
    var row = rowAt(itemColumn, 0, "itemId")
    var kids = itemColumn.children
    var target = null
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] && kids[i].itemId === focusedItemId) { target = kids[i]; break }
    }
    if (!target) return
    void row
    var top = target.y
    var bottom = target.y + target.height
    if (top < itemFlick.contentY) itemFlick.contentY = Math.max(0, top)
    else if (bottom > itemFlick.contentY + itemFlick.height)
      itemFlick.contentY = Math.max(0, bottom - itemFlick.height)
  }

  function beginListDrag(listId, label, archived) {
    dragKind = "list"
    dragId = listId
    dragLabel = label
    dragArchived = !!archived
    dragActive = true
    dropId = ""
  }

  function updateListDrag(y, gx, gy) {
    ghostX = gx
    ghostY = gy
    dragActive = true
    var row = rowAt(sideColumn, y, "listId")
    if (!row) {
      var rows = childRows(sideColumn, "listId")
      var fallback = null
      for (var i = 0; i < rows.length; i++) {
        if (!!rows[i].rowArchived !== dragArchived) continue
        if (rows[i].y <= y) fallback = rows[i]
      }
      if (!fallback && rows.length) {
        for (var j = 0; j < rows.length; j++) {
          if (!!rows[j].rowArchived === dragArchived) { fallback = rows[j]; break }
        }
      }
      if (!fallback || fallback.listId === dragId) {
        dropId = ""
        return
      }
      row = fallback
    }
    if (row.listId === dragId || !!row.rowArchived !== dragArchived) {
      dropId = ""
      return
    }
    var place = (y - row.y) > row.height / 2 ? "after" : "before"
    dropId = row.listId
    dropPlace = place
    dropH = row.height
    dropY = place === "after" ? row.y + row.height : row.y
  }

  function finishListDrag() {
    if (dragActive && dragKind === "list" && dropId && lists)
      lists.reorderList(dragId, dropId, dropPlace === "after")
    clearDrag()
  }

  function beginItemDrag(itemId, label) {
    dragKind = "item"
    dragId = itemId
    dragLabel = label
    dragActive = true
    dropId = ""
    focusedItemId = itemId
  }

  function updateItemDrag(y, gx, gy) {
    ghostX = gx
    ghostY = gy
    dragActive = true
    var row = rowAt(itemColumn, y, "itemId")
    if (!row || !lists) {
      dropId = ""
      return
    }
    var local = y - row.y
    var place = "inside"
    if (local < row.height * 0.28) place = "before"
    else if (local > row.height * 0.72) place = "after"
    if (!lists.canMoveItem(dragId, row.itemId, place)) {
      dropId = ""
      return
    }
    dropId = row.itemId
    dropPlace = place
    dropH = row.height
    dropY = place === "after" ? row.y + row.height : row.y
  }

  function finishItemDrag() {
    if (dragActive && dragKind === "item" && dropId && lists)
      lists.moveItemTo(dragId, dropId, dropPlace)
    clearDrag()
  }

  function open(_payloadJson) {
    closingFromHost = false
    opened = true
    if (lists) lists.windowOpen = true
    editingTitle = false
    editingItemId = ""
    editingDueId = ""
    focusedItemId = ""
    pendingDeleteId = ""
    pendingAction = ""
    helpOpen = false
    clearDrag()
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
    pendingAction = "delete"
    pendingDeleteId = listObj.id
    confirmDialog.confirmText = "Delete"
    confirmDialog.message = "Delete “" + listObj.title + "” permanently?"
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function confirmClear() {
    if (!currentList) return
    pendingAction = "clear"
    pendingDeleteId = ""
    confirmDialog.confirmText = "Clear"
    confirmDialog.message = "Remove checked items in this list? Nested items under them go too."
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Lists"
    color: root.background
    implicitWidth: Style.space(864)
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
        if (confirmDialog.opened && confirmDialog.handleKey(event)) {
          event.accepted = true
          return
        }
        var ctrl = event.modifiers & Qt.ControlModifier
        if (ctrl && event.key === Qt.Key_Z && !root.fieldActive && lists) {
          event.accepted = true
          lists.undo()
          return
        }
        if (ctrl && event.key === Qt.Key_F && searchField) {
          event.accepted = true
          searchField.forceActiveFocus()
          searchField.selectAll()
        }
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.fieldActive || confirmDialog.opened

        onCloseRequested: {
          if (root.helpOpen) root.helpOpen = false
          else root.requestClose()
        }
        onMoveRequested: function(dx, dy) {
          if (root.helpOpen) return
          var id = root.focusedItemId
          if (dx !== 0 && id && lists) {
            if (dx < 0) lists.outdentItem(id)
            else lists.indentItem(id)
            return
          }
          if (dy !== 0) root.moveFocus(dy)
        }
        onReturnRequested: {
          root.returnEdits = true
          if (root.helpOpen || !root.focusedItemId || root.archivedView) return
          root.editingDueId = ""
          root.editingItemId = root.focusedItemId
        }
        onActivateRequested: {
          if (root.returnEdits) {
            root.returnEdits = false
            return
          }
          if (root.helpOpen || !root.focusedItemId || !lists || root.archivedView) return
          lists.toggleItem(root.focusedItemId)
        }
        onTextKey: function(t) {
          if (t === "?") {
            root.helpOpen = !root.helpOpen
            return
          }
          if (root.helpOpen) return
          if (t === "n") root.startNewList()
          else if (t === "/" && searchField) {
            searchField.forceActiveFocus()
            searchField.selectAll()
          }
          else if (t === "a" && currentList && !currentList.archived && addField)
            addField.forceActiveFocus()
          else if (t === "e" && currentList && lists) {
            if (currentList.archived) lists.unarchiveList(currentList.id)
            else lists.archiveList(currentList.id)
          }
          else if (t === "u" && lists) lists.undo()
          else if (t === "p" && currentList && lists) lists.togglePinned(currentList.id)
          else if (t === "d" && currentList && lists) lists.duplicateList(currentList.id)
          else if (t === "c" && currentList && !currentList.archived) root.confirmClear()
          else if (t === "v" && lists) lists.toggleHideCompleted()
          else if ((t === "[" || t === "]") && currentList && lists)
            lists.moveList(currentList.id, t === "]" ? 1 : -1)
          else if ((t === "J" || t === "K") && root.focusedItemId && lists)
            lists.moveItem(root.focusedItemId, t === "J" ? 1 : -1)
          else if (t === "z" && root.focusedItemId && lists)
            lists.toggleCollapsed(root.focusedItemId)
        }
        onDeleteRequested: {
          if (root.focusedItemId && lists) lists.deleteItem(root.focusedItemId)
          else if (currentList && currentList.archived) root.confirmDelete(currentList)
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
            width: Style.space(252)
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

              TextField {
                id: searchField
                width: parent.width
                placeholderText: "Search"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                foreground: root.foreground
                accent: root.accent
                onTextChanged: if (lists) lists.query = text
                onAccepted: keyCatcher.forceActiveFocus()
                Keys.onEscapePressed: function(event) {
                  event.accepted = true
                  text = ""
                  keyCatcher.forceActiveFocus()
                }
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
                    text: searchField.text.trim() !== "" ? "No matches" : "None yet"
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

            Item {
              anchors.fill: sideFlick
              z: 4
              clip: true
              enabled: false

              Rectangle {
                visible: root.dragKind === "list" && root.dropId !== ""
                x: sideColumn.x
                y: root.dropY - sideFlick.contentY
                width: sideColumn.width
                height: Style.space(2)
                color: root.accent
              }
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
                text: root.totalCount > 0 ? (lists ? lists.progressFor(currentList) : "") : " "
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: root.totalCount > 0 ? 1 : 0
              }

              Rectangle {
                id: progressTrack
                anchors.top: progressLabel.bottom
                anchors.topMargin: Style.space(6)
                width: parent.width
                height: root.totalCount > 0 ? Style.space(3) : 0
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                visible: root.totalCount > 0

                Rectangle {
                  width: progressTrack.width * (root.totalCount > 0 ? root.doneCount / root.totalCount : 0)
                  height: parent.height
                  radius: parent.radius
                  color: root.accent
                }
              }

              Row {
                id: toolRow
                anchors.top: progressTrack.bottom
                anchors.topMargin: Style.space(8)
                spacing: Style.space(6)
                visible: !!currentList

                Button {
                  text: root.hideCompleted ? "Show done" : "Hide done"
                  bordered: true
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  foreground: root.foreground
                  accent: root.accent
                  visible: root.totalCount > 0
                  onClicked: if (lists) lists.toggleHideCompleted()
                }

                Button {
                  text: "Clear done"
                  bordered: true
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  foreground: root.foreground
                  accent: root.accent
                  visible: root.completedCount > 0 && !root.archivedView
                  onClicked: root.confirmClear()
                }

                Button {
                  text: "Copy"
                  bordered: true
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  foreground: root.foreground
                  accent: root.accent
                  onClicked: if (lists && currentList) lists.duplicateList(currentList.id)
                }
              }

              Text {
                id: hint
                visible: !!currentList
                anchors.bottom: parent.bottom
                width: parent.width
                text: "drag ⋮ to reorder   j/k move   space check   / search   ? shortcuts"
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
                anchors.top: toolRow.bottom
                anchors.topMargin: Style.space(10)
                visible: !root.helpOpen
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
                      childCount: Number(modelData.childCount || 0)
                      collapsed: modelData.collapsed === true
                      focused: root.focusedItemId === modelData.id
                      dragging: root.dragActive && root.dragKind === "item" && root.dragId === modelData.id
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
                      onDueSubmitted: function(due) {
                        if (lists) lists.setDue(itemId, due)
                        root.editingDueId = ""
                      }
                      onDueEditCanceled: root.editingDueId = ""
                      onCollapseRequested: if (lists) lists.toggleCollapsed(itemId)
                      onRowHovered: function(isHovered) {
                        if (isHovered) root.focusedItemId = itemId
                      }
                      onGripStarted: root.beginItemDrag(itemId, modelData.text)
                      onGripMoved: function(x, y) {
                        var inColumn = mapToItem(itemColumn, x, y)
                        var inWindow = mapToItem(focusScope, x, y)
                        root.updateItemDrag(inColumn.y, inWindow.x, inWindow.y)
                      }
                      onGripReleased: root.finishItemDrag()
                      onGripCanceled: root.clearDrag()
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

              Item {
                anchors.fill: itemFlick
                z: 4
                clip: true
                enabled: false
                visible: !root.helpOpen

                Rectangle {
                  visible: root.dragKind === "item" && root.dropPlace === "inside" && root.dropId !== ""
                  x: 0
                  y: root.dropY - itemFlick.contentY
                  width: itemFlick.width
                  height: root.dropH
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                }

                Rectangle {
                  visible: root.dragKind === "item" && root.dropId !== "" && root.dropPlace !== "inside"
                  x: 0
                  y: root.dropY - itemFlick.contentY
                  width: itemFlick.width
                  height: Style.space(2)
                  color: root.accent
                }
              }

              Flickable {
                id: helpFlick
                visible: root.helpOpen && !!currentList
                anchors.top: toolRow.bottom
                anchors.topMargin: Style.space(10)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: hint.top
                anchors.bottomMargin: Style.space(10)
                contentWidth: width
                contentHeight: helpText.implicitHeight
                clip: true

                Text {
                  id: helpText
                  width: helpFlick.width
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  lineHeight: 1.35
                  wrapMode: Text.WordWrap
                  text: "Drag the ⋮ grip to reorder. On an item, drop on the top or bottom edge to place it there, or on the middle to nest it.\n\n"
                    + "j k or arrows    move between items\n"
                    + "h l              un-nest / nest\n"
                    + "Space            check\n"
                    + "Enter            rename\n"
                    + "x                remove item\n"
                    + "J K              move item down / up\n"
                    + "[ ]              move this list up / down\n"
                    + "Tab              nest the focused item\n"
                    + "z                fold or unfold\n"
                    + "n                new list\n"
                    + "a                add an item\n"
                    + "/ or Ctrl+F      search\n"
                    + "e                archive\n"
                    + "p                pin\n"
                    + "d                duplicate\n"
                    + "c                clear completed\n"
                    + "v                hide completed\n"
                    + "u or Ctrl+Z      undo\n"
                    + "?                this list\n"
                    + "Esc              close\n\n"
                    + "Due dates take a day (2026-09-26), today, tomorrow, yesterday, week, or +3."
                }
              }
            }
          }
        }
      }

      Rectangle {
        id: dragGhost
        visible: root.dragActive && root.dragLabel !== ""
        x: Math.max(Style.space(8), Math.min(root.ghostX + Style.space(12), parent.width - width - Style.space(8)))
        y: Math.max(Style.space(8), Math.min(root.ghostY + Style.space(8), parent.height - height - Style.space(8)))
        z: 20
        width: Math.min(Style.space(240), dragGhostText.implicitWidth + Style.space(20))
        height: Style.space(32)
        radius: Style.cornerRadius
        color: root.background
        border.width: 1
        border.color: root.accent

        Text {
          id: dragGhostText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, Style.space(220))
          text: root.dragLabel
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
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
          root.pendingAction = ""
        }
        onConfirmed: {
          opened = false
          if (lists && root.pendingAction === "clear") lists.clearCompleted()
          else if (lists && root.pendingDeleteId) lists.deleteList(root.pendingDeleteId)
          root.pendingDeleteId = ""
          root.pendingAction = ""
        }
      }
    }
  }

  Component {
    id: navRow

    CursorSurface {
      id: row
      required property var modelData
      property string listId: modelData.id
      property bool rowArchived: modelData.archived === true
      readonly property int remain: {
        var rev = lists ? lists.revision : 0
        if (!lists || rev < 0) return 0
        return lists.remainingFor(modelData)
      }

      width: sideColumn.width
      implicitHeight: Style.space(32)
      radius: Style.cornerRadius
      current: currentList && currentList.id === modelData.id
      hasCursor: navMouse.containsMouse
      foreground: root.foreground
      accent: root.accent
      opacity: root.dragActive && root.dragKind === "list" && root.dragId === modelData.id ? 0.35 : 1

      MouseArea {
        id: navMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (lists) lists.selectList(modelData.id)
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(4)
        anchors.rightMargin: Style.space(4)
        spacing: Style.space(4)

        Item {
          id: listGrip
          width: Style.space(14)
          height: parent.height

          Text {
            anchors.centerIn: parent
            text: "⋮"
            color: root.foreground
            opacity: listGripArea.pressed || navMouse.containsMouse ? 0.85 : 0.28
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: listGripArea
            anchors.fill: parent
            anchors.margins: -4
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
                root.beginListDrag(modelData.id, modelData.title, modelData.archived === true)
              }
              var local = mapToItem(row, mouse.x, mouse.y)
              var inColumn = row.mapToItem(sideColumn, local.x, local.y)
              var inWindow = row.mapToItem(focusScope, local.x, local.y)
              root.updateListDrag(inColumn.y, inWindow.x, inWindow.y)
            }
            onReleased: {
              if (armed) root.finishListDrag()
              armed = false
            }
            onCanceled: {
              armed = false
              root.clearDrag()
            }
          }
        }

        Text {
          id: titleText
          width: Math.max(0, parent.width - listGrip.width - pinBtn.width - action.width
            - (countText.visible ? countText.implicitWidth : 0)
            - parent.spacing * (countText.visible ? 4 : 3))
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.title
          color: modelData.archived ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: countText
          anchors.verticalCenter: parent.verticalCenter
          visible: row.remain > 0
          text: row.remain > 0 ? String(row.remain) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelActionButton {
          id: pinBtn
          anchors.verticalCenter: parent.verticalCenter
          iconText: modelData.pinned ? "★" : "☆"
          tooltipText: modelData.pinned ? "Unpin" : "Pin"
          foreground: root.foreground
          opacity: modelData.pinned || navMouse.containsMouse ? 1 : 0
          enabled: opacity > 0
          onClicked: if (lists) lists.togglePinned(modelData.id)
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
