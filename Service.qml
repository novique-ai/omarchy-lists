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
  property int overdueCount: 0
  property int revision: 0
  property bool loaded: false
  property bool windowOpen: false
  property bool writing: false
  property bool hideCompleted: false
  property string query: ""
  property var past: []

  readonly property string tooltip: Model.barTooltip(store)
  readonly property string glyph: Model.GLYPH

  onQueryChanged: project()

  function project() {
    var state = store && typeof store === "object" ? store : Model.emptyState()
    var q = String(query || "")
    var searching = q.trim().length > 0
    var open = Model.openLists(state)
    var archived = Model.archivedLists(state)
    var shownOpen = []
    var shownArchived = []
    var i
    for (i = 0; i < open.length; i++) {
      if (Model.listMatches(open[i], q)) shownOpen.push(open[i])
    }
    for (i = 0; i < archived.length; i++) {
      if (Model.listMatches(archived[i], q)) shownArchived.push(archived[i])
    }
    openLists = shownOpen
    archivedLists = shownArchived
    currentList = Model.findList(state, state.selectedId)
    currentItems = Model.flattenItems(currentList, new Date(), {
      hideCompleted: !!state.hideCompleted && !searching,
      expandAll: searching
    })
    hideCompleted = !!state.hideCompleted
    remainingCount = Model.barRemaining(state)
    overdueCount = Model.attention(state).overdue
    revision++
  }

  function remember() {
    if (!loaded) return
    var snapshot = Model.serialize(store)
    var next = past && past.slice ? past.slice() : []
    if (next.length && next[next.length - 1] === snapshot) return
    next.push(snapshot)
    if (next.length > 40) next.splice(0, next.length - 40)
    past = next
  }

  function apply(next, persist) {
    var state = next && typeof next === "object" ? next : Model.emptyState()
    if (persist !== false && loaded) {
      var prev = Model.serialize(store)
      var incoming = Model.serialize(state)
      if (prev !== incoming) remember()
    }
    store = state
    project()
    if (persist !== false && loaded) saveTimer.restart()
  }

  function undo() {
    if (!past || past.length === 0) return
    var next = past.slice()
    var raw = next.pop()
    past = next
    store = Model.load(raw)
    project()
    if (loaded) saveTimer.restart()
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

  function toggleCollapsed(itemId) {
    if (!store.selectedId) return
    var list = Model.findList(store, store.selectedId)
    var path = list ? Model.findPath(list.items, itemId) : null
    if (!path) return
    var loc = path[path.length - 1]
    var collapsed = !loc.items[loc.index].collapsed
    apply(Model.setCollapsed(store, store.selectedId, itemId, collapsed))
  }

  function togglePinned(id) {
    var list = Model.findList(store, id)
    if (!list) return
    apply(Model.setPinned(store, id, !list.pinned))
  }

  function toggleHideCompleted() {
    apply(Model.toggleHideCompleted(store))
  }

  function clearCompleted() {
    if (!store.selectedId) return
    apply(Model.clearCompleted(store, store.selectedId))
  }

  function duplicateList(id) {
    apply(Model.duplicateList(store, id))
  }

  function moveItem(itemId, delta) {
    if (!store.selectedId) return
    apply(Model.moveItem(store, store.selectedId, itemId, delta))
  }

  function moveItemTo(itemId, targetId, place) {
    if (!store.selectedId) return
    apply(Model.moveItemTo(store, store.selectedId, itemId, targetId, place))
  }

  function canMoveItem(itemId, targetId, place) {
    if (!store.selectedId) return false
    return Model.canMoveItem(Model.findList(store, store.selectedId), itemId, targetId, place)
  }

  function reorderList(id, targetId, after) {
    apply(Model.reorderList(store, id, targetId, after))
  }

  function moveList(id, delta) {
    apply(Model.moveList(store, id, delta))
  }

  function progressFor(list) {
    return Model.progressLabel(list)
  }

  function remainingFor(list) {
    return Model.remainingCount(list)
  }

  function completedFor(list) {
    return Model.completedCount(list)
  }

  function progressParts(list) {
    var total = Model.countItems(list ? list.items : [])
    var done = total - Model.remainingCount(list)
    return { total: total, done: done }
  }

  Timer {
    id: saveTimer
    interval: 180
    onTriggered: directoryMaker.running = true
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.loaded
    onTriggered: root.project()
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
