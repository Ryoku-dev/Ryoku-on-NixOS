.pragma library

// The ink ramp: the theme's foreground walked toward its background until
// each tier lands on a fixed contrast against the paper (WCAG ratios). The
// Typeset mockups were drawn with this same tier() function.
// Colours here are "#rrggbb" strings; Ink.qml turns them into QML colours.

var TIERS = { ink: 12, inkDim: 9, inkMuted: 6.2, inkFaint: 4.6 }

function hexToRgb(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length === 8) h = h.substr(2) // QML's #aarrggbb
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  return [0, 2, 4].map(function(i) { return parseInt(h.substr(i, 2), 16) || 0 })
}

function rgbToHex(c) {
  return "#" + c.map(function(v) {
    var s = Math.max(0, Math.min(255, Math.round(v))).toString(16)
    return s.length < 2 ? "0" + s : s
  }).join("")
}

// t = 1 is all a, t = 0 is all b.
function mix(a, b, t) {
  var A = hexToRgb(a), B = hexToRgb(b)
  return rgbToHex(A.map(function(v, i) { return v * t + B[i] * (1 - t) }))
}

function luminance(hex) {
  var c = hexToRgb(hex).map(function(v) {
    v /= 255
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
  })
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

function contrast(a, b) {
  var x = luminance(a), y = luminance(b)
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// The faintest mix of fg into bg that still reaches `target`. A theme whose
// foreground is already below the target keeps its foreground.
function tier(fg, bg, target) {
  var t = 1, c = mix(fg, bg, 1)
  while (t > 0.2) {
    var next = mix(fg, bg, t - 0.01)
    if (contrast(next, bg) < target) break
    t -= 0.01
    c = next
  }
  return c
}

function isLight(bg) {
  return luminance(bg) > 0.4
}

function ramp(fg, bg) {
  return {
    ink: tier(fg, bg, TIERS.ink),
    inkDim: tier(fg, bg, TIERS.inkDim),
    inkMuted: tier(fg, bg, TIERS.inkMuted),
    inkFaint: tier(fg, bg, TIERS.inkFaint)
  }
}

// Kata's tones (core/Kata.js, docs/kata): one ink diluted toward the paper
// to a contrast, plus the opaque mixes the parts are cut from.
//   ink2  quiet text, 7:1 (or 80% of the theme's own contrast, at least 5.6)
//   ink3  secondary text and icons at rest, 4.6:1 (AA at 12px)
//   ink4  frames, ticks, disabled; never text you must read, 2:1
//   line  lattice and hairlines; lift  cards; paper2  sheets beneath, slots;
//   sunk  the room behind a panel
function kata(fg, bg) {
  var light = isLight(bg)
  var top = contrast(fg, bg)
  return {
    ink2: tier(fg, bg, Math.max(5.6, Math.min(7, top * 0.8))),
    ink3: tier(fg, bg, 4.6),
    ink4: tier(fg, bg, 2.05),
    line: mix(fg, bg, light ? 0.14 : 0.12),
    lift: mix(fg, bg, light ? 0.035 : 0.045),
    paper2: light ? mix(fg, bg, 0.055) : mix("#000000", bg, 0.32),
    sunk: light ? mix(fg, bg, 0.025) : mix("#000000", bg, 0.45)
  }
}
