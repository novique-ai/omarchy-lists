import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless owner of list state. The window and the bar widget both read
// from here so a tick in the window is the same data the tooltip counts.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "novique.lists"

  readonly property string dataDir: {
    var state = Quickshell.env("XDG_STATE_HOME")
    var home = Quickshell.env("HOME") || ""
    if (state && String(state).length > 0)
      return String(state) + "/omarchy/lists"
    return home + "/.local/state/omarchy/lists"
  }
  readonly property string dataPath: dataDir + "/lists.json"

  property var store: Model.emptyState()
  property var openLists: []
  property var archivedLists: []
  property var currentList: null
  property var currentItems: []
  property int remainingCount: 0
  property int revision: 0
  property bool loaded: false
  property bool windowOpen: false
  property bool writing: false

  readonly property string tooltip: Model.barTooltip(store)
  readonly property string glyph: Model.GLYPH

  function apply(next, persist) {
    var state = next && typeof next === "object" ? next : Model.emptyState()
    store = state
    openLists = Model.openLists(state)
    archivedLists = Model.archivedLists(state)
    currentList = Model.findList(state, state.selectedId)
    currentItems = Model.flattenItems(currentList)
    remainingCount = Model.barRemaining(state)
    revision++
    if (persist !== false && loaded) saveTimer.restart()
  }

  function createList(title) {
    apply(Model.createList(store, title))
    return store.selectedId
  }

  function renameList(id, title) {
    apply(Model.renameList(store, id, title))
  }

  function selectList(id) {
    apply(Model.selectList(store, id))
  }

  function archiveList(id) {
    apply(Model.setArchived(store, id, true))
  }

  function unarchiveList(id) {
    apply(Model.setArchived(store, id, false))
  }

  function deleteList(id) {
    apply(Model.deleteList(store, id))
  }

  function addItem(text) {
    if (!store.selectedId) return
    apply(Model.addItem(store, store.selectedId, text))
  }

  function toggleItem(itemId) {
    if (!store.selectedId) return
    apply(Model.toggleItem(store, store.selectedId, itemId))
  }

  function renameItem(itemId, text) {
    if (!store.selectedId) return
    apply(Model.renameItem(store, store.selectedId, itemId, text))
  }

  function deleteItem(itemId) {
    if (!store.selectedId) return
    apply(Model.deleteItem(store, store.selectedId, itemId))
  }

  function addChild(parentId, text) {
    if (!store.selectedId) return
    apply(Model.addChild(store, store.selectedId, parentId, text))
  }

  function indentItem(itemId) {
    if (!store.selectedId) return
    apply(Model.indentItem(store, store.selectedId, itemId))
  }

  function outdentItem(itemId) {
    if (!store.selectedId) return
    apply(Model.outdentItem(store, store.selectedId, itemId))
  }

  function setDue(itemId, due) {
    if (!store.selectedId) return
    apply(Model.setDue(store, store.selectedId, itemId, due))
  }

  function progressFor(list) {
    return Model.progressLabel(list)
  }

  Timer {
    id: saveTimer
    interval: 180
    onTriggered: directoryMaker.running = true
  }

  Process {
    id: directoryMaker
    command: ["mkdir", "-p", root.dataDir]
    onExited: {
      root.writing = true
      file.setText(Model.serialize(root.store))
    }
  }

  FileView {
    id: file
    path: root.dataPath
    atomicWrites: true
    printErrors: false
    watchChanges: false

    onLoaded: {
      if (root.writing) {
        root.writing = false
        return
      }
      root.apply(Model.load(text()), false)
      root.loaded = true
    }
    onLoadFailed: {
      root.apply(Model.emptyState(), false)
      root.loaded = true
    }
    onSaved: root.writing = false
    onSaveFailed: function(error) {
      root.writing = false
      console.warn("novique.lists: save failed:", error)
    }
  }
}
