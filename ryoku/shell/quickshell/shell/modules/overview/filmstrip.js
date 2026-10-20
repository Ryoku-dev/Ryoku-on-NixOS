// The compact overview's cell layout: one row of workspace cells at a height
// set from the screen, shrinking to fit the width it is given and wrapping to
// more rows only when a cell would get smaller than cellMin. A slot that is
// not full (the "+" slot) is a narrow slat. Boxes are in the row block's own
// coordinates, in the same shape as the full overview's layout.
function layout(slots, aspect, maxWidth, cellMax, cellMin, slat, gap) {
    const fulls = slots.filter(slot => slot.full).length;
    const slats = slots.length - fulls;
    const gaps = Math.max(0, slots.length - 1) * gap;
    const widthAt = h => fulls * h / aspect + slats * slat + gaps;
    let cellH = cellMax;
    if (widthAt(cellH) > maxWidth && fulls > 0)
        cellH = Math.max(cellMin, (maxWidth - slats * slat - gaps) * aspect / fulls);
    cellH = Math.floor(cellH);

    const rows = [];
    let row = [];
    let rowW = 0;
    for (let i = 0; i < slots.length; i++) {
        const w = slots[i].full ? cellH / aspect : slat;
        const add = (row.length > 0 ? gap : 0) + w;
        if (row.length > 0 && rowW + add > maxWidth) {
            rows.push({ ids: row, width: rowW });
            row = [];
            rowW = 0;
        }
        rowW += (row.length > 0 ? gap : 0) + w;
        row.push(i);
    }
    if (row.length > 0)
        rows.push({ ids: row, width: rowW });

    const width = rows.reduce((m, r) => Math.max(m, r.width), 0);
    const items = [];
    for (let r = 0; r < rows.length; r++) {
        let x = (width - rows[r].width) / 2;
        for (const i of rows[r].ids) {
            const w = slots[i].full ? cellH / aspect : slat;
            items[i] = { x: Math.round(x), y: r * (cellH + gap), w: Math.round(w), h: cellH };
            x += w + gap;
        }
    }
    return { items: items, cellH: cellH, width: Math.round(width),
        height: rows.length * cellH + Math.max(0, rows.length - 1) * gap };
}

if (typeof module !== "undefined" && module.exports) module.exports = { layout };
