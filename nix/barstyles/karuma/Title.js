.pragma library

// Turns a Hyprland window class and title into the parts the title styles
// draw: the app's name, the title, and a path split so its folders can
// recede and the file stays readable. Pure; tested in tests/unit.mjs.

// Classes whose last dotted part is not the name people know the app by.
var NAMES = {
  "firefox": "Firefox",
  "chromium": "Chromium",
  "google-chrome": "Chrome",
  "brave-browser": "Brave",
  "code": "VS Code",
  "code-oss": "VS Code",
  "org.gnome.nautilus": "Files",
  "org.pwmt.zathura": "Zathura",
  "com.mitchellh.ghostty": "Ghostty",
  "obsidian": "Obsidian",
  "spotify": "Spotify",
  "signal": "Signal",
  "typora": "Typora",
  "mpv": "mpv",
  "imv": "imv",
  "localsend": "LocalSend",
  "1password": "1Password"
}

// Browsers and editors append " - App" or " — Mozilla Firefox" to every title.
var SUFFIX = /\s+[-—–]\s+(Mozilla Firefox|Firefox|Chromium|Google Chrome|Brave|Visual Studio Code|Code - OSS|Obsidian v[\d.]+|Obsidian)\s*$/

function appName(cls) {
  var c = String(cls || "").trim()
  if (c === "") return ""
  var known = NAMES[c.toLowerCase()]
  if (known) return known
  // Reverse-DNS ids (org.foo.Bar) read best as their last part.
  var parts = c.split(".")
  var last = parts[parts.length - 1]
  last = last.replace(/[-_]+/g, " ")
  return last.charAt(0).toUpperCase() + last.slice(1)
}

// The first token that looks like a path: starts at ~/ or / and has a slash
// after its first character.
function findPath(text) {
  var m = /(^|[\s:(])((~|\.{1,2})?\/[^\s)]*\/?[^\s)]*)/.exec(text)
  if (!m) return null
  var path = m[2]
  if (path.length < 2 || path.indexOf("/") === -1) return null
  return { start: m.index + m[1].length, path: path }
}

function describe(cls, title) {
  var app = appName(cls)
  var t = String(title || "").replace(SUFFIX, "").trim()
  if (app !== "" && t.toLowerCase() === app.toLowerCase()) t = ""
  var out = { app: app, head: t, dir: "", leaf: "" }
  var p = findPath(t)
  if (!p) return out
  var slash = p.path.lastIndexOf("/")
  out.head = t.slice(0, p.start).replace(/[\s:·\-—–]+$/, "").trim()
  out.dir = p.path.slice(0, slash + 1)
  out.leaf = p.path.slice(slash + 1) + t.slice(p.start + p.path.length)
  out.leaf = out.leaf.trim()
  return out
}

// Shortens a home directory to ~ (some terminals report the full path).
function tildify(text, home) {
  if (!home) return text
  return String(text || "").split(home + "/").join("~/")
}
