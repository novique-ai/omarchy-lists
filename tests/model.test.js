const test = require("node:test")
const assert = require("node:assert/strict")
const { load, deepEqual } = require("./load")

const Model = load("Model.js")

function titles(state, archived) {
  return (archived ? Model.archivedLists(state) : Model.openLists(state))
    .map((list) => String(list.title))
}

function texts(list) {
  return (list.items || []).map((item) => String(item.text))
}

test("load recovers from empty, invalid, and partial JSON", () => {
  deepEqual(Model.load(""), Model.emptyState())
  deepEqual(Model.load("not json"), Model.emptyState())
  deepEqual(Model.load("[]"), Model.emptyState())
  const state = Model.load(JSON.stringify({
    lists: [{ title: "  Groceries  ", items: [{ text: "Milk" }, null, "nope"] }]
  }))
  assert.equal(state.lists.length, 1)
  assert.equal(state.lists[0].title, "Groceries")
  assert.equal(state.lists[0].archived, false)
  assert.equal(state.lists[0].items.length, 1)
  assert.equal(state.lists[0].items[0].text, "Milk")
  assert.equal(state.lists[0].items[0].checked, false)
  assert.equal(state.selectedId, state.lists[0].id)
})

test("createList prepends an open list and selects it", () => {
  let state = Model.createList(Model.emptyState(), "Packing")
  state = Model.createList(state, "Groceries")
  deepEqual(titles(state, false), ["Groceries", "Packing"])
  assert.equal(state.lists[0].title, "Groceries")
  assert.equal(state.selectedId, state.lists[0].id)
})

test("empty titles become Untitled and rename ignores blanks", () => {
  let state = Model.createList(Model.emptyState(), "   ")
  assert.equal(state.lists[0].title, "Untitled")
  const original = state.lists[0].title
  state = Model.renameList(state, state.lists[0].id, "  ")
  assert.equal(state.lists[0].title, original)
  state = Model.renameList(state, state.lists[0].id, " Errands ")
  assert.equal(state.lists[0].title, "Errands")
})

test("items can be added, checked, renamed, and deleted", () => {
  let state = Model.createList(Model.emptyState(), "Groceries")
  const listId = state.selectedId
  state = Model.addItem(state, listId, " Milk ")
  state = Model.addItem(state, listId, "Eggs")
  state = Model.addItem(state, listId, "   ")
  const list = Model.findList(state, listId)
  deepEqual(texts(list), ["Milk", "Eggs"])
  assert.equal(Model.remainingCount(list), 2)

  const milkId = list.items[0].id
  state = Model.toggleItem(state, listId, milkId)
  assert.equal(Model.findList(state, listId).items[0].checked, true)
  assert.equal(Model.remainingCount(Model.findList(state, listId)), 1)
  assert.equal(Model.progressLabel(Model.findList(state, listId)), "1/2")

  state = Model.renameItem(state, listId, milkId, "Oat milk")
  assert.equal(Model.findList(state, listId).items[0].text, "Oat milk")

  state = Model.renameItem(state, listId, milkId, "  ")
  deepEqual(texts(Model.findList(state, listId)), ["Eggs"])
})

test("archive hides a list from open, restore brings it back", () => {
  let state = Model.createList(Model.emptyState(), "Old")
  state = Model.createList(state, "Now")
  const oldId = state.lists[1].id
  state = Model.setArchived(state, oldId, true)
  deepEqual(titles(state, false), ["Now"])
  deepEqual(titles(state, true), ["Old"])
  assert.equal(state.selectedId, state.lists[0].id)

  state = Model.setArchived(state, oldId, false)
  deepEqual(titles(state, false), ["Now", "Old"])
  assert.equal(state.selectedId, oldId)
})

test("deleting the selected list moves selection to the next open list", () => {
  let state = Model.createList(Model.emptyState(), "Keep")
  state = Model.createList(state, "Drop")
  const dropId = state.selectedId
  state = Model.deleteList(state, dropId)
  deepEqual(titles(state, false), ["Keep"])
  assert.equal(state.selectedId, state.lists[0].id)
})

test("serialize round-trips and bar tooltip reports remaining open items", () => {
  let state = Model.createList(Model.emptyState(), "A")
  state = Model.addItem(state, state.selectedId, "One")
  state = Model.addItem(state, state.selectedId, "Two")
  state = Model.toggleItem(state, state.selectedId, Model.findList(state, state.selectedId).items[0].id)
  const reloaded = Model.load(Model.serialize(state))
  assert.equal(reloaded.lists[0].title, "A")
  assert.equal(Model.barRemaining(reloaded), 1)
  assert.equal(Model.barTooltip(reloaded), "Lists — 1 remaining")
  assert.equal(Model.barTooltip(Model.emptyState()), "Lists")
})
