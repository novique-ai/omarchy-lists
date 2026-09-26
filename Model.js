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
  return { version: 1, selectedId: "", hideCompleted: false, lists: [] }
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

// Blank clears. A calendar day is stored as-is. Words and +N land on a
// local day. Anything else is null so the caller can leave the old value.
function parseDueInput(raw, now) {
  var original = String(raw || "").trim()
  if (!original) return ""
  var iso = normalizeDue(original)
  if (iso) return iso
  var s = original.toLowerCase()
  var day = todayStamp(now)
  if (s === "today" || s === "tod") return day
  if (s === "tomorrow" || s === "tom") return addDays(day, 1)
  if (s === "yesterday") return addDays(day, -1)
  if (s === "week" || s === "next week" || s === "+7" || s === "7d") return addDays(day, 7)
  var match = s.match(/^\+(\d{1,3})d?$/)
  if (match) {
    var n = Number(match[1])
    if (n > 0 && n <= 366) return addDays(day, n)
  }
  return null
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
    collapsed: !!raw.collapsed,
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
    pinned: !!raw.pinned,
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

function flattenItems(list, now, options) {
  var today = todayStamp(now)
  var opts = options || {}
  var hideCompleted = !!opts.hideCompleted
  var expandAll = !!opts.expandAll
  var out = []
  function walk(items, depth) {
    var listItems = Array.isArray(items) ? items : []
    for (var i = 0; i < listItems.length; i++) {
      var it = listItems[i]
      var due = it.due || ""
      var hide = hideCompleted && !!it.checked
      if (!hide) {
        out.push({
          id: it.id,
          text: it.text,
          checked: !!it.checked,
          due: due,
          dueKind: it.checked ? "none" : dueKind(due, today),
          dueLabel: formatDue(due, today),
          depth: depth,
          collapsed: !!it.collapsed,
          childCount: (it.items || []).length
        })
      }
      if (it.collapsed && !expandAll) continue
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
    collapsed: !!item.collapsed,
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

  return {
    version: 1,
    selectedId: selectedId,
    hideCompleted: !!parsed.hideCompleted,
    lists: lists
  }
}

function serialize(state) {
  var lists = state && Array.isArray(state.lists) ? state.lists : []
  var payload = {
    version: 1,
    selectedId: state && state.selectedId ? String(state.selectedId) : "",
    hideCompleted: !!(state && state.hideCompleted),
    lists: lists.map(function(list) {
      return {
        id: list.id,
        title: list.title,
        archived: !!list.archived,
        pinned: !!list.pinned,
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

function setDue(state, listId, itemId, due, now) {
  var parsed = parseDueInput(due, now)
  if (parsed === null) return cloneState(state)
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items[loc.index].due = parsed
  })
}

function setCollapsed(state, listId, itemId, collapsed) {
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    loc.items[loc.index].collapsed = !!collapsed
  })
}

function setPinned(state, id, pinned) {
  var next = cloneState(state)
  var list = findList(next, id)
  if (!list) return next
  list.pinned = !!pinned
  touchList(list)
  return next
}

function toggleHideCompleted(state) {
  var next = cloneState(state)
  next.hideCompleted = !next.hideCompleted
  return next
}

function listMatches(list, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  if (!list) return false
  if (String(list.title || "").toLowerCase().indexOf(q) !== -1) return true
  return treeHasText(list.items, q)
}

function treeHasText(items, q) {
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].text || "").toLowerCase().indexOf(q) !== -1) return true
    if (treeHasText(list[i].items, q)) return true
  }
  return false
}

function completedIn(items) {
  var n = 0
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].checked) n += 1
    n += completedIn(list[i].items)
  }
  return n
}

function completedCount(list) {
  if (!list) return 0
  return completedIn(list.items)
}

function pruneChecked(items) {
  var out = []
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].checked) continue
    list[i].items = pruneChecked(list[i].items)
    out.push(list[i])
  }
  return out
}

function clearCompleted(state, listId) {
  return withList(state, listId, function(list) {
    list.items = pruneChecked(list.items)
  })
}

function cloneItemNewIds(item) {
  var children = []
  var src = item && Array.isArray(item.items) ? item.items : []
  for (var i = 0; i < src.length; i++) children.push(cloneItemNewIds(src[i]))
  return normalizeItem({
    text: item ? item.text : "",
    checked: item ? item.checked : false,
    due: item ? item.due : "",
    collapsed: item ? item.collapsed : false,
    items: children
  })
}

function duplicateList(state, id) {
  var next = cloneState(state)
  var src = findList(next, id)
  if (!src) return next
  var idx = -1
  for (var i = 0; i < next.lists.length; i++) {
    if (next.lists[i].id === src.id) { idx = i; break }
  }
  var copy = normalizeList({
    id: newId("l"),
    title: src.title + " copy",
    archived: false,
    pinned: !!src.pinned,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    items: (src.items || []).map(cloneItemNewIds)
  })
  next.lists.splice(idx + 1, 0, copy)
  next.selectedId = copy.id
  return next
}

