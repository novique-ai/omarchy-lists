const test = require("node:test")
const assert = require("node:assert/strict")
const { load, deepEqual } = require("./load")

const Model = load("Model.js")

function grocer() {
  let state = Model.createList(Model.emptyState(), "Groceries")
  const listId = state.selectedId
  state = Model.addItem(state, listId, "Produce")
  state = Model.addItem(state, listId, "Dairy")
  const produceId = Model.findList(state, listId).items[0].id
  const dairyId = Model.findList(state, listId).items[1].id
  return { state, listId, produceId, dairyId }
}

test("load keeps nested items and due dates from older flat files", () => {
  const state = Model.load(JSON.stringify({
    lists: [{
      title: "Trip",
      items: [
        { text: "Pack", due: "2026-09-01", items: [{ text: "Passport", checked: true }] },
        { text: "Milk" }
      ]
    }]
  }))
  const pack = state.lists[0].items[0]
  assert.equal(pack.text, "Pack")
  assert.equal(pack.due, "2026-09-01")
  assert.equal(pack.items.length, 1)
  assert.equal(pack.items[0].text, "Passport")
  assert.equal(pack.items[0].checked, true)
  assert.equal(pack.items[0].due, "")
  assert.equal(state.lists[0].items[1].items.length, 0)
})

test("remainingCount and progress walk nested items", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.addChild(state, listId, produceId, "Kale")
  const list = Model.findList(state, listId)
  assert.equal(Model.remainingCount(list), 4)
  assert.equal(Model.progressLabel(list), "0/4")

  const applesId = list.items[0].items[0].id
  state = Model.toggleItem(state, listId, applesId)
  assert.equal(Model.remainingCount(Model.findList(state, listId)), 3)
  assert.equal(Model.progressLabel(Model.findList(state, listId)), "1/4")
})

test("flattenItems is depth-first with due labels", () => {
  const today = "2026-08-29"
  let { state, listId, produceId, dairyId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.setDue(state, listId, dairyId, "2026-08-28")
  const rows = Model.flattenItems(Model.findList(state, listId), new Date("2026-08-29T12:00:00"))
  deepEqual(rows.map((row) => [row.text, row.depth]), [
    ["Produce", 0],
    ["Apples", 1],
    ["Dairy", 0]
  ])
  const dairy = rows.find((row) => row.text === "Dairy")
  assert.equal(dairy.due, "2026-08-28")
  assert.equal(dairy.dueKind, "overdue")
  assert.ok(String(dairy.dueLabel).length > 0)
  assert.equal(Model.dueKind("", today), "none")
  assert.equal(Model.dueKind("2026-08-29", today), "today")
  assert.equal(Model.dueKind("2026-08-30", today), "upcoming")
  assert.equal(Model.formatDue("2026-08-29", today), "today")
  assert.equal(Model.formatDue("2026-08-30", today), "tomorrow")
})

test("indent nests under the previous sibling; outdent restores it", () => {
  let { state, listId, dairyId } = grocer()
  state = Model.indentItem(state, listId, dairyId)
  const list = Model.findList(state, listId)
  assert.equal(list.items.length, 1)
  assert.equal(list.items[0].text, "Produce")
  assert.equal(list.items[0].items.length, 1)
  assert.equal(list.items[0].items[0].text, "Dairy")
  assert.equal(list.items[0].items[0].id, dairyId)

  state = Model.outdentItem(state, listId, dairyId)
  deepEqual(texts(Model.findList(state, listId)), ["Produce", "Dairy"])
})

test("indent of the first item is a no-op and outdent of a root item is a no-op", () => {
  let { state, listId, produceId } = grocer()
  const before = Model.serialize(state)
  state = Model.indentItem(state, listId, produceId)
  assert.equal(Model.serialize(state), before)
  state = Model.outdentItem(state, listId, produceId)
  assert.equal(Model.serialize(state), before)
})

test("deleting a parent removes its children; rename/toggle find nested items", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  const applesId = Model.findList(state, listId).items[0].items[0].id
  state = Model.renameItem(state, listId, applesId, "Honeycrisp")
  assert.equal(Model.findList(state, listId).items[0].items[0].text, "Honeycrisp")
  state = Model.toggleItem(state, listId, applesId)
  assert.equal(Model.findList(state, listId).items[0].items[0].checked, true)
  state = Model.deleteItem(state, listId, produceId)
  deepEqual(texts(Model.findList(state, listId)), ["Dairy"])
})

test("setDue stores a calendar day and clears on blank; invalid dates are ignored", () => {
  let { state, listId, dairyId } = grocer()
  state = Model.setDue(state, listId, dairyId, "2026-09-04")
  assert.equal(Model.findList(state, listId).items[1].due, "2026-09-04")
  state = Model.setDue(state, listId, dairyId, "nope")
  assert.equal(Model.findList(state, listId).items[1].due, "2026-09-04")
  state = Model.setDue(state, listId, dairyId, "")
  assert.equal(Model.findList(state, listId).items[1].due, "")
})

test("nested lists survive serialize round-trip", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.setDue(state, listId, produceId, "2026-09-01")
  state = Model.setCollapsed(state, listId, produceId, true)
  state = Model.setPinned(state, listId, true)
  state = Model.toggleHideCompleted(state)
  const reloaded = Model.load(Model.serialize(state))
  const produce = reloaded.lists[0].items[0]
  assert.equal(produce.due, "2026-09-01")
  assert.equal(produce.items[0].text, "Apples")
  assert.equal(produce.collapsed, true)
  assert.equal(reloaded.lists[0].pinned, true)
  assert.equal(reloaded.hideCompleted, true)
})

