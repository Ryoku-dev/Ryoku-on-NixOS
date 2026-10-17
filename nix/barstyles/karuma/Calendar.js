// Month-grid maths for the clock sheet's calendar. Pure data, tested with node
// (Calendar.test.mjs), so the QML only has to draw what this returns.

// Always 6 weeks of 7 days, so the sheet never changes height between months.
// `firstDay` is the first weekday column, 0 = Sunday .. 6 = Saturday (Qt's
// Locale.firstDayOfWeek). Returns { year, month, cells: [{ day, month, year,
// inMonth, weekday }] } with month 0-11.
function monthGrid(year, month, firstDay) {
    var y = Number(year), m = Number(month);
    var fd = ((Math.round(Number(firstDay)) || 0) % 7 + 7) % 7;
    var first = new Date(y, m, 1);
    var lead = (first.getDay() - fd + 7) % 7;
    var cells = [];
    for (var i = 0; i < 42; ++i) {
        var d = new Date(y, m, 1 - lead + i);
        cells.push({ day: d.getDate(), month: d.getMonth(), year: d.getFullYear(),
                     inMonth: d.getMonth() === first.getMonth(), weekday: d.getDay() });
    }
    return { year: first.getFullYear(), month: first.getMonth(), cells: cells };
}

// The month `offset` months away from `date`, as { year, month }.
function shiftMonth(date, offset) {
    var d = new Date(date.getFullYear(), date.getMonth() + Math.round(Number(offset) || 0), 1);
    return { year: d.getFullYear(), month: d.getMonth() };
}

function isToday(cell, now) {
    return cell.day === now.getDate() && cell.month === now.getMonth() && cell.year === now.getFullYear();
}

// Weekday indexes in column order, starting at `firstDay`.
function weekdayOrder(firstDay) {
    var fd = ((Math.round(Number(firstDay)) || 0) % 7 + 7) % 7, out = [];
    for (var i = 0; i < 7; ++i) out.push((fd + i) % 7);
    return out;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { monthGrid: monthGrid, shiftMonth: shiftMonth, isToday: isToday, weekdayOrder: weekdayOrder };
