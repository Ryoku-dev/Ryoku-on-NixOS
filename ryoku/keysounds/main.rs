// ryoku-keysounds: a keyboard sound on every key press, for a compositor with no
// plugin system to hang one on. Reading the same evdev node libinput reads is
// the one way to hear every key in every window without grabbing input, and
// playback goes through libcanberra, the same event-sound library the companion
// plugin uses, so the sound server caches and mixes and the compositor does no
// work per keystroke.
//
// Nothing here names a compositor: the session starts it, the window-manager
// provider writes its settings, and a changed file is picked up within a second.

use std::collections::{BTreeMap, HashSet};
use std::ffi::{CStr, CString};
use std::fs;
use std::io::{ErrorKind, Read};
use std::os::raw::{c_char, c_int};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const DEFAULT_PROFILE: &str = "cherry-mx-brown";
const PROFILES_DIR: &str = "/usr/share/ryoku/keysounds";

const EV_KEY: u16 = 1;
const KEY_RELEASE: i32 = 0;
const KEY_PRESS: i32 = 1;
const KEY_ENTER: u16 = 28;
const KEY_BACKSPACE: u16 = 14;
const KEY_SPACE: u16 = 57;
const KEY_KPENTER: u16 = 96;

// One role per bucket a profile may record; a key with no samples of its own
// falls back to the generic press (`down`) or release (`up`).
const ROLES: [&str; 8] = [
    "down", "up", "space", "space-up", "enter", "enter-up", "backspace", "backspace-up",
];

const CA_PROP_MEDIA_FILENAME: &CStr = c"media.filename";
const CA_PROP_CANBERRA_VOLUME: &CStr = c"canberra.volume";
const CA_PROP_CANBERRA_CACHE_CONTROL: &CStr = c"canberra.cache_control";
const CA_PROP_APPLICATION_NAME: &CStr = c"application.name";
const CA_PROP_APPLICATION_ID: &CStr = c"application.id";
const CA_PROP_APPLICATION_ICON_NAME: &CStr = c"application.icon_name";
const CA_CACHE_PERMANENT: &CStr = c"permanent";

#[link(name = "canberra")]
extern "C" {
    fn ca_context_create(ctx: *mut *mut std::ffi::c_void) -> c_int;
    fn ca_context_change_props(ctx: *mut std::ffi::c_void, ...) -> c_int;
    fn ca_context_cache(ctx: *mut std::ffi::c_void, ...) -> c_int;
    fn ca_context_play(ctx: *mut std::ffi::c_void, id: u32, ...) -> c_int;
}

/// The settings the provider writes and the daemon reads: `key=value` lines,
/// `#` comments ignored. The defaults match the companion plugin, so a box
/// whose provider has never run still sounds.
struct Settings {
    enabled: bool,
    profile: String,
    volume: f32,
    release: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { enabled: true, profile: DEFAULT_PROFILE.to_string(), volume: 0.6, release: true }
    }
}

/// One resolved profile: sample files per role, keyed by filename prefix
/// (`down-1.wav`). Every role is present, empty when the profile records none.
struct Bank {
    name: String,
    roles: BTreeMap<String, Vec<String>>,
}

impl Bank {
    fn empty(name: &str) -> Self {
        let mut roles = BTreeMap::new();
        for r in ROLES {
            roles.insert(r.to_string(), Vec::new());
        }
        Bank { name: name.to_string(), roles }
    }
}

struct State {
    ctx: *mut std::ffi::c_void,
    settings: Settings,
    bank: Bank,
}

// Safe: the context is only ever touched while the owning Mutex is held.
unsafe impl Send for State {}

fn env_dir(name: &str, fallback: PathBuf) -> PathBuf {
    std::env::var_os(name).map(PathBuf::from).filter(|p| !p.as_os_str().is_empty()).unwrap_or(fallback)
}

fn home() -> PathBuf {
    env_dir("HOME", PathBuf::from("/"))
}

/// Where the window-manager provider writes the live settings. A neutral path,
/// like the profile layout: only the writer names the compositor.
fn conf_path() -> PathBuf {
    env_dir("XDG_STATE_HOME", home().join(".local/state")).join("ryoku").join("keysounds.conf")
}

fn profile_roots() -> Vec<PathBuf> {
    vec![
        env_dir("XDG_DATA_HOME", home().join(".local/share")).join("ryoku").join("keysounds"),
        PathBuf::from(PROFILES_DIR),
    ]
}

fn truthy(v: &str) -> bool {
    matches!(v, "1" | "true" | "yes" | "on")
}

