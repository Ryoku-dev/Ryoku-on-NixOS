// Grammar: || and && over !, parentheses, ==, !=, in {a, b}, bare truthy refs, cap.* and available.*. A malformed expression fails open (visible).

function evaluate(expr, ctx) {
    if (expr === undefined || expr === null)
        return true;
    if (typeof expr !== "string")
        return !!expr;
    var s = expr.trim();
    if (s.length === 0)
        return true;
    try {
        var p = { toks: _lex(s), i: 0 };
        var node = _parseOr(p);
        return !!_eval(node, ctx);
    } catch (e) {
        return true;
    }
}

// cap.* is false when absent; available.* is true when absent.
function makeCtx(settings) {
    return {
        value: function (key) {
            var v = settings.value(key);
            if ((v === undefined || v === null) && key.indexOf(".") < 0)
                v = settings.value("components.wallpaperSelector." + key);
            return v;
        },
        cap: function (name) { return settings.cap(name); },
        avail: function (name) { return settings.available(name); }
    };
}

function _lex(s) {
    var toks = [];
    var i = 0, n = s.length;
    while (i < n) {
        var c = s.charAt(i);
        if (c === " " || c === "\t" || c === "\n" || c === "\r") { i++; continue; }
        if (c === "(" || c === ")" || c === "{" || c === "}" || c === ",") { toks.push({ t: c }); i++; continue; }
        if (c === "&" && s.charAt(i + 1) === "&") { toks.push({ t: "&&" }); i += 2; continue; }
        if (c === "|" && s.charAt(i + 1) === "|") { toks.push({ t: "||" }); i += 2; continue; }
        if (c === "=" && s.charAt(i + 1) === "=") { toks.push({ t: "==" }); i += 2; continue; }
        if (c === "!" && s.charAt(i + 1) === "=") { toks.push({ t: "!=" }); i += 2; continue; }
        if (c === "!") { toks.push({ t: "!" }); i++; continue; }
        var j = i;
        while (j < n) {
            var d = s.charAt(j);
            if (d === " " || d === "\t" || d === "\n" || d === "\r"
                || d === "(" || d === ")" || d === "{" || d === "}" || d === ","
                || d === "&" || d === "|" || d === "=" || d === "!")
                break;
            j++;
        }
        toks.push({ t: "word", v: s.substring(i, j) });
        i = j;
    }
    return toks;
}

function _peek(p) { return p.i < p.toks.length ? p.toks[p.i] : null; }
function _next(p) { return p.toks[p.i++]; }

function _parseOr(p) {
    var l = _parseAnd(p);
    while (_peek(p) && _peek(p).t === "||") { _next(p); l = { op: "||", l: l, r: _parseAnd(p) }; }
    return l;
}
function _parseAnd(p) {
    var l = _parseUnary(p);
    while (_peek(p) && _peek(p).t === "&&") { _next(p); l = { op: "&&", l: l, r: _parseUnary(p) }; }
    return l;
}
function _parseUnary(p) {
    if (_peek(p) && _peek(p).t === "!") { _next(p); return { op: "!", x: _parseUnary(p) }; }
    return _parsePrimary(p);
}
function _parsePrimary(p) {
    var tk = _peek(p);
    if (!tk)
        throw "eof";
    if (tk.t === "(") {
        _next(p);
        var e = _parseOr(p);
        if (_peek(p) && _peek(p).t === ")") _next(p);
        return e;
    }
    if (tk.t === "word") {
        _next(p);
        var ref = tk.v;
        var nxt = _peek(p);
        if (nxt && (nxt.t === "==" || nxt.t === "!=")) {
            var op = _next(p).t;
            var rhs = _next(p);
            return { op: op, ref: ref, lit: rhs && rhs.t === "word" ? rhs.v : "" };
        }
        if (nxt && nxt.t === "word" && nxt.v === "in") {
            _next(p);
            var set = [];
            if (_peek(p) && _peek(p).t === "{") {
                _next(p);
                while (_peek(p) && _peek(p).t !== "}") {
                    var w = _next(p);
                    if (w.t === "word") set.push(w.v);
                }
                if (_peek(p) && _peek(p).t === "}") _next(p);
            }
            return { op: "in", ref: ref, set: set };
        }
        return { op: "truthy", ref: ref };
    }
    throw "unexpected";
}

function _resolve(ref, ctx) {
    if (ref.indexOf("cap.") === 0)
        return ctx.cap(ref.substring(4));
    if (ref.indexOf("available.") === 0)
        return ctx.avail(ref.substring(10));
    return ctx.value(ref);
}

function _toBool(v) {
    if (v === true) return true;
    if (v === false || v === undefined || v === null) return false;
    if (typeof v === "number") return v !== 0;
    if (typeof v === "string") return v !== "" && v !== "false" && v !== "0";
    if (Array.isArray(v)) return v.length > 0;
    if (typeof v === "object") return Object.keys(v).length > 0;
    return !!v;
}

function _litEq(v, lit) {
    if (lit === "true") return _toBool(v) === true;
    if (lit === "false") return _toBool(v) === false;
    var nv = Number(v), nl = Number(lit);
    if (!isNaN(nv) && !isNaN(nl) && v !== "" && v !== null && v !== undefined)
        return nv === nl;
    return String(v) === lit;
}

function _eval(node, ctx) {
    switch (node.op) {
    case "||": return _eval(node.l, ctx) || _eval(node.r, ctx);
    case "&&": return _eval(node.l, ctx) && _eval(node.r, ctx);
    case "!": return !_eval(node.x, ctx);
    case "==": return _litEq(_resolve(node.ref, ctx), node.lit);
    case "!=": return !_litEq(_resolve(node.ref, ctx), node.lit);
    case "in": {
        var v = _resolve(node.ref, ctx);
        for (var k = 0; k < node.set.length; k++)
            if (_litEq(v, node.set[k])) return true;
        return false;
    }
    case "truthy": return _toBool(_resolve(node.ref, ctx));
    }
    return false;
}
