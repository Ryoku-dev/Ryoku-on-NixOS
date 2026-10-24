package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	wm "ryoku-wm"
)

// The neutral settings store as mango reads it: the desktop.* fields mango can
// express, the wm.mango.* exclusives that have no neutral key, the desktop.json
// codec that fills them, and the mango defaults the Hub overlays user values on.
// Only the leaves mango honours are modelled; apply reports everything else in
// the store as unhonored rather than parsing it.
//
// settings.conf carries the full effective config, not a diff: the shipped tree
// has no defaults module, so settings.conf and rebinds.conf are the only writers
// of real config. A leaf left out here would boot as stock mango, not Ryoku.

// Appearance: the window-frame, gap, shadow, opacity and blur leaves mango can
// express. Unlike niri, mango's scenefx effects are first-class, so blur and
// per-window dim both land here; the neutral rounding maps to border_radius and
// the neutral shadow range to shadows_size.
type Appearance struct {
	GapsIn               int     `json:"gapsIn"`
	GapsOut              int     `json:"gapsOut"`
	BorderSize           int     `json:"borderSize"`
	Rounding             int     `json:"rounding"`
	ActiveBorder         string  `json:"activeBorder"`
	InactiveBorder       string  `json:"inactiveBorder"`
	BorderFollowsPalette bool    `json:"borderFollowsPalette"`
	Animations           bool    `json:"animations"`
	ActiveOpacity        float64 `json:"activeOpacity"`
	InactiveOpacity      float64 `json:"inactiveOpacity"`
	ShadowEnabled        bool    `json:"shadowEnabled"`
	ShadowRange          int     `json:"shadowRange"`
	ShadowColor          string  `json:"shadowColor"`
	ShadowSpread         int     `json:"shadowSpread"`
	ShadowOffsetX        int     `json:"shadowOffsetX"`
	ShadowOffsetY        int     `json:"shadowOffsetY"`
	DimInactive          bool    `json:"dimInactive"`
	DimStrength          float64 `json:"dimStrength"`
	BlurEnabled          bool    `json:"blurEnabled"`
	BlurSize             int     `json:"blurSize"`
	BlurPasses           int     `json:"blurPasses"`
	BlurNoise            float64 `json:"blurNoise"`
	BlurVibrancy         float64 `json:"blurVibrancy"`
}

// Input: the keyboard, pointer and touchpad leaves mango's config covers.
type Input struct {
	KbLayout           string  `json:"kbLayout"`
	KbVariant          string  `json:"kbVariant"`
	KbOptions          string  `json:"kbOptions"`
	NumlockByDefault   bool    `json:"numlockByDefault"`
	FollowMouse        int     `json:"followMouse"`
	Sensitivity        float64 `json:"sensitivity"`
	AccelProfile       string  `json:"accelProfile"`
	LeftHanded         bool    `json:"leftHanded"`
	MouseNaturalScroll bool    `json:"mouseNaturalScroll"`
	MouseScrollFactor  float64 `json:"mouseScrollFactor"`
	MiddleClickPaste   bool    `json:"middleClickPaste"`
	NaturalScroll      bool    `json:"naturalScroll"`
	TouchScrollFactor  float64 `json:"touchScrollFactor"`
	TapToClick         bool    `json:"tapToClick"`
	TapAndDrag         bool    `json:"tapAndDrag"`
	Clickfinger        bool    `json:"clickfinger"`
	MiddleEmulation    bool    `json:"middleEmulation"`
	DisableWhileTyping bool    `json:"disableWhileTyping"`
	RepeatRate         int     `json:"repeatRate"`
	RepeatDelay        int     `json:"repeatDelay"`
}

type Cursor struct {
	Theme           string `json:"theme"`
	Size            int    `json:"size"`
	InactiveTimeout int    `json:"inactiveTimeout"`
	HideOnKeyPress  bool   `json:"hideOnKeyPress"`
}

