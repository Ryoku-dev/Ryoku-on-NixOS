import { createRequire } from "node:module";
import assert from "node:assert/strict";
const C = createRequire(import.meta.url)("./Calendar.js");

// Oct 2026 starts on a Thursday (4)
let g = C.monthGrid(2026, 9, 0);
assert.equal(g.cells.length, 42);
assert.equal(g.cells[4].day, 1); assert.ok(g.cells[4].inMonth); assert.ok(!g.cells[3].inMonth);
assert.equal(g.cells[0].day, 27); assert.equal(g.cells[0].month, 8);          // Sun 27 Sep
assert.equal(g.cells.filter(c => c.inMonth).length, 31);
// Monday-first: Oct 1 is the fourth column
g = C.monthGrid(2026, 9, 1);
assert.equal(g.cells[3].day, 1); assert.equal(g.cells[0].weekday, 1);
// every column keeps its weekday
for (const fd of [0, 1, 6]) {
  const grid = C.monthGrid(2024, 1, fd);                                      // Feb 2024, leap year
  assert.equal(grid.cells.filter(c => c.inMonth).length, 29);
  grid.cells.forEach((c, i) => assert.equal(c.weekday, (fd + i) % 7));
}
// year boundaries
g = C.monthGrid(2026, 11, 0);
assert.ok(g.cells.some(c => c.year === 2027 && c.month === 0));
assert.deepEqual(C.shiftMonth(new Date(2026, 11, 15), 1), { year: 2027, month: 0 });
assert.deepEqual(C.shiftMonth(new Date(2026, 0, 31), -1), { year: 2025, month: 11 });
assert.deepEqual(C.shiftMonth(new Date(2026, 0, 31), 0), { year: 2026, month: 0 });
// today
const now = new Date(2026, 9, 16);
g = C.monthGrid(2026, 9, 0);
assert.equal(g.cells.filter(c => C.isToday(c, now)).length, 1);
assert.deepEqual(C.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0]);
assert.deepEqual(C.weekdayOrder(undefined), [0, 1, 2, 3, 4, 5, 6]);
console.log("Calendar: all assertions passed");