fn read_conf(path: &Path) -> Settings {
    let mut s = Settings::default();
    let Ok(text) = fs::read_to_string(path) else { return s };
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        let v = v.trim();
        match k.trim() {
            "enabled" => s.enabled = truthy(v),
            "release" => s.release = truthy(v),
            "profile" if !v.is_empty() => s.profile = v.to_string(),
            "volume" => {
                if let Ok(x) = v.parse::<f32>() {
                    s.volume = x.clamp(0.0, 1.0);
                }
            }
            _ => {}
        }
    }
    s
}

fn is_sample(p: &Path) -> bool {
    matches!(p.extension().and_then(|e| e.to_str()), Some("wav") | Some("oga") | Some("ogg"))
}

/// Files named `<role>-<n>.<ext>`, matched by prefix exactly as the plugin's
/// sample lookup matches them, so a profile sounds the same either way.
fn collect(dir: &Path, role: &str) -> Vec<String> {
    let prefix = format!("{role}-");
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(dir) {
        for entry in rd.flatten() {
            let p = entry.path();
            if !p.is_file() || !is_sample(&p) {
                continue;
            }
            if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.starts_with(&prefix) {
                    out.push(p.to_string_lossy().into_owned());
                }
            }
        }
    }
    out.sort();
    out
}

fn find_profile(name: &str) -> Option<PathBuf> {
    profile_roots().into_iter().map(|root| root.join(name)).find(|dir| dir.is_dir())
}

/// Returns the wanted profile, falling back to the shipped default when it is
/// gone (renamed, a user folder removed) rather than going silent.
fn load_bank(want: &str) -> Bank {
    let dir = find_profile(want).or_else(|| find_profile(DEFAULT_PROFILE));
    let Some(dir) = dir else { return Bank::empty(want) };
    let mut bank = Bank::empty(want);
    for role in ROLES {
        bank.roles.insert(role.to_string(), collect(&dir, role));
    }
    bank
}

/// Upload every sample to the sound server once, so the first press is as quick
/// as the hundredth.
fn cache_all(ctx: *mut std::ffi::c_void, bank: &Bank) {
    if ctx.is_null() {
        return;
    }
    for files in bank.roles.values() {
        for f in files {
            if let Ok(f) = CString::new(f.as_str()) {
                unsafe {
                    ca_context_cache(
                        ctx,
                        CA_PROP_MEDIA_FILENAME.as_ptr(),
                        f.as_ptr(),
                        CA_PROP_CANBERRA_CACHE_CONTROL.as_ptr(),
                        CA_CACHE_PERMANENT.as_ptr(),
                        std::ptr::null::<c_char>(),
                    );
                }
            }
        }
    }
}

// xorshift64*, seeded lazily from the clock: a random variant per press so
// typing never sounds like a loop.
static SEED: AtomicU64 = AtomicU64::new(0);

fn next_rand() -> u64 {
    let mut x = SEED.load(Ordering::Relaxed);
    if x == 0 {
        x = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1) | 1;
    }
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    SEED.store(x, Ordering::Relaxed);
    x
}

fn bucket<'a>(bank: &'a Bank, code: u16, pressed: bool) -> &'a [String] {
    let role = match code {
        KEY_SPACE => Some("space"),
        KEY_ENTER | KEY_KPENTER => Some("enter"),
        KEY_BACKSPACE => Some("backspace"),
        _ => None,
    };
    let generic = bank.roles.get(if pressed { "down" } else { "up" });
    if let Some(role) = role {
        let own = if pressed { role.to_string() } else { format!("{role}-up") };
        if let Some(files) = bank.roles.get(&own) {
            if !files.is_empty() {
                return files;
            }
        }
    }
    generic.map(Vec::as_slice).unwrap_or(&[])
}

fn play(state: &State, code: u16, pressed: bool) {
    if state.ctx.is_null() || state.settings.volume <= 0.0 {
        return;
    }
    let files = bucket(&state.bank, code, pressed);
    if files.is_empty() {
        return;
    }
    let file = &files[(next_rand() % files.len() as u64) as usize];
    let (Ok(file), Ok(db)) = (
        CString::new(file.as_str()),
        // canberra takes the volume as a dB offset; 1.0 is the sample as recorded
        CString::new(format!("{:.2}", 20.0 * state.settings.volume.log10())),
    ) else {
        return;
    };
    unsafe {
        ca_context_play(
            state.ctx,
            0,
            CA_PROP_MEDIA_FILENAME.as_ptr(),
            file.as_ptr(),
            CA_PROP_CANBERRA_VOLUME.as_ptr(),
            db.as_ptr(),
            CA_PROP_CANBERRA_CACHE_CONTROL.as_ptr(),
            CA_CACHE_PERMANENT.as_ptr(),
            std::ptr::null::<c_char>(),
        );
    }
}