type EnvVar struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// WindowRule = one user rule: optional app-id/title match + one action.
type WindowRule struct {
	Class  string `json:"class"`
	Title  string `json:"title"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

// AppOverride: per-app appearance. Numeric fields use -1 for "inherit".
type AppOverride struct {
	Class      string  `json:"class"`
	Title      string  `json:"title"`
	Opacity    float64 `json:"opacity"`
	Rounding   int     `json:"rounding"`
	BorderSize int     `json:"borderSize"`
	Blur       string  `json:"blur"`
	Shadow     string  `json:"shadow"`
	Dim        string  `json:"dim"`
	Anim       string  `json:"anim"`
	Opaque     string  `json:"opaque"`
}

type Autostart struct {
	Command string `json:"command"`
}

// Keybind = a user shortcut. action "exec" runs Value; the window actions take
// no value.
type Keybind struct {
	Keys    string `json:"keys"`
	Action  string `json:"action"`
	Value   string `json:"value"`
	Release bool   `json:"release,omitempty"`
}

// Windows is the neutral window-behaviour block. TameMaximizeOnOpen resets a
// window an app opens maximised back to an ordinary tile with the gaps kept:
// mango's force_fakemaximize/noopenmaximized rules carry the intent.
type Windows struct {
	TameMaximizeOnOpen bool `json:"tameMaximizeOnOpen"`
}

// AnimSpec is one mango animation's tuning: a type plus duration and curve.
// Mode "default" emits nothing so mango keeps its own; "off" disables.
type AnimSpec struct {
	Mode       string `json:"mode"`
	DurationMs int    `json:"durationMs"`
	Curve      string `json:"curve"`
	Type       string `json:"type"`
}

// LayerRule is one user layer-shell rule: a namespace match plus the fields
// mango's layerrule can set on a matching surface.
type LayerRule struct {
	Namespace    string  `json:"namespace"`
	Opacity      float64 `json:"opacity"`
	CornerRadius int     `json:"cornerRadius"`
	Blur         string  `json:"blur"`
	Shadow       string  `json:"shadow"`
	BlockOut     bool    `json:"blockOut"`
	BabaIsFloat  bool    `json:"babaIsFloat"`
}

// Mango holds the wm.mango.* exclusives: mango behaviours with no neutral key.
// This is the mango twin of wm.niri.*, so the Hub can surface them without
// every other compositor pretending to have them.
type Mango struct {
	// Tag count: mango's workspace slots. The neutral model assumes ten; mango
	// binds digits 1..0 onto tag_num tags, so 9 is the shipped truth.
	TagNum int `json:"tagNum"`
	// Master/stack tuning for the tile family.
	DefaultMFact   float64 `json:"defaultMfact"`
	DefaultNMaster int     `json:"defaultNMaster"`
	NewIsMaster    bool    `json:"newIsMaster"`
	// Scroller tuning: the niri twin of preset column widths, so Super+R steps
	// proportions rather than dragging.
	ScrollerStructs           int         `json:"scrollerStructs"`
	ScrollerDefaultProportion float64     `json:"scrollerDefaultProportion"`
	ScrollerFocusCenter       bool        `json:"scrollerFocusCenter"`
	ScrollerProportionPreset  Proportions `json:"scrollerProportionPreset"`
	// Default layout for every tag, expanded into tagrules by apply.
	DefaultLayout string `json:"defaultLayout"`
	// Smart gaps: inner gaps collapse on a single window.
	SmartGaps bool `json:"smartGaps"`
	// Border and single-window behaviour.
	NoBorderWhenSingle bool `json:"noBorderWhenSingle"`
	NoRadiusWhenSingle bool `json:"noRadiusWhenSingle"`
	// Focus behaviour.
	FocusOnActivate   bool `json:"focusOnActivate"`
	FocusCrossMonitor bool `json:"focusCrossMonitor"`
	FocusCrossTag     bool `json:"focusCrossTag"`
	WarpCursor        bool `json:"warpCursor"`
	ViewCurrentToBack bool `json:"viewCurrentToBack"`
	// Overview (hycov-style) tuning.
	EnableHotarea  bool `json:"enableHotarea"`
	HotareaSize    int  `json:"hotareaSize"`
	OverviewGapIn  int  `json:"overviewGapIn"`
	OverviewGapOut int  `json:"overviewGapOut"`
	// Dim tuning colours.
	DimFocusedColor   string `json:"dimFocusedColor"`
	DimUnfocusedColor string `json:"dimFocusedColorDup"`
	// Urgent colour for the bar's attention pill.
	UrgentColor string `json:"urgentColor"`
	// Scratchpad sizing.
	ScratchpadWidthRatio  float64 `json:"scratchpadWidthRatio"`
	ScratchpadHeightRatio float64 `json:"scratchpadHeightRatio"`
	// XWayland scaling stance: ignore global scale to keep X11 sharp.
	XWaylandIgnoreScale bool `json:"xwaylandIgnoreScale"`
	// Tearing (the game-mode lever lives neutral; this is the global gate).
	AllowTearing string `json:"allowTearing"`
	// Idle inhibit policy.
	IdleInhibitIgnoreVisible bool        `json:"idleInhibitIgnoreVisible"`
	LayerRules               []LayerRule `json:"layerRules"`
	// Tag and focus behaviours with no neutral twin. Segments (dragCorner,
	// allowShortcutsInhibit, the scroll and send-event methods, buttonMap,
	// hotareaCorner, the dwindle split directions, tagAnimationDirection,
	// the layer animation types) are stored as the string mango's config
	// speaks, the way AllowTearing already is: the Hub's Seg control writes
	// the chosen option verbatim, so a string field is what round-trips.
	TagGather                 bool   `json:"tagGather"`
	TagCarousel               bool   `json:"tagCarousel"`
	ExchangeCrossMonitor      bool   `json:"exchangeCrossMonitor"`
	FocusdirOnlyZoneOverlap   bool   `json:"focusdirOnlyZoneOverlap"`
	FloatFullToTop            bool   `json:"floatFullToTop"`
	DragTileToTile            bool   `json:"dragTileToTile"`
	DragTileSmall             bool   `json:"dragTileSmall"`
	DragWarpCursor            bool   `json:"dragWarpCursor"`
	DragCorner                string `json:"dragCorner"`
	EnableFloatingSnap        bool   `json:"enableFloatingSnap"`
	SnapDistance              int    `json:"snapDistance"`
	AxisBindApplyTimeout      int    `json:"axisBindApplyTimeout"`
	XWaylandPersistence       bool   `json:"xwaylandPersistence"`
	SyncobjEnable             bool   `json:"syncobjEnable"`
	AllowLockTransparent      bool   `json:"allowLockTransparent"`
	AllowShortcutsInhibit     string `json:"allowShortcutsInhibit"`
	IdleInhibitWhenFullscreen bool   `json:"idleInhibitWhenFullscreen"`
	// Layout-engine tuning: master/stack, dwindle, scroller, overcircle.
	CenterMasterOverspread          bool    `json:"centerMasterOverspread"`
	CenterWhenSingleStack           bool    `json:"centerWhenSingleStack"`
	DwindleSmartSplit               bool    `json:"dwindleSmartSplit"`
	DwindleSmartResize              bool    `json:"dwindleSmartResize"`
	DwindleManualSplit              bool    `json:"dwindleManualSplit"`
	DwindlePreserveSplit            bool    `json:"dwindlePreserveSplit"`
	DwindleDropSimpleSplit          bool    `json:"dwindleDropSimpleSplit"`
	DwindleHSplit                   string  `json:"dwindleHSplit"`
	DwindleVSplit                   string  `json:"dwindleVSplit"`
	DwindleSplitRatio               float64 `json:"dwindleSplitRatio"`
	ScrollerPreferCenter            bool    `json:"scrollerPreferCenter"`
	ScrollerPreferOverspread        bool    `json:"scrollerPreferOverspread"`
	ScrollerIgnoreProportionSingle  bool    `json:"scrollerIgnoreProportionSingle"`
	ScrollerDefaultProportionSingle float64 `json:"scrollerDefaultProportionSingle"`
	EdgeScrollerPointerFocus        bool    `json:"edgeScrollerPointerFocus"`
	EdgeScrollerFocusAllowSpeed     float64 `json:"edgeScrollerFocusAllowSpeed"`
	OvercircleCenterRatio           float64 `json:"overcircleCenterRatio"`
	// Overview (hycov-style) corner and fullscreen behaviour.
	HotareaCorner              string `json:"hotareaCorner"`
	HotareaDisableOnFullscreen bool   `json:"hotareaDisableOnFullscreen"`
	// Scratchpad and special-tag tuning.
	SingleScratchpad       bool    `json:"singleScratchpad"`
	ScratchpadCrossMonitor bool    `json:"scratchpadCrossMonitor"`
	SpecialDim             float64 `json:"specialDim"`
	SpecialGapsIn          int     `json:"specialGapsIn"`
	SpecialGapsOut         int     `json:"specialGapsOut"`
	// Animation envelope tuning beyond the per-event type/duration/curve.
	FadeinBeginOpacity      float64 `json:"fadeinBeginOpacity"`
	FadeoutBeginOpacity     float64 `json:"fadeoutBeginOpacity"`
	ZoomInitialRatio        float64 `json:"zoomInitialRatio"`
	ZoomEndRatio            float64 `json:"zoomEndRatio"`
	TagAnimationDirection   string  `json:"tagAnimationDirection"`
	LayerAnimationTypeOpen  string  `json:"layerAnimationTypeOpen"`
	LayerAnimationTypeClose string  `json:"layerAnimationTypeClose"`
	// Device-level input leaves with no neutral twin (the neutral desktop.input
	// block covers accel, tap, and natural scroll; these are mango's own).
	TouchEnable               bool    `json:"touchEnable"`
	TouchMouseEmulation       bool    `json:"touchMouseEmulation"`
	SwipeMinThreshold         int     `json:"swipeMinThreshold"`
	GestureLive               bool    `json:"gestureLive"`
	GestureSwipeDistance      int     `json:"gestureSwipeDistance"`
	GestureSwipeCancelRatio   float64 `json:"gestureSwipeCancelRatio"`
	GestureSwipeMinSpeedForce int     `json:"gestureSwipeMinSpeedToForce"`
	MouseScrollMethod         string  `json:"mouseScrollMethod"`
	MouseScrollButton         int     `json:"mouseScrollButton"`
	MouseSendEventsMode       string  `json:"mouseSendEventsMode"`
	TrackpadScrollMethod      string  `json:"trackpadScrollMethod"`
	TrackpadScrollButton      int     `json:"trackpadScrollButton"`
	TrackpadSendEventsMode    string  `json:"trackpadSendEventsMode"`
	ButtonMap                 string  `json:"buttonMap"`
	// Frame colours for the states the neutral palette does not name.
	RootColor       string `json:"rootColor"`
	DropColor       string `json:"dropColor"`
	SplitColor      string `json:"splitColor"`
	MaximizeColor   string `json:"maximizeScreenColor"`
	ScratchpadColor string `json:"scratchpadColor"`
	GlobalColor     string `json:"globalColor"`
	OverlayColor    string `json:"overlayColor"`
	Anim            struct {
		Open  AnimSpec `json:"open"`
		Close AnimSpec `json:"close"`
		Move  AnimSpec `json:"move"`
		Tag   AnimSpec `json:"tag"`
	} `json:"anim"`
}

// Proportions carries as a comma-separated string like niri's preset widths.
type Proportions []float64

func (p Proportions) MarshalJSON() ([]byte, error) {
	parts := make([]string, len(p))
	for i, v := range p {
		parts[i] = numStr(v)
	}
	return json.Marshal(strings.Join(parts, ", "))
}

func (p *Proportions) UnmarshalJSON(b []byte) error {
	b = []byte(strings.TrimSpace(string(b)))
	if len(b) == 0 || string(b) == "null" {
		*p = nil
		return nil
	}
	if b[0] == '[' {
		var nums []float64
		if err := json.Unmarshal(b, &nums); err != nil {
			return err
		}
		*p = nums
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	var out Proportions
	for _, tok := range strings.FieldsFunc(s, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' }) {
		scale := 1.0
		if strings.HasSuffix(tok, "%") {
			tok = strings.TrimSuffix(tok, "%")
			scale = 0.01
		}
		if v, err := strconv.ParseFloat(tok, 64); err == nil {
			out = append(out, v*scale)
		}
	}
	*p = out
	return nil
}

type mangoStore struct {
	Appearance     Appearance        `json:"appearance"`
	Input          Input             `json:"input"`
	Cursor         Cursor            `json:"cursor"`
	Windows        Windows           `json:"windows"`
	Env            []EnvVar          `json:"env"`
	WindowRules    []WindowRule      `json:"windowRules"`
	AppOverrides   []AppOverride     `json:"appOverrides"`
	Autostart      []Autostart       `json:"autostart"`
	Keybinds       []Keybind         `json:"keybinds"`
	Apps           map[string]string `json:"apps,omitempty"`
	KeybindRebinds map[string]string `json:"keybindRebinds,omitempty"`
	Unbinds        []string          `json:"unbinds,omitempty"`
	Mango          Mango             `json:"-"`
}

// neutralStore is desktop.json on disk: { "desktop": {...}, "wm": { "<name>":
// {...} } }. WM is keyed by compositor so apply can see, and preserve, another
// compositor's exclusives without parsing them.
type neutralStore struct {
	Desktop map[string]json.RawMessage `json:"desktop"`
	WM      map[string]json.RawMessage `json:"wm"`
}

func defaultAnim() AnimSpec {
	return AnimSpec{Mode: "default", DurationMs: 400, Curve: "0.46,1.0,0.29,1", Type: "slide"}
}

// defaultStore is mango's baseline. It matches the Ryoku look on the other
// compositors where mango has the same knob (gaps 16, border 4, radius 6 like
// the shipped mango default, animations on); the pointer and keyboard leaves
// match the recommended session; the wm.mango block is the Ryoku look for the
// settings mango owns alone.
func defaultStore() mangoStore {
	s := mangoStore{
		Appearance: Appearance{
			GapsIn: 16, GapsOut: 16, BorderSize: 4, Rounding: 6,
			ActiveBorder: "#e0563b", InactiveBorder: "#313a4d", BorderFollowsPalette: true, Animations: true,
			ActiveOpacity: 1, InactiveOpacity: 1,
			ShadowEnabled: false, ShadowRange: 10, ShadowColor: "#000000",
			ShadowSpread: 0, ShadowOffsetX: 0, ShadowOffsetY: 0,
			DimInactive: false, DimStrength: 0.33,
			BlurEnabled: false, BlurSize: 5, BlurPasses: 2, BlurNoise: 0.02, BlurVibrancy: 1.2,
		},
		Windows: Windows{TameMaximizeOnOpen: true},
		Input: Input{
			KbLayout: "us", NumlockByDefault: false, FollowMouse: 1,
			Sensitivity: 0, AccelProfile: "", LeftHanded: false,
			MouseNaturalScroll: false, MouseScrollFactor: 1, MiddleClickPaste: true,
			NaturalScroll: true, TouchScrollFactor: 1,
			TapToClick: true, TapAndDrag: true, Clickfinger: false,
			MiddleEmulation: false, DisableWhileTyping: true,
			RepeatRate: 25, RepeatDelay: 600,
		},
		Cursor:       Cursor{Theme: "Bibata-Modern-Ice", Size: 24, InactiveTimeout: 0, HideOnKeyPress: false},
		Env:          []EnvVar{},
		WindowRules:  []WindowRule{},
		AppOverrides: []AppOverride{},
		Autostart:    []Autostart{},
		Keybinds:     []Keybind{},
	}
	s.Mango = Mango{
		TagNum:                    9,
		DefaultMFact:              0.55,
		DefaultNMaster:            1,
		NewIsMaster:               true,
		ScrollerStructs:           20,
		ScrollerDefaultProportion: 0.8,
		ScrollerProportionPreset:  Proportions{0.5, 0.8, 1.0},
		DefaultLayout:             "tile",
		SmartGaps:                 false,
		FocusOnActivate:           true,
		WarpCursor:                true,
		EnableHotarea:             false,
		HotareaSize:               10,
		OverviewGapIn:             5,
		OverviewGapOut:            30,
		UrgentColor:               "#9b0000",
		ScratchpadWidthRatio:      0.8,
		ScratchpadHeightRatio:     0.9,
		XWaylandIgnoreScale:       true,
		AllowTearing:              "0",
		DimFocusedColor:           "#00000000",
		DimUnfocusedColor:         "#00000055",
		LayerRules:                []LayerRule{},

		// The rest of the wm.mango block is mango's compiled baseline, read
		// from its own default_config(): emitting the truth means the Hub
		// rows show what an untouched mango does, and settings.conf stays a
		// complete picture of the session.
		TagGather:                 false,
		TagCarousel:               false,
		ExchangeCrossMonitor:      false,
		FocusdirOnlyZoneOverlap:   true,
		FloatFullToTop:            false,
		DragTileToTile:            true,
		DragTileSmall:             true,
		DragWarpCursor:            true,
		DragCorner:                "3",
		EnableFloatingSnap:        false,
		SnapDistance:              30,
		AxisBindApplyTimeout:      100,
		XWaylandPersistence:       true,
		SyncobjEnable:             true,
		AllowLockTransparent:      false,
		AllowShortcutsInhibit:     "1",
		IdleInhibitWhenFullscreen: false,

		CenterMasterOverspread:          false,
		CenterWhenSingleStack:           true,
		DwindleSmartSplit:               false,
		DwindleSmartResize:              false,
		DwindleManualSplit:              false,
		DwindlePreserveSplit:            false,
		DwindleDropSimpleSplit:          true,
		DwindleHSplit:                   "1",
		DwindleVSplit:                   "1",
		DwindleSplitRatio:               0.5,
		ScrollerPreferCenter:            false,
		ScrollerPreferOverspread:        true,
		ScrollerIgnoreProportionSingle:  true,
		ScrollerDefaultProportionSingle: 1.0,
		EdgeScrollerPointerFocus:        true,
		EdgeScrollerFocusAllowSpeed:     0.0,
		OvercircleCenterRatio:           0.5,

		HotareaCorner:              "2",
		HotareaDisableOnFullscreen: true,

		SingleScratchpad:       true,
		ScratchpadCrossMonitor: false,
		SpecialDim:             0.5,
		SpecialGapsIn:          10,
		SpecialGapsOut:         20,

		FadeinBeginOpacity:      0.5,
		FadeoutBeginOpacity:     0.5,
		ZoomInitialRatio:        0.4,
		ZoomEndRatio:            0.8,
		TagAnimationDirection:   "1",
		LayerAnimationTypeOpen:  "default",
		LayerAnimationTypeClose: "default",

		TouchEnable:               true,
		TouchMouseEmulation:       false,
		SwipeMinThreshold:         1,
		GestureLive:               true,
		GestureSwipeDistance:      300,
		GestureSwipeCancelRatio:   0.5,
		GestureSwipeMinSpeedForce: 10,
		MouseScrollMethod:         "1",
		MouseScrollButton:         274,
		MouseSendEventsMode:       "0",
		TrackpadScrollMethod:      "1",
		TrackpadScrollButton:      274,
		TrackpadSendEventsMode:    "0",
		ButtonMap:                 "0",

		RootColor:       "#323232ff",
		DropColor:       "#d5899d80",
		SplitColor:      "#eb441eff",
		MaximizeColor:   "#89aa61ff",
		ScratchpadColor: "#516c93ff",
		GlobalColor:     "#b153a7ff",
		OverlayColor:    "#14a57cff",
	}
	s.Mango.Anim.Open = defaultAnim()
	s.Mango.Anim.Close = AnimSpec{Mode: "default", DurationMs: 800, Curve: "0.08,0.92,0,1", Type: "slide"}
	s.Mango.Anim.Move = AnimSpec{Mode: "default", DurationMs: 500, Curve: "0.46,1.0,0.29,1", Type: "slide"}
	s.Mango.Anim.Tag = AnimSpec{Mode: "default", DurationMs: 350, Curve: "0.46,1.0,0.29,1", Type: "slide"}
	return s
}

// readNeutralStore reads desktop.json, false when it is absent or unparseable.
func readNeutralStore(path string) (neutralStore, bool) {
	var ns neutralStore
	b, err := os.ReadFile(path)
	if err != nil {
		return ns, false
	}
	if json.Unmarshal(b, &ns) != nil {
		return ns, false
	}
	return ns, true
}

// loadStore fills the mango defaults, then overlays the store's desktop.* and
// wm.mango.* leaves. An absent leaf keeps its default, so the generated config
// is always the full effective look, not a partial one.
func loadStore(path string) mangoStore {
	s := defaultStore()
	ns, ok := readNeutralStore(path)
	if !ok {
		return s
	}
	if b, err := json.Marshal(ns.Desktop); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	s.Cursor.Theme = wm.ResolveCursorTheme(s.Cursor.Theme)
	if raw, ok := ns.WM["mango"]; ok {
		_ = json.Unmarshal(raw, &s.Mango)
	}
	if len(s.Mango.ScrollerProportionPreset) < 2 {
		s.Mango.ScrollerProportionPreset = defaultStore().Mango.ScrollerProportionPreset
	}
	return s
}

// splitStore renders the store as the namespaced desktop.json tree.
func splitStore(s mangoStore) (map[string]any, error) {
	db, err := json.Marshal(s)
	if err != nil {
		return nil, err
	}
	var desktop map[string]json.RawMessage
	if err := json.Unmarshal(db, &desktop); err != nil {
		return nil, err
	}
	mb, err := json.Marshal(s.Mango)
	if err != nil {
		return nil, err
	}
	var mango map[string]json.RawMessage
	if err := json.Unmarshal(mb, &mango); err != nil {
		return nil, err
	}
	return map[string]any{
		"desktop": desktop,
		"wm":      map[string]any{"mango": mango},
	}, nil
}

// --- paths ----------------------------------------------------------------

func configHome() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return d
	}
	return filepath.Join(os.Getenv("HOME"), ".config")
}

// storePath is the neutral settings store this provider reads for the runtime
// behaviours that never reach the config file.
func storePath() string {
	return filepath.Join(configHome(), "ryoku", "desktop.json")
}

// borderPalettePath is where the border act records the live palette's active
// and inactive colours. writeFrame reads it so the border tracks the wallpaper;
// the last session's file is still there at login.
func borderPalettePath() string {
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		dir = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(dir, "ryoku", "mango-border-palette.json")
}

func borderPaletteColors() (active, inactive string, ok bool) {
	b, err := os.ReadFile(borderPalettePath())
	if err != nil {
		return "", "", false
	}
	var p struct {
		Active   string `json:"active"`
		Inactive string `json:"inactive"`
	}
	if json.Unmarshal(b, &p) != nil {
		return "", "", false
	}
	if p.Active == "" && p.Inactive == "" {
		return "", "", false
	}
	return p.Active, p.Inactive, true
}

func recordBorderPalette(active, inactive string) error {
	if err := os.MkdirAll(filepath.Dir(borderPalettePath()), 0o755); err != nil {
		return err
	}
	b, _ := json.Marshal(map[string]string{"active": active, "inactive": inactive})
	return os.WriteFile(borderPalettePath(), b, 0o644)
}

// userEditsMangoDir is the mango slice of the user overlay tree. The generated
// config lives here so it survives an update as a user edit; writeOverlayConf
// reflects the same bytes into the live mango dir so a reload picks them up.
func userEditsMangoDir() string {
	return filepath.Join(configHome(), "ryoku", "user_edits", "mango")
}

// --- disk ------------------------------------------------------------------

func atomicWrite(path string, b []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	if _, err := f.Write(b); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Chmod(mode); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func writeOverlayConf(name string, body []byte) error {
	if err := atomicWrite(filepath.Join(userEditsMangoDir(), name), body, 0o644); err != nil {
		return err
	}
	return atomicWrite(filepath.Join(mangoConfigDir(), name), body, 0o644)
}

func numStr(f float64) string {
	return strconv.FormatFloat(f, 'g', -1, 64)
}
