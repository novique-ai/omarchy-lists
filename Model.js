.pragma library

// Pure list operations. The QML service is a thin FileView + method
// wrapper around this, and the tests load the same file.

var GLYPH = String.fromCodePoint(0xF0DC9) // nf-md-format-list-checks
var MAX_DEPTH = 6
var _seq = 0
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function nowIso() {
  return new Date().toISOString()
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function newId(prefix) {
  _seq += 1
  var rand = Math.floor(Math.random() * 46656).toString(36)
  return String(prefix || "id") + "_" + Date.now().toString(36) + "_" + _seq.toString(36) + rand
}

function emptyState() {
  return { version: 1, selectedId: "", lists: [] }
}

function normalizeDue(raw) {
  var s = String(raw || "").trim()
  var m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  var month = Number(m[2])
  var day = Number(m[3])
  if (month < 1 || month > 12 || day < 1 || day > 31) return ""
  return m[1] + "-" + m[2] + "-" + m[3]
}

function todayStamp(now) {
  var d = now instanceof Date ? now : (now ? new Date(now) : new Date())
  if (isNaN(d.getTime())) d = new Date()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function addDays(stamp, days) {
  var p = String(stamp || "").split("-")
  var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  d.setDate(d.getDate() + days)
  return todayStamp(d)
}

function dueKind(due, today) {
  var day = normalizeDue(due)
  if (!day) return "none"
  if (day < today) return "overdue"
  if (day === today) return "today"
  return "upcoming"
}

function formatDue(due, today) {
  var day = normalizeDue(due)
  if (!day) return ""
  if (day === today) return "today"
  if (day === addDays(today, 1)) return "tomorrow"
  if (day === addDays(today, -1)) return "yesterday"
  var p = day.split("-")
  var month = MONTHS[Number(p[1]) - 1] || p[1]
  return month + " " + Number(p[2])
}

function normalizeItem(raw) {
  if (!raw || typeof raw !== "object") return null
  var children = []
  var src = Array.isArray(raw.items) ? raw.items : []
  for (var i = 0; i < src.length; i++) {
    var child = normalizeItem(src[i])
    if (child) children.push(child)
  }
  return {
    id: String(raw.id || newId("i")),
    text: String(raw.text || ""),
    checked: !!raw.checked,
    due: normalizeDue(raw.due),
    items: children
  }
}

function normalizeList(raw) {
  if (!raw || typeof raw !== "object") return null
  var items = []
  var src = Array.isArray(raw.items) ? raw.items : []
  for (var i = 0; i < src.length; i++) {
    var item = normalizeItem(src[i])
    if (item) items.push(item)
  }
  var title = String(raw.title || "").trim()
  return {
    id: String(raw.id || newId("l")),
    title: title || "Untitled",
    archived: !!raw.archived,
    createdAt: String(raw.createdAt || nowIso()),
    updatedAt: String(raw.updatedAt || nowIso()),
    items: items
  }
}

function findList(state, id) {
  var lists = state && Array.isArray(state.lists) ? state.lists : []
  var key = String(id || "")
  for (var i = 0; i < lists.length; i++) {
    if (lists[i].id === key) return lists[i]
  }
  return null
}

function findPath(items, id) {
  var key = String(id || "")
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === key) return [{ items: list, index: i }]
    var rest = findPath(list[i].items, key)
    if (rest) return [{ items: list, index: i }].concat(rest)
  }
  return null
}

function openLists(state) {
  var lists = state && Array.isArray(state.lists) ? state.lists : []
  var out = []
  for (var i = 0; i < lists.length; i++) {
    if (!lists[i].archived) out.push(lists[i])
  }
  return out
}

function archivedLists(state) {
  var lists = state && Array.isArray(state.lists) ? state.lists : []
  var out = []
  for (var i = 0; i < lists.length; i++) {
    if (lists[i].archived) out.push(lists[i])
  }
  return out
}

function countItems(items) {
  var n = 0
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    n += 1 + countItems(list[i].items)
  }
  return n
}

function remainingIn(items) {
  var n = 0
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    if (!list[i].checked) n += 1
    n += remainingIn(list[i].items)
  }
  return n
}

function remainingCount(list) {
  if (!list) return 0
  return remainingIn(list.items)
}

function barRemaining(state) {
  var lists = openLists(state)
  var n = 0
  for (var i = 0; i < lists.length; i++) n += remainingCount(lists[i])
  return n
}

function progressLabel(list) {
  var total = list ? countItems(list.items) : 0
  if (total === 0) return ""
  var done = total - remainingCount(list)
  return done + "/" + total
}

function flattenItems(list, now) {
  var today = todayStamp(now)
  var out = []
  function walk(items, depth) {
    var listItems = Array.isArray(items) ? items : []
    for (var i = 0; i < listItems.length; i++) {
      var it = listItems[i]
      var due = it.due || ""
      out.push({
        id: it.id,
        text: it.text,
        checked: !!it.checked,
        due: due,
        dueKind: it.checked ? "none" : dueKind(due, today),
        dueLabel: formatDue(due, today),
        depth: depth,
        childCount: (it.items || []).length
      })
      walk(it.items, depth + 1)
    }
  }
  if (list) walk(list.items, 0)
  return out
}