/// Every keyboard event node, deduped by what it resolves to: `by-path` lists
/// a USB device under both its v1 and v2 name, and both point at one node.
fn keyboard_devices() -> Vec<(PathBuf, PathBuf)> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir("/dev/input/by-path") {
        for entry in rd.flatten() {
            if !entry.file_name().to_string_lossy().contains("event-kbd") {
                continue;
            }
            if let Ok(real) = fs::canonicalize(entry.path()) {
                if seen.insert(real.clone()) {
                    out.push((entry.path(), real));
                }
            }
        }
    }
    out
}

/// One blocking reader per device. It returns when the device goes away, and
/// the watcher adds it again if it comes back.
fn read_device(link: PathBuf, real: PathBuf, state: Arc<Mutex<State>>, live: Arc<Mutex<HashSet<PathBuf>>>) {
    if let Ok(mut f) = fs::File::open(&link) {
        let mut buf = [0u8; 24]; // struct input_event: timeval (16) + type + code + value
        loop {
            match f.read(&mut buf) {
                Ok(24) => {
                    let type_ = u16::from_le_bytes([buf[16], buf[17]]);
                    let code = u16::from_le_bytes([buf[18], buf[19]]);
                    let value = i32::from_le_bytes([buf[20], buf[21], buf[22], buf[23]]);
                    // value 2 is a repeat: one sound per press, like a real key
                    if type_ != EV_KEY || (value != KEY_PRESS && value != KEY_RELEASE) {
                        continue;
                    }
                    let state = state.lock().unwrap();
                    if state.settings.enabled {
                        play(&state, code, value == KEY_PRESS);
                    }
                }
                Ok(_) => {}
                Err(e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    }
    live.lock().unwrap().remove(&real);
}

fn watch_devices(state: Arc<Mutex<State>>, live: Arc<Mutex<HashSet<PathBuf>>>) {
    loop {
        for (link, real) in keyboard_devices() {
            if !live.lock().unwrap().insert(real.clone()) {
                continue;
            }
            let (s, l, r) = (state.clone(), live.clone(), real.clone());
            thread::spawn(move || read_device(link, r, s, l));
        }
        thread::sleep(Duration::from_secs(2));
    }
}

/// Repoint the daemon at the settings without a relogin: the provider rewrites
/// the file on Save, and this turns a changed mtime into a fresh bank.
fn watch_settings(state: Arc<Mutex<State>>) {
    let path = conf_path();
    let mtime = || fs::metadata(&path).and_then(|m| m.modified()).ok();
    let mut last = mtime();
    loop {
        thread::sleep(Duration::from_secs(1));
        let now = mtime();
        if now == last {
            continue;
        }
        last = now;
        let settings = read_conf(&path);
        let bank = load_bank(&settings.profile);
        let mut s = state.lock().unwrap();
        if bank.name != s.bank.name {
            cache_all(s.ctx, &bank);
        }
        s.settings = settings;
        s.bank = bank;
    }
}

fn open_context() -> *mut std::ffi::c_void {
    let mut ctx: *mut std::ffi::c_void = std::ptr::null_mut();
    unsafe {
        if ca_context_create(&mut ctx) == 0 {
            ca_context_change_props(
                ctx,
                CA_PROP_APPLICATION_NAME.as_ptr(),
                c"Ryoku Key Sounds".as_ptr(),
                CA_PROP_APPLICATION_ID.as_ptr(),
                c"dev.ryoku.keysounds".as_ptr(),
                CA_PROP_APPLICATION_ICON_NAME.as_ptr(),
                c"input-keyboard".as_ptr(),
                std::ptr::null::<c_char>(),
            );
        } else {
            ctx = std::ptr::null_mut();
        }
    }
    ctx
}

fn main() {
    let ctx = open_context();
    let settings = read_conf(&conf_path());
    let bank = load_bank(&settings.profile);
    cache_all(ctx, &bank);
    let state = Arc::new(Mutex::new(State { ctx, settings, bank }));
    let live = Arc::new(Mutex::new(HashSet::new()));

    {
        let state = state.clone();
        thread::spawn(move || watch_settings(state));
    }
    watch_devices(state, live);
}
