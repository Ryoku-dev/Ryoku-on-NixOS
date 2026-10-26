// Which connectors exist and what is plugged into each: all that decides which
// monitors answer DDC/CI. Outputs are re-emitted on workspace and focus changes,
// and mode, scale and position do not change the answer either.
function connectorSignature(outputs) {
    var keys = [];
    var count = outputs ? outputs.length : 0;
    for (var i = 0; i < count; i++) {
        var o = outputs[i];
        if (o)
            keys.push([o.name || "", o.make || "", o.model || ""].join("\u001f"));
    }
    return keys.sort().join("\u001e");
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { connectorSignature };
