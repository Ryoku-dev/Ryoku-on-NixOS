--[[
rebinds.lua is generated from the neutral store's desktop.keybindRebinds and
desktop.keybindDisabled. It maps a shipped chord to a user-chosen one, e.g.
{ ["SUPER + Q"] = "SUPER + X" }, or to false when the bind is switched off.

K() wraps every bind's key argument, so a rebind is a pure key swap: the default
chord is never registered and the dispatcher never moves. A false result makes
the wrapped hl.bind a no-op. Absent or malformed, K() is the identity and every
shortcut keeps its shipped default.

Every module that registers a bind must go through K(), or a rebind would add a
second handler instead of moving the first.
]]
local ok, rebinds = pcall(require, "rebinds")
if not ok or type(rebinds) ~= "table" then rebinds = {} end

local bind = hl.bind
hl.bind = function(key, ...)
    if key == false then return end
    return bind(key, ...)
end

return function(k)
    local v = rebinds[k]
    if v == nil then return k end
    return v
end
