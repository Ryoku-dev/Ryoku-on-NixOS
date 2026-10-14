import QtQuick
import Ryoku.Ui.Singletons

QtObject {
    id: sources

    // Every source the daemon offers, in its order, so a tab exists before source.providers
    // answers; searchable false turns the search box into a label.
    readonly property var providers: [
        { id: "wallhaven", label: I18n.tr("Wallhaven"),      searchable: true },
        { id: "steam",     label: I18n.tr("Steam Workshop"), searchable: true },
        { id: "unsplash",  label: I18n.tr("Unsplash"),       searchable: true },
        { id: "pexels",    label: I18n.tr("Pexels"),         searchable: true },
        { id: "youtube",   label: I18n.tr("YouTube"),        searchable: true },
        { id: "bing",      label: I18n.tr("Bing Daily"),     searchable: false },
        { id: "moewalls",  label: I18n.tr("MoeWalls"),       searchable: true },
        { id: "motionbgs", label: I18n.tr("MotionBGs"),      searchable: true },
        { id: "ryostore",  label: I18n.tr("Ryostore"),       searchable: true },
        { id: "repos",     label: I18n.tr("Repos"),          searchable: true }
    ]

    function descriptor(id) {
        for (var i = 0; i < sources.providers.length; ++i)
            if (sources.providers[i].id === id)
                return sources.providers[i]
        return { id: id, label: id, searchable: true }
    }

    function searchPlaceholder(id) {
        switch (id) {
        case "steam":    return I18n.tr("Search Steam Workshop…")
        case "wallhaven":return I18n.tr("Search Wallhaven…")
        case "unsplash": return I18n.tr("Search Unsplash…")
        case "pexels":   return I18n.tr("Search Pexels…")
        case "youtube":  return I18n.tr("Search YouTube…")
        case "repos":    return I18n.tr("Filter files…")
        default:         return I18n.tr("Search…")
        }
    }

    // Index 0-11 is the hue wheel, 12 neutral grey; bright is the active tap.
    function swatchColor(index, bright) {
        var s = bright ? 0.75 : 0.65
        var l = bright ? 0.55 : 0.45
        if (index >= 12)
            return Qt.hsla(0, 0, bright ? 0.60 : 0.45, 1)
        return Qt.hsla(index / 12, s, l, 1)
    }

    function downloadPhase(status) {
        switch (status) {
        case "video":    return I18n.tr("Video")
        case "audio":    return I18n.tr("Audio")
        case "merging":  return I18n.tr("Merging")
        case "clipping": return I18n.tr("Clipping")
        case "fetching": return I18n.tr("Fetching")
        case "queued":   return I18n.tr("Queued")
        default:         return ""
        }
    }
    // Normalise a 0..1 or 0..100 progress to a whole percent.
    function progressPercent(item) {
        var p = Number(item && item.downloadProgress)
        if (isNaN(p)) return 0
        if (p <= 1) p = p * 100
        return Math.round(p)
    }
    // verb arrives translated; the percent and phase are appended.
    function progressLabel(verb, item) {
        var pct = progressPercent(item)
        var phase = downloadPhase(item ? item.downloadStatus : "")
        if (pct <= 0) return verb + "\u2026"
        if (phase.length === 0) return verb + " " + pct + "%"
        return verb + " " + pct + "% \u00b7 " + phase
    }
    function isDownloading(item) {
        if (!item || item.downloaded === true) return false
        var s = item.downloadStatus
        return s !== undefined && s !== null && s !== "" &&
               s !== "done" && s !== "error" && s !== "auth_error"
    }
    function isQueued(item) {
        return !!item && String(item.downloadStatus || "").indexOf("queued") === 0
    }

    function _bool(settings, key, fb) {
        var v = settings.value(key)
        return (v === undefined || v === null) ? fb : (v === true || v === "true" || v === 1)
    }
    function _str(settings, key, fb) {
        var v = settings.value(key)
        return (v === undefined || v === null || v === "") ? fb : String(v)
    }

    function defaultState(id, settings) {
        switch (id) {
        case "wallhaven": {
            var atleast = _str(settings, "wallhaven.defaults.atleast", "")
            var ratio = _str(settings, "wallhaven.defaults.ratios", "")
            return {
                general: _bool(settings, "wallhaven.defaults.general", true),
                anime:   _bool(settings, "wallhaven.defaults.anime", true),
                people:  _bool(settings, "wallhaven.defaults.people", true),
                sort:    _str(settings, "wallhaven.defaults.sort", "toplist"),
                topRange:_str(settings, "wallhaven.defaults.topRange", "1M"),
                sfw:     _bool(settings, "wallhaven.defaults.sfw", true),
                sketchy: _bool(settings, "wallhaven.defaults.sketchy", false),
                nsfw:    _bool(settings, "wallhaven.defaults.nsfw", false),
                colour:  -1,
                resMode: "min",
                resolution: atleast,
                ratios:  ratio.length > 0 ? [ratio] : [],
                atmost:  _str(settings, "wallhaven.defaults.atmost", ""),
                collection: ""
            }
        }
        case "steam":
            return {
                sort:       _str(settings, "steam.defaults.sort", "3"),
                trendDays:  _str(settings, "steam.defaults.trendDays", "7"),
                type:       _str(settings, "steam.defaults.type", ""),
                resolution: _str(settings, "steam.defaults.resolution", ""),
                category:   _str(settings, "steam.defaults.category", ""),
                nsfw:       _bool(settings, "steam.defaults.nsfw", false)
            }
        case "unsplash":
            return { order: "relevant", safety: "high", orientation: "", colour: "" }
        case "pexels":
            return { orientation: "", size: "", colour: "" }
        case "youtube":
            return { maxDuration: "" }
        case "repos": {
            var saved = sources.savedRepos(settings)
            return { repo: saved.length > 0 ? saved[0] : "", type: "all" }
        }
        default:
            return {}
        }
    }

    // Folds the chip state into the flat params source.search reads.
    function _hex2(x) {
        var v = Math.max(0, Math.min(255, Math.round(x * 255)))
        var s = v.toString(16)
        return s.length < 2 ? "0" + s : s
    }
    function swatchHex(index) {
        var c = swatchColor(index, false)
        return _hex2(c.r) + _hex2(c.g) + _hex2(c.b)
    }
    function _bits(a, b, c) { return (a ? "1" : "0") + (b ? "1" : "0") + (c ? "1" : "0") }

    function buildFilters(id, st, settings) {
        switch (id) {
        case "wallhaven": {
            var exact = st.resMode === "exact"
            return {
                categories: _bits(st.general, st.anime, st.people),
                purity: _bits(st.sfw, st.sketchy, st.nsfw),
                sorting: st.sort,
                order: "desc",
                topRange: st.sort === "toplist" ? st.topRange : "",
                atleast: exact ? "" : st.resolution,
                resolutions: (exact && st.resolution.length > 0) ? st.resolution : "",
                ratios: (st.ratios && st.ratios.length > 0) ? st.ratios.join(",") : "",
                colors: st.colour >= 0 ? swatchHex(st.colour) : "",
                atmost: exact ? "" : st.atmost,
                collection: st.collection
            }
        }
        case "steam": {
            var req = []
            if (st.type && st.type.length > 0) req.push(st.type)
            if (st.category && st.category.length > 0) req.push(st.category)
            if (st.resolution && st.resolution.length > 0) req.push(st.resolution)
            return {
                queryType: parseInt(st.sort, 10),
                trendDays: st.sort === "3" ? parseInt(st.trendDays, 10) : 0,
                requiredTags: req,
                allowNsfw: st.nsfw === true
            }
        }
        case "unsplash":
            return { order_by: st.order, content_filter: st.safety, orientation: st.orientation, color: st.colour }
        case "pexels":
            return { orientation: st.orientation, size: st.size, color: st.colour }
        case "youtube":
            return { max_duration: st.maxDuration.length > 0 ? parseInt(st.maxDuration, 10) : 0 }
        case "bing":
            return { market: _str(settings, "sources.bing.market", "en-US") }
        case "repos":
            return { repo: st.repo || "", type: st.type || "all" }
        default:
            return {}
        }
    }

    // Prefers the daemon's own verdict from source.providers, else derives one from settings.
    function availability(id, settings, rpc) {
        if (rpc && rpc.available === false)
            return { enabled: false, reason: sources.reasonText(id, rpc.unavailableReason), code: rpc.unavailableReason || "Disabled" }
        if (rpc && rpc.available === true)
            return { enabled: true, reason: I18n.tr("Available") }

        switch (id) {
        case "wallhaven":
            return _bool(settings, "features.wallhaven", true)
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Enable in settings") }
        case "steam":
            return _bool(settings, "features.steam", true)
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Enable in settings") }
        case "unsplash":
            if (!_bool(settings, "sources.unsplash.enabled", false))
                return { enabled: false, reason: I18n.tr("Enable in settings"), code: "Disabled" }
            return _str(settings, "sources.unsplash.accessKey", "").length > 0
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Credentials required"), code: "MissingCredentials" }
        case "pexels":
            if (!_bool(settings, "sources.pexels.enabled", false))
                return { enabled: false, reason: I18n.tr("Enable in settings"), code: "Disabled" }
            return _str(settings, "sources.pexels.apiKey", "").length > 0
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Credentials required"), code: "MissingCredentials" }
        case "youtube":
            return _bool(settings, "sources.youtube.enabled", false)
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Enable in settings") }
        case "bing":
            return _bool(settings, "sources.bing.enabled", false)
                ? { enabled: true, reason: I18n.tr("Available") }
                : { enabled: false, reason: I18n.tr("Enable in settings") }
        default:
            return { enabled: true, reason: I18n.tr("Available") }
        }
    }

    // The daemon reports why a source is off as a code; people read skwd's wording.
    function reasonText(id, code) {
        switch (code) {
        case "MissingCredentials": return I18n.tr("Credentials required")
        case "MissingTool": return id === "youtube" ? I18n.tr("Install yt-dlp") : I18n.tr("Helper not installed")
        default: return I18n.tr("Enable in settings")
        }
    }

    // The Sources setting that turns a source on, or takes its missing key.
    function settingsControl(id, code) {
        switch (id) {
        case "wallhaven": return "features.wallhaven"
        case "steam": return "features.steam"
        case "unsplash": return code === "MissingCredentials" ? "sources.unsplash.accessKey" : "sources.unsplash.enabled"
        case "pexels": return code === "MissingCredentials" ? "sources.pexels.apiKey" : "sources.pexels.enabled"
        default: return "sources." + id + ".enabled"
        }
    }

    function manualSearch(id, settings) {
        return _bool(settings, "sources." + id + ".showApplyButton", false)
    }

    // Saved as owner/repo; a pasted GitHub address is cut back to that.
    function normaliseRepo(raw) {
        var v = String(raw || "").trim()
            .replace(/^(https?:\/\/)?(www\.)?github\.com\//, "")
            .replace(/\.git$/, "")
        var parts = v.split("/").filter(function(p) { return p.length > 0 })
        if (parts.length < 2)
            return ""
        var repo = parts[0] + "/" + parts[1].replace(/\.git$/, "")
        return /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo) ? repo : ""
    }

    function savedRepos(settings) {
        var list = settings ? settings.value("sources.repos") : null
        var out = []
        if (list && list.length !== undefined)
            for (var i = 0; i < list.length; ++i)
                if (typeof list[i] === "string" && list[i].length > 0)
                    out.push(list[i])
        return out
    }

    // A section input hands typed text here; the next filter state, or null to refuse the text.
    function submit(id, input, text, st) {
        if (id !== "repos" || !input || input.action !== "addRepo")
            return null
        var repo = sources.normaliseRepo(text)
        if (repo.length === 0)
            return null
        var saved = sources.savedRepos(Settings)
        if (saved.indexOf(repo) < 0) {
            saved.push(repo)
            Settings.set("sources.repos", saved)
        }
        st.repo = repo
        return st
    }

    // An action chip changes saved data rather than a filter; the next filter state, or null.
    function act(id, chip, st) {
        if (id !== "repos" || chip.action !== "forgetRepo")
            return null
        var saved = sources.savedRepos(Settings).filter(function(r) { return r !== chip.value })
        Settings.set("sources.repos", saved)
        st.repo = saved.length > 0 ? saved[0] : ""
        return st
    }

    // Each section: { n, group, build(state, ctx) -> [chip], input? }.
    function sections(id) {
        switch (id) {
        case "wallhaven": return sources._wallhavenSections
        case "steam":     return sources._steamSections
        case "unsplash":  return sources._unsplashSections
        case "pexels":    return sources._pexelsSections
        case "youtube":   return sources._youtubeSections
        case "repos":     return sources._reposSections
        default:          return []
        }
    }

    readonly property var _wallhavenSections: [
        { n: "01", group: I18n.tr("Content"), build: function(st) { return [
            { kind: "bool", label: I18n.tr("General"), key: "general" },
            { kind: "bool", label: I18n.tr("Anime"),   key: "anime" },
            { kind: "bool", label: I18n.tr("People"),  key: "people" }
        ] } },
        { n: "02", group: I18n.tr("Order"), build: function(st) {
            var out = [
                { kind: "single", order: true, key: "sort", value: "toplist",   label: I18n.tr("Top") },
                { kind: "single", order: true, key: "sort", value: "hot",        label: I18n.tr("Hot") },
                { kind: "single", order: true, key: "sort", value: "date_added", label: I18n.tr("New") },
                { kind: "single", order: true, key: "sort", value: "relevance",  label: I18n.tr("Relevant") },
                { kind: "single", order: true, key: "sort", value: "views",      label: I18n.tr("Views") },
                { kind: "single", order: true, key: "sort", value: "favorites",  label: I18n.tr("Favourites") },
                { kind: "single", order: true, key: "sort", value: "random",     label: I18n.tr("Random") }
            ]
            if (st.sort === "toplist") {
                var ranges = [["1d", I18n.tr("Day")], ["3d", I18n.tr("3 days")], ["1w", I18n.tr("Week")],
                              ["1M", I18n.tr("Month")], ["3M", I18n.tr("3 months")], ["6M", I18n.tr("6 months")],
                              ["1y", I18n.tr("Year")]]
                for (var i = 0; i < ranges.length; ++i)
                    out.push({ kind: "single", order: true, key: "topRange", value: ranges[i][0], label: ranges[i][1] })
            }
            return out
        } },
        { n: "03", group: I18n.tr("Safety and colour"), build: function(st) {
            var out = [
                { kind: "bool", label: I18n.tr("SFW"),     key: "sfw" },
                { kind: "bool", label: I18n.tr("Sketchy"), key: "sketchy" },
                { kind: "bool", label: I18n.tr("NSFW"),    key: "nsfw" }
            ]
            for (var i = 0; i <= 12; ++i)
                out.push({ kind: "swatch", index: i })
            return out
        } },
        { n: "04", group: I18n.tr("Format"), build: function(st) {
            var out = [
                { kind: "single", key: "resMode", value: st.resMode === "exact" ? "min" : "exact",
                  label: st.resMode === "exact" ? I18n.tr("Exact size") : I18n.tr("Min size"), toggleMode: true }
            ]
            var res = [["", I18n.tr("Any")], ["1920x1080", I18n.tr("1080p")], ["2560x1440", I18n.tr("2K")],
                       ["3840x2160", I18n.tr("4K")], ["5120x2880", I18n.tr("5K")], ["7680x4320", I18n.tr("8K")]]
            for (var i = 0; i < res.length; ++i)
                out.push({ kind: "single", key: "resolution", value: res[i][0], label: res[i][1] })
            var ratios = [["", I18n.tr("Any")], ["16x9", "16:9"], ["16x10", "16:10"],
                          ["21x9", "21:9"], ["32x9", "32:9"], ["4x3", "4:3"]]
            for (var j = 0; j < ratios.length; ++j)
                out.push({ kind: "multi", key: "ratios", value: ratios[j][0], label: ratios[j][1] })
            return out
        } },
        { n: "05", group: I18n.tr("Limit"), build: function(st) {
            if (st.resMode === "exact")
                return []
            var res = [["", I18n.tr("Any")], ["1920x1080", I18n.tr("1080p")], ["2560x1440", I18n.tr("2K")],
                       ["3840x2160", I18n.tr("4K")], ["5120x2880", I18n.tr("5K")], ["7680x4320", I18n.tr("8K")]]
            var out = []
            for (var i = 0; i < res.length; ++i)
                out.push({ kind: "single", key: "atmost", value: res[i][0], label: res[i][1] })
            return out
        } },
        { n: "06", group: I18n.tr("Collection"), build: function(st, ctx) {
            var cols = (ctx && ctx.collections) ? ctx.collections : []
            if (cols.length === 0)
                return []
            var out = [{ kind: "single", key: "collection", value: "", label: I18n.tr("All") }]
            for (var i = 0; i < cols.length; ++i)
                out.push({ kind: "single", key: "collection", value: String(cols[i].id), label: cols[i].label })
            return out
        } }
    ]

    readonly property var _steamSections: [
        { n: "01", group: I18n.tr("Order"), build: function(st) {
            var out = [
                { kind: "single", order: true, key: "sort", value: "3",  label: I18n.tr("Trend") },
                { kind: "single", order: true, key: "sort", value: "0",  label: I18n.tr("Top") },
                { kind: "single", order: true, key: "sort", value: "1",  label: I18n.tr("New") },
                { kind: "single", order: true, key: "sort", value: "21", label: I18n.tr("Updated") },
                { kind: "single", order: true, key: "sort", value: "9",  label: I18n.tr("Subscribers") }
            ]
            if (st.sort === "3") {
                var days = [["1", I18n.tr("1 day")], ["3", I18n.tr("3 days")], ["7", I18n.tr("7 days")]]
                for (var i = 0; i < days.length; ++i)
                    out.push({ kind: "single", order: true, key: "trendDays", value: days[i][0], label: days[i][1] })
            }
            return out
        } },
        { n: "02", group: I18n.tr("Media and safety"), build: function(st) { return [
            { kind: "single", key: "type", value: "",      label: I18n.tr("Scene + Video") },
            { kind: "single", key: "type", value: "Scene", label: I18n.tr("Scene") },
            { kind: "single", key: "type", value: "Video", label: I18n.tr("Video") },
            { kind: "single", key: "nsfw", value: false,   label: I18n.tr("SFW") },
            { kind: "single", key: "nsfw", value: true,    label: I18n.tr("NSFW") }
        ] } },
        { n: "03", group: I18n.tr("Resolution"), build: function(st) {
            var res = [["", I18n.tr("Any")], ["1920 x 1080", I18n.tr("1080p")], ["2560 x 1440", I18n.tr("2K")],
                       ["3840 x 2160", I18n.tr("4K")], ["2560 x 1080", I18n.tr("UW")],
                       ["3440 x 1440", I18n.tr("UWQHD")], ["3840 x 1080", I18n.tr("Dual")]]
            var out = []
            for (var i = 0; i < res.length; ++i)
                out.push({ kind: "single", key: "resolution", value: res[i][0], label: res[i][1] })
            return out
        } },
        { n: "04", group: I18n.tr("Subject"), build: function(st) {
            var cats = ["Abstract", "Animal", "Anime", "CGI", "Cyberpunk", "Fantasy", "Game", "Girls",
                        "Guys", "Landscape", "Medieval", "Music", "Nature", "Pixel art", "Relaxing",
                        "Retro", "Sci-Fi", "Technology", "Vehicle"]
            var out = [{ kind: "single", key: "category", value: "", label: I18n.tr("All") }]
            for (var i = 0; i < cats.length; ++i)
                out.push({ kind: "single", key: "category", value: cats[i], label: I18n.tr(cats[i]) })
            return out
        } }
    ]

    readonly property var _unsplashSections: [
        { n: "01", group: I18n.tr("Order"), build: function(st) { return [
            { kind: "single", order: true, key: "order", value: "relevant", label: I18n.tr("Relevant") },
            { kind: "single", order: true, key: "order", value: "latest",   label: I18n.tr("Latest") }
        ] } },
        { n: "02", group: I18n.tr("Safety"), build: function(st) { return [
            { kind: "single", key: "safety", value: "low",  label: I18n.tr("Standard") },
            { kind: "single", key: "safety", value: "high", label: I18n.tr("Strict") }
        ] } },
        { n: "03", group: I18n.tr("Orientation"), build: function(st) { return [
            { kind: "single", key: "orientation", value: "",          label: I18n.tr("Any") },
            { kind: "single", key: "orientation", value: "landscape", label: I18n.tr("Landscape") },
            { kind: "single", key: "orientation", value: "portrait",  label: I18n.tr("Portrait") },
            { kind: "single", key: "orientation", value: "squarish",  label: I18n.tr("Square") }
        ] } },
        { n: "04", group: I18n.tr("Colour"), build: function(st) {
            var cols = [["", I18n.tr("Any colour")], ["black_and_white", I18n.tr("B&W")],
                        ["black", I18n.tr("Black")], ["white", I18n.tr("White")], ["yellow", I18n.tr("Yellow")],
                        ["orange", I18n.tr("Orange")], ["red", I18n.tr("Red")], ["purple", I18n.tr("Purple")],
                        ["magenta", I18n.tr("Magenta")], ["green", I18n.tr("Green")], ["teal", I18n.tr("Teal")],
                        ["blue", I18n.tr("Blue")]]
            var out = []
            for (var i = 0; i < cols.length; ++i)
                out.push({ kind: "single", key: "colour", value: cols[i][0], label: cols[i][1] })
            return out
        } }
    ]

    readonly property var _pexelsSections: [
        { n: "01", group: I18n.tr("Orientation"), build: function(st) { return [
            { kind: "single", key: "orientation", value: "",          label: I18n.tr("Any") },
            { kind: "single", key: "orientation", value: "landscape", label: I18n.tr("Landscape") },
            { kind: "single", key: "orientation", value: "portrait",  label: I18n.tr("Portrait") },
            { kind: "single", key: "orientation", value: "square",    label: I18n.tr("Square") }
        ] } },
        { n: "02", group: I18n.tr("Size"), build: function(st) { return [
            { kind: "single", key: "size", value: "",       label: I18n.tr("Any size") },
            { kind: "single", key: "size", value: "small",  label: I18n.tr("4 MP+") },
            { kind: "single", key: "size", value: "medium", label: I18n.tr("12 MP+") },
            { kind: "single", key: "size", value: "large",  label: I18n.tr("24 MP+") }
        ] } },
        { n: "03", group: I18n.tr("Colour"), build: function(st) {
            var cols = [["", I18n.tr("Any colour")], ["red", I18n.tr("Red")], ["orange", I18n.tr("Orange")],
                        ["yellow", I18n.tr("Yellow")], ["green", I18n.tr("Green")], ["turquoise", I18n.tr("Turquoise")],
                        ["blue", I18n.tr("Blue")], ["violet", I18n.tr("Violet")], ["pink", I18n.tr("Pink")],
                        ["brown", I18n.tr("Brown")], ["black", I18n.tr("Black")], ["gray", I18n.tr("Gray")],
                        ["white", I18n.tr("White")], ["#808080", I18n.tr("Neutral")]]
            var out = []
            for (var i = 0; i < cols.length; ++i)
                out.push({ kind: "single", key: "colour", value: cols[i][0], label: cols[i][1] })
            return out
        } }
    ]

    readonly property var _youtubeSections: [
        { n: "01", group: I18n.tr("Duration"), build: function(st) { return [
            { kind: "single", key: "maxDuration", value: "",     label: I18n.tr("Any") },
            { kind: "single", key: "maxDuration", value: "300",  label: I18n.tr("\u22645m") },
            { kind: "single", key: "maxDuration", value: "600",  label: I18n.tr("\u226410m") },
            { kind: "single", key: "maxDuration", value: "1800", label: I18n.tr("\u226430m") },
            { kind: "single", key: "maxDuration", value: "3600", label: I18n.tr("\u22641h") }
        ] } }
    ]

    readonly property var _reposSections: [
        { n: "01", group: I18n.tr("Repository"),
          input: { action: "addRepo", placeholder: I18n.tr("Add owner/repo or a GitHub link"), glyph: "\uf09b" },
          build: function(st) {
            var saved = sources.savedRepos(Settings)
            var out = []
            for (var i = 0; i < saved.length; ++i)
                out.push({ kind: "single", key: "repo", value: saved[i], label: saved[i] })
            if (st.repo && saved.indexOf(st.repo) >= 0)
                out.push({ kind: "action", action: "forgetRepo", value: st.repo, label: I18n.tr("Forget selected") })
            return out
        } },
        { n: "02", group: I18n.tr("Type"), build: function(st) { return [
            { kind: "single", key: "type", value: "all",    label: I18n.tr("All") },
            { kind: "single", key: "type", value: "live",   label: I18n.tr("Live") },
            { kind: "single", key: "type", value: "images", label: I18n.tr("Images") }
        ] } }
    ]
}
