.pragma library

// Paths, URIs and labels for the file widgets (Files, Screenshots, Shelf, Send).

function pathFromUrl(url) {
    var s = String(url || "");
    if (s.indexOf("file://") === 0) {
        s = s.slice(7);
        try {
            s = decodeURIComponent(s);
        } catch (e) {
        }
    }
    return s;
}

function expandPath(path, home) {
    var value = pathFromUrl(path).trim();
    var homePath = pathFromUrl(home).replace(/\/+$/, "");
    if (value === "~")
        return homePath;
    if (value.indexOf("~/") === 0)
        return homePath + value.slice(1);
    if (value.indexOf("$HOME/") === 0)
        return homePath + value.slice(5);
    return value;
}

// A file:// URI another app accepts, encoded one path segment at a time.
function fileUri(path) {
    var value = pathFromUrl(path);
    return "file:///" + value.replace(/^\/+/, "").split("/").map(function (segment) {
        return encodeURIComponent(segment);
    }).join("/");
}

function uriList(paths) {
    var uris = (paths || []).map(fileUri);
    return uris.length > 0 ? uris.join("\r\n") + "\r\n" : "";
}

function baseName(path) {
    var parts = String(path || "").split("/").filter(function (s) { return s.length > 0; });
    return parts.length > 0 ? parts[parts.length - 1] : "";
}

function isImage(path) {
    return /\.(png|jpe?g|webp|gif|bmp|svg|avif|tiff?)$/i.test(String(path || ""));
}

function imageMime(path) {
    var p = String(path || "").toLowerCase();
    if (/\.jpe?g$/.test(p))
        return "image/jpeg";
    if (/\.webp$/.test(p))
        return "image/webp";
    if (/\.gif$/.test(p))
        return "image/gif";
    if (/\.bmp$/.test(p))
        return "image/bmp";
    if (/\.svg$/.test(p))
        return "image/svg+xml";
    if (/\.avif$/.test(p))
        return "image/avif";
    if (/\.tiff?$/.test(p))
        return "image/tiff";
    return "image/png";
}

function symbolFor(path) {
    var p = String(path || "").toLowerCase();
    if (isImage(p))
        return "image";
    if (/\.(mp3|flac|ogg|opus|wav|aac|m4a)$/.test(p))
        return "music_note";
    if (/\.(mp4|mkv|webm|avi|mov)$/.test(p))
        return "movie";
    if (p.endsWith(".pdf"))
        return "picture_as_pdf";
    if (/\.(txt|md|rst|log|json|csv)$/.test(p))
        return "description";
    if (/\.(zip|tar|gz|xz|zst|rar|7z)$/.test(p))
        return "folder_zip";
    if (/\.(appimage|rpm|deb|flatpakref|exe|msi)$/.test(p))
        return "deployed_code";
    var last = baseName(p);
    return last.indexOf(".") >= 0 ? "draft" : "folder";
}

// "just now", "5 min", "3 h", "2 d" — how long ago a file arrived.
function age(ms, now, tr) {
    var t = tr || function (s) { return s; };
    if (!isFinite(ms) || ms <= 0 || !isFinite(now))
        return "";
    var seconds = Math.max(0, Math.round((now - ms) / 1000));
    if (seconds < 60)
        return t("just now");
    var minutes = Math.round(seconds / 60);
    if (minutes < 60)
        return t("%1 min ago").replace("%1", String(minutes));
    var hours = Math.round(minutes / 60);
    if (hours < 24)
        return t("%1 h ago").replace("%1", String(hours));
    return t("%1 d ago").replace("%1", String(Math.round(hours / 24)));
}

// Paths from a drop (urls, or a text/uri-list), deduplicated.
function dedupe(paths) {
    var seen = {};
    var out = [];
    for (var i = 0; i < (paths || []).length; i++) {
        var p = pathFromUrl(paths[i]);
        if (!p || seen[p])
            continue;
        seen[p] = true;
        out.push(p);
    }
    return out;
}
