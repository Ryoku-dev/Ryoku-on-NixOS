.pragma library

// Plain helpers for the bar: numerals, stamps, day-rule maths and formatting.
// Adapted from the original core's Spaces.js, Status.js and Edge.js.

var NUMERALS = ["〇", "壱", "弐", "参", "肆", "伍", "陸", "漆", "捌", "玖", "拾"]

function numeral(n) {
  n = parseInt(String(n), 10)
  return !isNaN(n) && n >= 0 && n < NUMERALS.length ? NUMERALS[n] : String(isNaN(n) ? "?" : n)
}

function clamp01(v) {
  v = Number(v)
  if (!isFinite(v)) return 0
  return Math.max(0, Math.min(1, v))
}

// Wi-Fi signal (0..100) as 0..4 bars.
function bars(signal) {
  var s = Number(signal)
  if (!isFinite(s) || s <= 0) return 0
  if (s >= 75) return 4
  if (s >= 50) return 3
  if (s >= 25) return 2
  return 1
}

// A name cut to what a glance needs: "Next India", "Enco Buds2".
function short(name) {
  var words = String(name === undefined || name === null ? "" : name).trim().split(/\s+/).filter(function(w) { return w !== "" })
  if (!words.length) return ""
  if (words.length > 1 && /^[A-Z]{2,5}$/.test(words[0])) words = words.slice(1)
  var out = words[0]
  if (out.length < 5 && words.length > 1) out += " " + words[1]
  else if (words.length > 1 && (out + " " + words[1]).length <= 12) out += " " + words[1]
  return out.length > 14 ? out.slice(0, 13) + "…" : out
}

function count2(n) {
  n = Math.max(0, Math.round(Number(n) || 0))
  return n > 99 ? "99" : (n < 10 ? "0" : "") + n
}

// Notification stamps get the app's initial; a few apps a kanji, like a seal.
var STAMP_KANJI = { firefox: "火", "zen": "禅", "librewolf": "狼", "signal": "信", "spotify": "音" }

function stampGlyph(app) {
  var a = String(app || "").trim()
  if (a === "") return "・"
  var k = STAMP_KANJI[a.toLowerCase()]
  if (k) return k
  var ch = a.charAt(0)
  return /[a-z]/i.test(ch) ? ch.toUpperCase() : ch
}

// A small, steady tilt per stamp: -6 .. 6 degrees in 1.5 degree steps.
function tilt(key) {
  var s = String(key || ""), h = 0
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return ((Math.abs(h) % 9) - 4) * 1.5
}

function esc(s) {
  return String(s === undefined || s === null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// ---------------------------------------------------------------- the edge
var HOURS = 24
var MAJOR_EVERY = 6

function dayFraction(date) {
  var d = date instanceof Date ? date : new Date(date)
  if (isNaN(d.getTime())) return 0
  return (d.getHours() * 60 + d.getMinutes()) / (HOURS * 60)
}

function hourTicks() {
  var out = []
  for (var h = 1; h < HOURS; h++)
    out.push({ hour: h, fraction: h / HOURS, major: h % MAJOR_EVERY === 0 })
  return out
}

function at(fraction, length, width) {
  var w = Math.max(0, Number(width) || 0)
  var x = Math.round(Math.max(0, Math.min(1, Number(fraction) || 0)) * length)
  return Math.max(0, Math.min(Math.max(0, length - w), x))
}
