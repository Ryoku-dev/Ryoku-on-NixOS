package main

import (
	"strconv"
	"strings"

	wm "ryoku-wm"
)

// writeWindowRules renders the neutral desktop.windowRules and
// desktop.appOverrides into mango's windowrule / windowrule-once lines, plus
// the tame-maximise rule the neutral desktop.windows model asks for. The match
// field is class->appid or title; both narrow the rule the way mango's grammar
// does (appid AND title must match).
func writeWindowRules(b *strings.Builder, s mangoStore) {
	var out []string
	for _, r := range s.WindowRules {
		matcher := ruleMatcher(r.Class, r.Title)
		if matcher == "" {
			continue
		}
		param, once, reason := windowRuleParam(r.Action, r.Value)
		if reason != "" || param == "" {
			continue // reported by ruleUnhonored, not dropped silently
		}
		kind := "windowrule"
		if once {
			kind = "windowrule-once"
		}
		out = append(out, kind+"="+param+","+matcher)
	}
	for _, o := range s.AppOverrides {
		matcher := ruleMatcher(o.Class, o.Title)
		if matcher == "" {
			continue
		}
		if o.Opacity > 0 && o.Opacity < 1 {
			out = append(out, "windowrule=focused_opacity:"+confNum(o.Opacity)+","+matcher)
		}
		if o.Rounding == 0 {
			out = append(out, "windowrule=isnoradius:1,"+matcher)
		}
		if o.BorderSize == 0 {
			out = append(out, "windowrule=isnoborder:1,"+matcher)
		}
		if o.Blur == "off" {
			out = append(out, "windowrule=noblur:1,"+matcher)
		}
		if o.Shadow == "off" {
			out = append(out, "windowrule=isnoshadow:1,"+matcher)
		}
		if o.Anim == "off" {
			out = append(out, "windowrule=isnoanimation:1,"+matcher)
		}
	}
	// desktop.windows.tameMaximizeOnOpen has no config lever on 0.17.4: the
	// noopenmaximized rule its docs list is not in this parser (measured:
	// mango -p rejects it). apply reports the loss per store instead, so a
	// user moving from Hyprland or niri sees it and does not chase a missing
	// behaviour. The runtime tamer (the niri watch-fold route) is the follow-up.
	if len(out) == 0 {
		return
	}
	for _, l := range out {
		b.WriteString(l)
		b.WriteString("\n")
	}
	b.WriteString("\n")
}

// ruleMatcher renders the match half of a mango rule.
func ruleMatcher(class, title string) string {
	var parts []string
	if strings.TrimSpace(class) != "" {
		parts = append(parts, "appid:"+class)
	}
	if strings.TrimSpace(title) != "" {
		parts = append(parts, "title:"+title)
	}
	return strings.Join(parts, ",")
}

// windowRuleParam maps a neutral rule action+value onto mango's rule parameter.
// once reports whether mango needs the windowrule-once verb for it. A reason is
// the user copy for an action mango cannot express; the caller reports it and
// the editor never lists it (caps.WindowRuleActions already gates the pick
// list).
func windowRuleParam(action, value string) (param string, once bool, reason string) {
	switch action {
	case "float":
		return "isfloating:1", false, ""
	case "tile":
		return "force_tiled_state:1", false, ""
	case "pin":
		return "isglobal:1", false, ""
	case "fullscreen":
		return "isfullscreen:1", false, ""
	case "maximize":
		return "force_fakemaximize:1", false, ""
	case "center":
		// offsetx/offsety 0,0 pins the floating window's centre to the screen
		// centre, which is what the neutral "center" rule asks for.
		return "offsetx:0,offsety:0", false, ""
	case "size":
		w, h, ok := splitWH(value)
		if !ok {
			return "", false, "a size rule needs WxH."
		}
		return "width:" + w + ",height:" + h, false, ""
	case "move":
		x, y, ok := splitXY(value)
		if !ok {
			return "", false, "a move rule needs X,Y."
		}
		return "offsetx:" + x + ",offsety:" + y, false, ""
	case "workspace":
		n, err := strconv.Atoi(strings.TrimSpace(value))
		if err != nil || n < 1 || n > 9 {
			return "", false, "a workspace rule names a tag number 1-9."
		}
		return "tags:" + strconv.Itoa(n), true, ""
	case "opacity":
		f, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
		if err != nil || f <= 0 || f > 1 {
			return "", false, "an opacity rule takes 0.0-1.0."
		}
		return "focused_opacity:" + confNum(f), false, ""
	case "noblur":
		return "noblur:1", false, ""
	case "noborder":
		return "isnoborder:1", false, ""
	case "noshadow":
		return "isnoshadow:1", false, ""
	case "norounding":
		return "isnoradius:1", false, ""
	case "noanim":
		return "isnoanimation:1", false, ""
	case "nofocus":
		return "isopensilent:1", true, ""
	default:
		return "", false, "mango has no matching window rule."
	}
}

func splitWH(v string) (string, string, bool) {
	parts := strings.Split(strings.ToLower(strings.TrimSpace(v)), "x")
	if len(parts) != 2 {
		return "", "", false
	}
	w := strings.TrimSpace(parts[0])
	h := strings.TrimSpace(parts[1])
	if _, err := strconv.Atoi(w); err != nil {
		return "", "", false
	}
	if _, err := strconv.Atoi(h); err != nil {
		return "", "", false
	}
	return w, h, true
}

func splitXY(v string) (string, string, bool) {
	parts := strings.Split(strings.TrimSpace(v), ",")
	if len(parts) != 2 {
		return "", "", false
	}
	x := strings.TrimSpace(parts[0])
	y := strings.TrimSpace(parts[1])
	for _, n := range []string{x, y} {
		if _, err := strconv.Atoi(n); err != nil {
			return "", "", false
		}
	}
	return x, y, true
}

// writeLayerRules renders the wm.mango.layerRules exclusives as mango layerrule
// lines. Only fields mango expresses are emitted.
func writeLayerRules(b *strings.Builder, rules []LayerRule) {
	if len(rules) == 0 {
		return
	}
	for _, r := range rules {
		if strings.TrimSpace(r.Namespace) == "" {
			continue
		}
		var parts []string
		parts = append(parts, "layer_name:"+r.Namespace)
		if r.Blur == "off" {
			parts = append(parts, "noblur:1")
		}
		if r.Shadow == "off" {
			parts = append(parts, "noshadow:1")
		}
		b.WriteString("layerrule=" + strings.Join(parts, ",") + "\n")
	}
	b.WriteString("\n")
}

// ruleUnhonored reports every neutral rule whose action mango cannot express,
// so a store carried from Hyprland says what it lost rather than dropping it.
func ruleUnhonored(rules []WindowRule) []wm.Unhonored {
	var out []wm.Unhonored
	for _, r := range rules {
		if _, _, reason := windowRuleParam(r.Action, r.Value); reason != "" {
			out = append(out, wm.Unhonored{
				Key:    "desktop.windowRules." + r.Action,
				Reason: reason,
			})
		}
	}
	return out
}