function subtreeDepth(item) {
  var items = item && Array.isArray(item.items) ? item.items : []
  var max = 1
  for (var i = 0; i < items.length; i++) {
    max = Math.max(max, 1 + subtreeDepth(items[i]))
  }
  return max
}

function containsId(item, id) {
  if (!item) return false
  if (item.id === id) return true
  var kids = item.items || []
  for (var i = 0; i < kids.length; i++) {
    if (containsId(kids[i], id)) return true
  }
  return false
}

function canMoveItem(list, itemId, targetId, place) {
  if (!list || !itemId || !targetId || itemId === targetId) return false
  if (place !== "before" && place !== "after" && place !== "inside") return false
  var srcPath = findPath(list.items, itemId)
  var dstPath = findPath(list.items, targetId)
  if (!srcPath || !dstPath) return false
  var src = srcPath[srcPath.length - 1]
  var node = src.items[src.index]
  if (containsId(node, targetId)) return false
  var parentPathLen = place === "inside" ? dstPath.length : dstPath.length - 1
  if (parentPathLen + subtreeDepth(node) > MAX_DEPTH) return false
  return true
}

function moveItem(state, listId, itemId, delta) {
  var step = delta < 0 ? -1 : 1
  return withList(state, listId, function(list) {
    var path = findPath(list.items, itemId)
    if (!path) return
    var loc = path[path.length - 1]
    var dest = loc.index + step
    if (dest < 0 || dest >= loc.items.length) return
    var item = loc.items.splice(loc.index, 1)[0]
    loc.items.splice(dest, 0, item)
  })
}

function moveItemTo(state, listId, itemId, targetId, place) {
  var current = findList(state, listId)
  if (!canMoveItem(current, itemId, targetId, place)) return cloneState(state)
  return withList(state, listId, function(list) {
    var srcPath = findPath(list.items, itemId)
    if (!srcPath) return
    var src = srcPath[srcPath.length - 1]
    var node = src.items.splice(src.index, 1)[0]
    var dstPath = findPath(list.items, targetId)
    if (!dstPath) {
      src.items.splice(src.index, 0, node)
      return
    }
    if (place === "inside") {
      var parent = dstPath[dstPath.length - 1]
      var parentItem = parent.items[parent.index]
      parentItem.collapsed = false
      parentItem.items.push(node)
      return
    }
    var loc = dstPath[dstPath.length - 1]
    var idx = loc.index + (place === "after" ? 1 : 0)
    loc.items.splice(idx, 0, node)
  })
}

function reorderList(state, id, targetId, after) {
  var next = cloneState(state)
  var from = -1
  var to = -1
  var i
  for (i = 0; i < next.lists.length; i++) {
    if (next.lists[i].id === id) from = i
    if (next.lists[i].id === targetId) to = i
  }
  if (from < 0 || to < 0 || from === to) return next
  if (!!next.lists[from].archived !== !!next.lists[to].archived) return next
  var moving = next.lists.splice(from, 1)[0]
  var dest = 0
  for (i = 0; i < next.lists.length; i++) {
    if (next.lists[i].id === targetId) { dest = i; break }
  }
  if (after) dest += 1
  next.lists.splice(dest, 0, moving)
  touchList(moving)
  return next
}

function moveList(state, id, delta) {
  var moving = findList(state, id)
  if (!moving) return cloneState(state)
  var group = []
  var lists = state.lists || []
  for (var i = 0; i < lists.length; i++) {
    if (!!lists[i].archived === !!moving.archived) group.push(lists[i].id)
  }
  var idx = group.indexOf(String(id))
  var step = delta < 0 ? -1 : 1
  var dest = idx + step
  if (idx < 0 || dest < 0 || dest >= group.length) return cloneState(state)
  return reorderList(state, id, group[dest], step > 0)
}

function attention(state, now) {
  var today = todayStamp(now)
  var acc = { remaining: 0, overdue: 0, today: 0 }
  var lists = openLists(state)
  for (var i = 0; i < lists.length; i++) walkAttention(lists[i].items, today, acc)
  return acc
}

function walkAttention(items, today, acc) {
  var list = Array.isArray(items) ? items : []
  for (var i = 0; i < list.length; i++) {
    var it = list[i]
    if (!it.checked) {
      acc.remaining += 1
      var kind = dueKind(it.due, today)
      if (kind === "overdue") acc.overdue += 1
      else if (kind === "today") acc.today += 1
    }
    walkAttention(it.items, today, acc)
  }
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

function barTooltip(state, now) {
  var info = attention(state, now)
  if (info.overdue === 1) return "Lists — 1 overdue"
  if (info.overdue > 1) return "Lists — " + info.overdue + " overdue"
  if (info.remaining === 1) return "Lists — 1 remaining"
  if (info.remaining > 1) return "Lists — " + info.remaining + " remaining"
  return "Lists"
}
