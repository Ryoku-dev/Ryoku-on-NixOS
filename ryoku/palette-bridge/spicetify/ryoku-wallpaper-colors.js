// Update Spotify's color variables directly from Ryoku's wallpaper palette.
// This changes paint values in place: no renderer reload and no playback pause.
(function ryokuWallpaperColors() {
  if (window.__ryokuWallpaperColors) return;
  window.__ryokuWallpaperColors = true;
  const endpoint = "http://127.0.0.1:47616/v1/events";
  const paletteRoles = {
    text: "onSurface",
    subtext: "onSurfaceVariant",
    main: "background",
    "main-elevated": "surfaceContainer",
    "main-transition": "surface",
    highlight: "surfaceContainerHigh",
    "highlight-elevated": "surfaceContainerHighest",
    sidebar: "surfaceContainerLow",
    player: "background",
    card: "surfaceContainer",
    shadow: "shadow",
    "selected-row": "onSurface",
    button: "primary",
    "button-active": "primaryContainer",
    "button-disabled": "outlineVariant",
    "tab-active": "surfaceContainerHigh",
    notification: "tertiary",
    "notification-error": "error",
    misc: "surfaceVariant",
    "play-button": "primary",
    "play-button-active": "primaryContainer",
    "progress-fg": "secondary",
    "progress-bg": "surfaceVariant",
    heart: "error",
    "pagelink-active": "tertiary",
    "radio-btn-active": "primary",
  };

  const paletteCss = `
    :root,
    .encore-dark-theme,
    .encore-dark-theme .encore-base-set {
      --background-base: var(--spice-main) !important;
      --background-highlight: var(--spice-highlight) !important;
      --background-press: var(--spice-highlight-elevated) !important;
      --background-elevated-base: var(--spice-main-elevated) !important;
      --background-elevated-highlight: var(--spice-highlight-elevated) !important;
      --background-elevated-press: var(--spice-highlight-elevated) !important;
      --background-tinted-base: var(--spice-main-elevated) !important;
      --background-tinted-highlight: var(--spice-highlight) !important;
      --background-tinted-press: var(--spice-highlight-elevated) !important;
      --text-base: var(--spice-text) !important;
      --text-subdued: var(--spice-subtext) !important;
      --text-bright-accent: var(--spice-button) !important;
      --essential-base: var(--spice-text) !important;
      --essential-subdued: var(--spice-subtext) !important;
      --essential-bright-accent: var(--spice-button) !important;
      --decorative-base: var(--spice-text) !important;
      --decorative-subdued: var(--spice-subtext) !important;
      --encore-app-semantic-background-color: var(--spice-main) !important;
      --encore-background-highlight: var(--spice-highlight) !important;
      --encore-background-elevated-highlight: var(--spice-highlight-elevated) !important;
      --encore-box-shadow-color: var(--spice-shadow) !important;
      --encore-focus-outline-color: var(--spice-button) !important;
    }
    :root .encore-bright-accent-set {
      --background-base: var(--spice-button) !important;
      --background-highlight: var(--spice-button-active) !important;
      --background-press: var(--spice-button-active) !important;
      --text-base: var(--spice-main) !important;
      --essential-base: var(--spice-main) !important;
    }
  `;
  const detailCss = `
    .main-actionBarBackground-background,
    .playlist-playlist-actionBarBackground-background {
      background: linear-gradient(180deg,
        color-mix(in srgb, var(--spice-pagelink-active) 12%, var(--spice-main)),
        var(--spice-main)) !important;
    }
    .Root__now-playing-bar .main-genericButton-button[data-active="true"],
    .Root__now-playing-bar .main-genericButton-button[aria-pressed="true"],
    .Root__now-playing-bar .main-genericButton-buttonActive {
      color: var(--spice-pagelink-active) !important;
    }
    .Root__now-playing-bar .main-genericButton-button[data-active="true"]::after,
    .Root__now-playing-bar .main-genericButton-button[aria-pressed="true"]::after {
      background-color: var(--spice-pagelink-active) !important;
    }
    .main-trackList-trackListRow:hover,
    .main-trackList-trackListRow:focus-within {
      background-color: color-mix(in srgb, var(--spice-pagelink-active) 10%, var(--spice-main)) !important;
    }
    .main-trackList-trackListRow[aria-selected="true"],
    [role="row"][aria-selected="true"] .main-trackList-trackListRow {
      background-color: color-mix(in srgb, var(--spice-pagelink-active) 18%, var(--spice-main)) !important;
    }
    .main-trackList-trackListRow {
      color: var(--spice-subtext) !important;
      --text-base: var(--spice-text) !important;
      --text-subdued: var(--spice-subtext) !important;
    }
    .main-trackInfo-artists a,
    .Root__main-view a[href^="/artist/"],
    .main-trackList-trackListRow a[href^="/artist/"] {
      color: var(--spice-pagelink-active) !important;
    }
    .Root__globalNav .main-globalNav-navLink {
      background-color: var(--spice-main-elevated) !important;
      color: var(--spice-subtext) !important;
    }
    .Root__globalNav .main-globalNav-navLinkActive {
      color: var(--spice-pagelink-active) !important;
    }
    .Root__globalNav .main-globalNav-navLink:hover,
    .Root__globalNav .main-globalNav-navLink:focus-visible {
      background-color: var(--spice-highlight) !important;
      color: var(--spice-text) !important;
    }
    .main-contextMenu-tippy,
    #hover-or-focus-tooltip {
      --generic-tooltip-background-color: var(--spice-card) !important;
      background-color: var(--spice-card) !important;
      color: var(--spice-text) !important;
    }
  `;
  const defaultPreferences = {
    neutralStyle: false, accentStrength: 100, surfaceTint: 5, neutralText: true, removeGradients: true,
    surfaceBrightness: 50, sidebarTint: 100, playerTint: 100, cardTint: 100,
    accentButtons: true, accentProgress: true, accentLinks: true,
  };
  let preferences = { ...defaultPreferences };
  let latestPalette = null;
  function mix(base, tint, amount) {
    return "#" + [1, 3, 5].map(i => Math.round(
      parseInt(base.slice(i, i + 2), 16) * (1 - amount) +
      parseInt(tint.slice(i, i + 2), 16) * amount,
    ).toString(16).padStart(2, "0")).join("");
  }
  function luminance(hex) {
    const channels = [1, 3, 5].map(i => {
      const value = parseInt(hex.slice(i, i + 2), 16) / 255;
      return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  }
  function colorsFor(palette) {
    if (!/^#[0-9a-f]{6}$/i.test(palette.primary || "")) return null;
    const tint = mix("#c7c9d1", palette.primary, preferences.accentStrength / 100);
    const amount = preferences.surfaceTint / 100;
    const surface = (base, weight) => {
      const brightness = preferences.surfaceBrightness;
      const foundation = brightness <= 50
        ? mix("#000000", base, brightness / 50)
        : mix(base, "#ffffff", (brightness - 50) / 50 * 0.12);
      return mix(foundation, tint, amount * weight);
    };
    const main = surface("#131416", 0.5);
    const card = surface("#222327", preferences.cardTint / 100);
    let accent = tint;
    for (let amount = 0.1; (luminance(accent) + 0.05) / (luminance(card) + 0.05) < 4.5; amount += 0.1) {
      accent = mix(tint, "#ffffff", Math.min(amount, 1));
    }
    const button = preferences.accentButtons ? accent : "#c7c9d1";
    const progress = preferences.accentProgress ? accent : "#c7c9d1";
    const link = preferences.accentLinks ? accent : "#c7c9d1";
    return {
      text: preferences.neutralText ? "#f1f1f3" : (palette.onSurface || "#f1f1f3"),
      subtext: preferences.neutralText ? "#b6b8c0" : (palette.onSurfaceVariant || "#b6b8c0"), main,
      "main-elevated": surface("#1c1d21", 0.9),
      "main-transition": main,
      highlight: surface("#292b30", 1.5),
      "highlight-elevated": surface("#33353b", 1.8),
      sidebar: surface("#17181b", 0.7 * preferences.sidebarTint / 100),
      player: surface("#101113", 0.4 * preferences.playerTint / 100),
      card, shadow: "#000000",
      "selected-row": "#f1f1f3", button,
      "button-active": mix(button, "#ffffff", 0.15),
      "button-disabled": "#555760",
      "tab-active": surface("#292b30", 1.5),
      notification: accent, "notification-error": "#f28b82",
      misc: "#6b6e78", "play-button": button,
      "play-button-active": mix(button, "#ffffff", 0.15),
      "progress-fg": progress, "progress-bg": "#45474f",
      heart: link, "pagelink-active": link, "radio-btn-active": link,
    };
  }

  // Modern Spotify surfaces use Encore tokens in addition to --spice-*.
  const neutralCss = `
    :root,
    .encore-dark-theme,
    .encore-dark-theme .encore-base-set {
      --text-bright-accent: var(--spice-pagelink-active) !important;
      --essential-bright-accent: var(--spice-pagelink-active) !important;
    }
    body,
    .Root__top-container,
    .Root__globalNav { background-color: var(--spice-player) !important; }
    .Root__now-playing-bar { background: var(--spice-player) !important; }
    .Root__now-playing-bar [data-testid="control-button-playpause"] > span,
    .Root__main-view [data-encore-id="buttonPrimary"] > span {
      background-color: var(--spice-button) !important;
      color: #131416 !important;
    }
    .playback-progressbar .x-progressBar-fillColor {
      background-color: var(--spice-progress-fg) !important;
    }
    :root .encore-bright-accent-set {
      --background-base: var(--spice-button) !important;
      --background-highlight: var(--spice-button-active) !important;
      --background-press: var(--spice-button-active) !important;
      --text-base: #131416 !important;
      --essential-base: #131416 !important;
    }
  `;
  const washCss = `
    .main-home-homeHeader,
    .main-home-homeBackground,
    .main-actionBarBackground-background,
    .playlist-playlist-actionBarBackground-background,
    .main-entityHeader-backgroundColor,
    .main-topBar-overlay {
      background: var(--spice-main) !important;
      background-image: none !important;
    }
  `;

  let bridge = document.getElementById("ryoku-wallpaper-token-bridge");
  if (!bridge) {
    bridge = document.createElement("style");
    bridge.id = "ryoku-wallpaper-token-bridge";
    bridge.textContent = paletteCss;
    document.head.appendChild(bridge);
  }

  let last = "";
  const applied = new Map();
  function setColor(style, name, color) {
    if (applied.get(name) === color) return;
    style.setProperty(name, color);
    applied.set(name, color);
  }
  function rgb(hex) {
    const value = hex.replace("#", "");
    return [0, 2, 4].map((i) => parseInt(value.slice(i, i + 2), 16)).join(",");
  }
  function update(palette) {
    if (!palette || typeof palette.primary !== "string" || !/^#[0-9a-f]{6}$/i.test(palette.primary)) return;
    latestPalette = palette;
    render();
  }
  function render() {
    try {
      const palette = latestPalette;
      if (!palette || !/^#[0-9a-f]{6}$/i.test(palette.primary || "")) return;
      const colors = preferences.neutralStyle ? colorsFor(palette) : Object.fromEntries(
        Object.entries(paletteRoles).map(([name, role]) => [name, palette[role]]),
      );
      if (!colors) return;
      const signature = JSON.stringify({ palette, preferences });
      if (signature === last) return;
      last = signature;
      const css = paletteCss + detailCss + (preferences.neutralStyle ? neutralCss + (preferences.removeGradients ? washCss : "") : "");
      if (bridge.textContent !== css) bridge.textContent = css;
      const style = document.documentElement.style;
      for (const [name, color] of Object.entries(colors)) {
        if (!/^#[0-9a-f]{6}$/i.test(color || "")) continue;
        setColor(style, "--spice-" + name, color);
        setColor(style, "--spice-rgb-" + name, rgb(color));
      }
      if (/^#[0-9a-f]{6}$/i.test(palette.primary || "")) {
        setColor(style, "--spice-primary", colors.button);
      }
      window.dispatchEvent(new CustomEvent("ryoku-palette-changed", { detail: palette }));
    } catch (_) {}
  }

  function updatePreferences(doc) {
    const incoming = doc && doc.spotify;
    if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) return;
    const next = { ...defaultPreferences, ...incoming };
    const booleans = ["neutralStyle", "neutralText", "removeGradients", "accentButtons", "accentProgress", "accentLinks"];
    const ranges = { accentStrength: 100, surfaceTint: 20, surfaceBrightness: 100, sidebarTint: 100, playerTint: 100, cardTint: 100 };
    if (booleans.some(key => typeof next[key] !== "boolean") ||
        Object.entries(ranges).some(([key, max]) => !Number.isFinite(next[key]) || next[key] < 0 || next[key] > max)) return;
    preferences = Object.fromEntries(Object.keys(defaultPreferences).map(key => [key, next[key]]));
    render();
  }
  function subscribe(url, apply) {
    let reconnectTimer = null;
    function connect() {
      const events = new EventSource(url);
      events.onmessage = event => {
        try { apply(JSON.parse(event.data)); } catch (_) {}
      };
      events.onerror = () => {
        events.close();
        if (reconnectTimer !== null) return;
        reconnectTimer = setTimeout(() => {
          reconnectTimer = null;
          connect();
        }, 1000);
      };
    }
    connect();
  }
  subscribe("http://127.0.0.1:47616/v1/preferences/events", updatePreferences);
  subscribe(endpoint, update);
})();
