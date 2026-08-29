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
  const reloaded = Model.load(Model.serialize(state))
  const produce = reloaded.lists[0].items[0]
  assert.equal(produce.due, "2026-09-01")
  assert.equal(produce.items[0].text, "Apples")
})

function texts(list) {
  return (list.items || []).map((item) => String(item.text))
}
