// Templated controls (keys with .N or .{idx}) and their add/remove actions fold into list blocks.

var ACTION_ARRAY = {
    AddPostCommand: "postProcessing",
    RemovePostCommand: "postProcessing",
    AddIntegration: "integrations",
    RemoveIntegration: "integrations",
    CreateResolutionPresetBand: "filterBar.resolutionPresets",
    RemoveResolutionPreset: "filterBar.resolutionPresets",
    RemoveSemanticModel: "semantic.models",
    DeleteSemanticModel: "semantic.models"
};

function _actionId(action) {
    if (Array.isArray(action))
        action = action.length ? action[0] : "";
    if (typeof action !== "string")
        return "";
    var i = action.indexOf("(");
    return i < 0 ? action : action.substring(0, i);
}

function _templateBase(key) {
    if (typeof key !== "string")
        return null;
    var iN = key.indexOf(".N");
    if (iN >= 0 && (key.length === iN + 2 || key.charAt(iN + 2) === "."))
        return key.substring(0, iN);
    var iB = key.indexOf(".{idx}");
    if (iB >= 0)
        return key.substring(0, iB);
    return null;
}

function _leaf(key) {
    var m = /\.(?:N|\{idx\})\.(.+)$/.exec(key || "");
    return m ? m[1] : "";
}

function isDisplayControl(control) {
    if (control.perDisplay === true)
        return true;
    var k = control.id || control.key || "";
    return typeof k === "string" && k.indexOf("<output>") >= 0;
}

// Only these fold into list blocks; other templated ids (shader scopes, keybind conflicts) render in place.
var KNOWN_LISTS = {
    "filterBar.resolutionPresets": true,
    "semantic.models": true,
    "postProcessing": true,
    "integrations": true
};

function _groupBase(control) {
    var base = _templateBase(control.key) || _templateBase(control.id);
    if (base && KNOWN_LISTS[base])
        return base;
    var id = _actionId(control.action);
    if (id && ACTION_ARRAY[id])
        return ACTION_ARRAY[id];
    return null;
}

function buildRows(section) {
    var controls = (section && section.controls) ? section.controls : [];
    var out = [];
    var groups = ({});
    var displayGroup = null;
    var sectionGroups = (section && section.groups) ? section.groups : [];
    var emittedGroups = ({});

    for (var i = 0; i < controls.length; i++) {
        var c = controls[i];
        if (c.group && !emittedGroups[c.group]) {
            for (var gi = 0; gi < sectionGroups.length; gi++) {
                if (sectionGroups[gi].id === c.group) {
                    out.push({ type: "group", id: c.group, title: sectionGroups[gi].title });
                    emittedGroups[c.group] = true;
                    break;
                }
            }
        }

        if (isDisplayControl(c)) {
            if (!displayGroup) {
                displayGroup = { type: "display", controls: [] };
                out.push(displayGroup);
            }
            displayGroup.controls.push(c);
            continue;
        }

        var base = _groupBase(c);
        if (!base) {
            out.push({ type: "control", control: c, group: emittedGroups[c.group] ? c.group : "" });
            continue;
        }

        var g = groups[base];
        if (!g) {
            g = { type: "list", base: base, itemLabel: "", listControl: null,
                  fields: [], itemActions: [], addControl: null,
                  daemon: base === "semantic.models" };
            groups[base] = g;
            out.push(g);
        }

        var isList = c.kind === "list";
        var isAction = c.kind === "action" || c.action !== undefined;
        var leaf = _leaf(c.key || c.id || "");

        if (isList && leaf === "") {
            g.listControl = c;
            if (c.label)
                g.itemLabel = c.label;
        } else if (isAction) {
            var aid = _actionId(c.action);
            if (aid.indexOf("Add") === 0 || aid.indexOf("Create") === 0)
                g.addControl = c;
            else
                g.itemActions.push(c);
        } else if (leaf !== "") {
            g.fields.push(c);
        }
    }

    return out;
}