test("due words resolve against today and invalid text is ignored", () => {
  const now = new Date("2026-08-29T12:00:00")
  let { state, listId, dairyId } = grocer()
  state = Model.setDue(state, listId, dairyId, "tomorrow", now)
  assert.equal(Model.findList(state, listId).items[1].due, "2026-08-30")
  state = Model.setDue(state, listId, dairyId, "+3", now)
  assert.equal(Model.findList(state, listId).items[1].due, "2026-09-01")
  state = Model.setDue(state, listId, dairyId, "nope", now)
  assert.equal(Model.findList(state, listId).items[1].due, "2026-09-01")
  state = Model.setDue(state, listId, dairyId, "today", now)
  assert.equal(Model.findList(state, listId).items[1].due, "2026-08-29")
  assert.equal(Model.parseDueInput("", now), "")
  assert.equal(Model.parseDueInput("week", now), "2026-09-05")
})

test("collapse hides children until expandAll, hideCompleted skips checked rows", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.setCollapsed(state, listId, produceId, true)
  const now = new Date("2026-08-29T12:00:00")
  let rows = Model.flattenItems(Model.findList(state, listId), now)
  deepEqual(rows.map((row) => row.text), ["Produce", "Dairy"])
  rows = Model.flattenItems(Model.findList(state, listId), now, { expandAll: true })
  deepEqual(rows.map((row) => row.text), ["Produce", "Apples", "Dairy"])

  const applesId = Model.findList(state, listId).items[0].items[0].id
  state = Model.toggleItem(state, listId, applesId)
  rows = Model.flattenItems(Model.findList(state, listId), now, {
    hideCompleted: true,
    expandAll: true
  })
  deepEqual(rows.map((row) => row.text), ["Produce", "Dairy"])
})

test("moveItem swaps siblings and moveItemTo reparents", () => {
  let { state, listId, produceId, dairyId } = grocer()
  state = Model.addItem(state, listId, "Bread")
  const breadId = Model.findList(state, listId).items[2].id
  state = Model.moveItem(state, listId, breadId, -1)
  deepEqual(texts(Model.findList(state, listId)), ["Produce", "Bread", "Dairy"])
  state = Model.moveItem(state, listId, produceId, -1)
  deepEqual(texts(Model.findList(state, listId)), ["Produce", "Bread", "Dairy"])

  state = Model.moveItemTo(state, listId, breadId, produceId, "inside")
  const produce = Model.findList(state, listId).items[0]
  assert.equal(produce.text, "Produce")
  assert.equal(produce.collapsed, false)
  deepEqual(produce.items.map((item) => item.text), ["Bread"])
  assert.equal(Model.canMoveItem(Model.findList(state, listId), produceId, breadId, "inside"), false)

  state = Model.moveItemTo(state, listId, breadId, dairyId, "before")
  deepEqual(texts(Model.findList(state, listId)), ["Produce", "Bread", "Dairy"])
})

test("clearCompleted drops checked items and anything nested under them", () => {
  let { state, listId, produceId, dairyId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.toggleItem(state, listId, produceId)
  state = Model.toggleItem(state, listId, dairyId)
  state = Model.addItem(state, listId, "Bread")
  state = Model.clearCompleted(state, listId)
  deepEqual(texts(Model.findList(state, listId)), ["Bread"])
})

test("search matches titles and nested item text", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  const list = Model.findList(state, listId)
  assert.equal(Model.listMatches(list, ""), true)
  assert.equal(Model.listMatches(list, "groc"), true)
  assert.equal(Model.listMatches(list, "appl"), true)
  assert.equal(Model.listMatches(list, "zzz"), false)
})

test("reorderList and moveList stay inside the open or archived section", () => {
  let state = Model.createList(Model.emptyState(), "A")
  state = Model.createList(state, "B")
  state = Model.createList(state, "C")
  const c = state.lists[0].id
  const b = state.lists[1].id
  const a = state.lists[2].id
  state = Model.setArchived(state, b, true)
  state = Model.reorderList(state, c, a, true)
  deepEqual(
    Model.openLists(state).map((list) => list.title),
    ["A", "C"]
  )
  const before = Model.openLists(state).map((list) => list.id)
  state = Model.reorderList(state, c, b, true)
  deepEqual(Model.openLists(state).map((list) => list.id), before)
  state = Model.moveList(state, a, -1)
  deepEqual(Model.openLists(state).map((list) => list.id), before)
  state = Model.moveList(state, c, -1)
  deepEqual(
    Model.openLists(state).map((list) => list.title),
    ["C", "A"]
  )
})

test("duplicateList copies items under new ids and selects the copy", () => {
  let { state, listId, produceId } = grocer()
  state = Model.addChild(state, listId, produceId, "Apples")
  state = Model.setPinned(state, listId, true)
  state = Model.duplicateList(state, listId)
  assert.equal(state.lists[1].title, "Groceries copy")
  assert.equal(state.selectedId, state.lists[1].id)
  assert.equal(state.lists[1].pinned, true)
  assert.notEqual(state.lists[1].id, listId)
  assert.notEqual(state.lists[1].items[0].id, produceId)
  assert.equal(state.lists[1].items[0].items[0].text, "Apples")
  assert.notEqual(state.lists[1].items[0].items[0].id, state.lists[0].items[0].items[0].id)
})

test("overdue wins the bar tooltip", () => {
  let { state, listId, dairyId } = grocer()
  state = Model.setDue(state, listId, dairyId, "2026-08-28")
  assert.equal(Model.barTooltip(state, new Date("2026-08-29T12:00:00")), "Lists — 1 overdue")
  assert.equal(Model.attention(state, new Date("2026-08-29T12:00:00")).today, 0)
})

function texts(list) {
  return (list.items || []).map((item) => String(item.text))
}