function firstSelectableId(lists) {
  var i
  for (i = 0; i < lists.length; i++) {
    if (!lists[i].archived) return lists[i].id
  }
  for (i = 0; i < lists.length; i++) {
    if (lists[i].archived) return lists[i].id
  }
  return ""
}

function serializeItem(item) {
  return {
    id: item.id,
    text: item.text,
    checked: !!item.checked,
    due: item.due || "",
    items: (item.items || []).map(serializeItem)
  }
}

function load(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return emptyState()

  var lists = []
  var src = Array.isArray(parsed.lists) ? parsed.lists : []
  for (var i = 0; i < src.length; i++) {
    var list = normalizeList(src[i])
    if (list) lists.push(list)
  }

  var selectedId = String(parsed.selectedId || "")
  if (selectedId && !findList({ lists: lists }, selectedId)) selectedId = ""
  if (!selectedId) selectedId = firstSelectableId(lists)

  return { version: 1, selectedId: selectedId, lists: lists }
}

function serialize(state) {
  var lists = state && Array.isArray(state.lists) ? state.lists : []
  var payload = {
    version: 1,
    selectedId: state && state.selectedId ? String(state.selectedId) : "",
    lists: lists.map(function(list) {
      return {
        id: list.id,
        title: list.title,
        archived: !!list.archived,
        createdAt: list.createdAt,
        updatedAt: list.updatedAt,
        items: (list.items || []).map(serializeItem)
      }
    })
  }
  return JSON.stringify(payload, null, 2) + "\n"
}

function cloneState(state) {
  return load(serialize(state || emptyState()))
}

function touchList(list) {
  list.updatedAt = nowIso()
}

function withList(state, listId, fn) {
  var next = cloneState(state)
  var list = findList(next, listId)
  if (!list) return next
  fn(list)
  touchList(list)
  return next
}

function createList(state, title) {
  var next = cloneState(state)
  var list = normalizeList({
    id: newId("l"),
    title: String(title || "").trim() || "Untitled",
    archived: false,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    items: []
  })
  next.lists.unshift(list)
  next.selectedId = list.id
  return next
}

function renameList(state, id, title) {
  var next = cloneState(state)
  var list = findList(next, id)
  var name = String(title || "").trim()
  if (!list || !name) return next
  list.title = name
  touchList(list)
  return next
}

function selectList(state, id) {
  var next = cloneState(state)
  var list = findList(next, id)
  if (!list) return next
  next.selectedId = list.id
  return next
}

function setArchived(state, id, archived) {
  var next = cloneState(state)
  var list = findList(next, id)
  if (!list) return next
  list.archived = !!archived
  touchList(list)
  if (list.archived && next.selectedId === list.id) {
    next.selectedId = firstSelectableId(next.lists)
  }
  if (!list.archived) next.selectedId = list.id
  return next
}

function deleteList(state, id) {
  var next = cloneState(state)
  var key = String(id || "")
  var lists = []
  for (var i = 0; i < next.lists.length; i++) {
    if (next.lists[i].id !== key) lists.push(next.lists[i])
  }
  next.lists = lists
  if (next.selectedId === key) next.selectedId = firstSelectableId(lists)
  return next
}

function addItem(state, listId, text) {
  return withList(state, listId, function(list) {
    var value = String(text || "").trim()
    if (!value) return
    list.items.push(normalizeItem({
      id: newId("i"),
      text: value,
      checked: false,
      due: "",
      items: []
    }))
  })
}

function addChild(state, listId, parentId, text) {
  var value = String(text || "").trim()
  if (!value) return cloneState(state)
  return withList(state, listId, function(list) {
    var path = findPath(list.items, parentId)
    if (!path) return
    if (path.length >= MAX_DEPTH) return
    var loc = path[path.length - 1]
    loc.items[loc.index].items.push(normalizeItem({
      id: newId("i"),
      text: value,
      checked: false,
      due: "",
      items: []
    }))
  })
}

function toggleItem(state, listId, itemId) {
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items[loc.index].checked = !loc.items[loc.index].checked
  })
}

function renameItem(state, listId, itemId, text) {
  var value = String(text || "").trim()
  if (!value) return deleteItem(state, listId, itemId)
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items[loc.index].text = value
  })
}

function deleteItem(state, listId, itemId) {
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items.splice(loc.index, 1)
  })
}

function setDue(state, listId, itemId, due) {
  var nextDue = String(due || "").trim()
  if (nextDue !== "" && !normalizeDue(nextDue)) return cloneState(state)
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items[loc.index].due = normalizeDue(nextDue)
  })
}

function indentItem(state, listId, itemId) {
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    if (loc.index === 0) return
    if (path.length >= MAX_DEPTH) return
    var item = loc.items.splice(loc.index, 1)[0]
    loc.items[loc.index - 1].items.push(item)
  })
}

function outdentItem(state, listId, itemId) {
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path || path.length < 2) return
    var loc = path[path.length - 1]
    var parentLoc = path[path.length - 2]
    var item = loc.items.splice(loc.index, 1)[0]
    parentLoc.items.splice(parentLoc.index + 1, 0, item)
  })
}

function barTooltip(state) {
  var remaining = barRemaining(state)
  if (remaining <= 0) return "Lists"
  if (remaining === 1) return "Lists — 1 remaining"
  return "Lists — " + remaining + " remaining"
}
