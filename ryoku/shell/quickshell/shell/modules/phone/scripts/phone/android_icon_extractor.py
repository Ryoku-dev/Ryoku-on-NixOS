#!/usr/bin/env python3
"""Launcher icon extractor for the Quickshell phone panel.

Android exposes no API to hand a launcher icon to a desktop, so icons are
resolved out of the installed APKs over adb:

  1. `pm path <pkg>` lists the base APK plus its config splits.
  2. `AndroidManifest.xml` and `resources.arsc` are streamed out of the APK
     with the device's own `unzip -p`, so a 200 MB app costs a few hundred KB
     rather than a full pull.
  3. The manifest's `application@icon` resource id is resolved against the
     resource table to a concrete file inside one of the APKs.
  4. Bitmaps are converted to PNG; adaptive icons are flattened by compositing
     their foreground over their background and cropping to the safe zone;
     vector drawables are translated to SVG, which Qt renders natively.
  5. Whatever comes out has to actually paint something. A drawable whose
     colours or layers did not resolve still yields a perfectly valid, entirely
     invisible icon, so each candidate is checked and rejected in favour of the
     next one rather than cached as a blank.

Results are cached under XDG_CACHE_HOME so the adb round trips happen once per
app. Speaks newline-delimited JSON on stdin/stdout:

  {"cmd": "cached", "deviceId": "..."}                    -> {"event": "cached", "icons": {...}}
  {"cmd": "fetch", "package": "...", "deviceId": "...",   -> {"event": "icon", "package": "...", "path": "..."}
   "target_args": ["-s", "..."]}
  {"cmd": "clear", "deviceId": "..."}                     -> {"event": "cleared"}
"""

import base64
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
from io import BytesIO
from pathlib import Path
from struct import unpack_from


try:
    from PIL import Image

    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

ANDROID = "{http://schemas.android.com/apk/res/android}"
AAPT = "{http://schemas.android.com/aapt}"

CACHE_ROOT = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "ryoku" / "phone" / "app-icons"
MISS_TTL = 7 * 24 * 3600  # Retry apps we failed to resolve after a week
OUTPUT_SIZE = 192  # Icons are shown at ~36 px; 192 stays crisp on any scale factor
WORKER_COUNT = 3
ADB_TIMEOUT = 25
# Resource tables are the one entry that can be genuinely huge — Samsung Health
# ships 175 MB of it — and streaming that off the phone takes its time.
TABLE_TIMEOUT = 120

DENSITY_ANY = 0xFFFE  # anydpi: an XML drawable rather than a bitmap
DENSITY_NONE = 0xFFFF  # nodpi

# resources.arsc chunk and entry tags, from AOSP's ResourceTypes.h
RES_STRING_POOL = 0x0001
RES_TABLE = 0x0002
RES_TABLE_PACKAGE = 0x0200
RES_TABLE_TYPE = 0x0201
RES_XML = 0x0003
RES_XML_START_NAMESPACE = 0x0100
RES_XML_END_NAMESPACE = 0x0101
RES_XML_START_ELEMENT = 0x0102
RES_XML_END_ELEMENT = 0x0103
NO_INDEX = 0xFFFFFFFF
VALUE_FLOAT = 0x04
VALUE_DIMENSION = 0x05
VALUE_FRACTION = 0x06
VALUE_INT_DEC = 0x10
VALUE_INT_HEX = 0x11
VALUE_INT_BOOLEAN = 0x12
TYPE_SPARSE = 0x01  # entry offsets are an (index, offset) map, not an array
TYPE_OFFSET16 = 0x02  # entry offsets are 16-bit
ENTRY_COMPLEX = 0x0001  # a bag (style, array); never a drawable
ENTRY_COMPACT = 0x0008  # value packed into the entry header
VALUE_REFERENCE = 0x01
VALUE_ATTRIBUTE = 0x02
VALUE_STRING = 0x03
VALUE_COLORS = (0x1C, 0x1D, 0x1E, 0x1F)
NO_ENTRY16 = 0xFFFF
NO_ENTRY32 = 0xFFFFFFFF

# Adaptive icons draw 108x108 layers of which only the centre 72x72 is
# guaranteed visible; everything outside is parallax/mask bleed.
ADAPTIVE_VIEWPORT = 108.0
ADAPTIVE_SAFE = 72.0
ADAPTIVE_INSET = (ADAPTIVE_VIEWPORT - ADAPTIVE_SAFE) / 2.0

out_lock = threading.Lock()


def emit(payload: dict) -> None:
    with out_lock:
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()


def warn(message: str) -> None:
    sys.stderr.write(f"[android_icon_extractor] {message}\n")
    sys.stderr.flush()


# ─── adb plumbing ────────────────────────────────────────────────────────────

target_lock = threading.Lock()
server_started = False
resolved_target = None


def ensure_server() -> None:
    """Start the adb server once, serialized. Several workers racing to spawn
    their own server is a reliable way to wedge adb for everyone else."""
    global server_started
    with target_lock:
        if server_started:
            return
        server_started = True
    try:
        subprocess.run(["adb", "start-server"], capture_output=True, timeout=ADB_TIMEOUT)
    except (subprocess.SubprocessError, OSError) as exc:
        warn(f"adb start-server failed: {exc}")


def resolve_target(target_args) -> list:
    """The live device list beats the serial the shell passed us: wireless
    debugging picks a new port on every toggle, so that serial goes stale."""
    global resolved_target
    ensure_server()
    with target_lock:
        if resolved_target is not None:
            return resolved_target

    usb, wireless = [], []
    try:
        res = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=ADB_TIMEOUT)
        for line in res.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                (wireless if ":" in parts[0] else usb).append(parts[0])
    except (subprocess.SubprocessError, OSError) as exc:
        warn(f"adb devices failed: {exc}")

    connected = usb or wireless
    target = ["-s", connected[0]] if connected else list(target_args or [])
    with target_lock:
        resolved_target = target
    return target


def forget_target() -> None:
    global resolved_target
    with target_lock:
        resolved_target = None


def device_online(target_args) -> bool:
    try:
        res = subprocess.run(["adb", *resolve_target(target_args), "get-state"],
                             capture_output=True, text=True, timeout=ADB_TIMEOUT)
    except (subprocess.SubprocessError, OSError) as exc:
        warn(f"adb get-state failed: {exc}")
        forget_target()
        return False

    if res.stdout.strip() != "device":
        forget_target()
        return False
    return True


def adb_text(target_args, *args) -> str:
    try:
        res = subprocess.run(["adb", *resolve_target(target_args), *args], capture_output=True,
                             timeout=ADB_TIMEOUT)
        return res.stdout.decode("utf-8", "replace")
    except (subprocess.SubprocessError, OSError) as exc:
        warn(f"adb {' '.join(args)} failed: {exc}")
        return ""


def adb_binary(target_args, command: str, timeout: int = ADB_TIMEOUT) -> bytes:
    try:
        res = subprocess.run(["adb", *resolve_target(target_args), "exec-out", command],
                             capture_output=True, timeout=timeout)
        return res.stdout
    except (subprocess.SubprocessError, OSError) as exc:
        warn(f"adb exec-out failed: {exc}")
        return b""


def apk_paths(target_args, package: str) -> list:
    lines = adb_text(target_args, "shell", "pm", "path", package).splitlines()
    return [line.strip()[len("package:"):] for line in lines if line.strip().startswith("package:")]


def read_entry(target_args, apk: str, entry: str, timeout: int = ADB_TIMEOUT) -> bytes:
    return adb_binary(target_args, f"unzip -p {shlex.quote(apk)} {shlex.quote(entry)}", timeout)


# ─── Resource tables ─────────────────────────────────────────────────────────

class StringPool:
    """A resource table's string pool, read on demand rather than up front."""

    def __init__(self, data: bytes, start: int):
        header_size = unpack_from("<H", data, start + 2)[0]
        count, _styles, flags, strings_start = unpack_from("<IIII", data, start + 8)

        self.data = data
        self.utf8 = bool(flags & 0x0100)
        self.base = start + strings_start
        self.offsets = unpack_from(f"<{count}I", data, start + header_size) if count else ()

    def get(self, index: int):
        if not 0 <= index < len(self.offsets):
            return None
        position = self.base + self.offsets[index]
        try:
            if self.utf8:
                _, position = self._length8(position)  # character count, then byte count
                length, position = self._length8(position)
                return self.data[position:position + length].decode("utf-8", "replace")
            length, position = self._length16(position)
            return self.data[position:position + length * 2].decode("utf-16-le", "replace")
        except Exception:
            return None

    def _length8(self, position: int):
        value = self.data[position]
        position += 1
        if value & 0x80:  # A high bit means the length spills into a second byte
            value = ((value & 0x7F) << 8) | self.data[position]
            position += 1
        return value, position

    def _length16(self, position: int):
        value = unpack_from("<H", self.data, position)[0]
        position += 2
        if value & 0x8000:
            value = ((value & 0x7FFF) << 16) | unpack_from("<H", self.data, position)[0]
            position += 2
        return value, position

class BinaryXML:
    """Small Android binary XML reader for manifests and drawable resources."""

    def __init__(self, data: bytes):
        if len(data) < 8 or unpack_from("<H", data, 0)[0] != RES_XML:
            raise ValueError("not Android binary XML")
        self.data = data
        self.strings = None

    def parse(self):
        header_size, total = unpack_from("<HI", self.data, 2)
        stack = []
        root = None
        for kind, position, child_header, size in self._chunks(header_size, min(total, len(self.data))):
            if kind == RES_STRING_POOL:
                self.strings = StringPool(self.data, position)
                continue
            if kind == RES_XML_START_ELEMENT:
                if self.strings is None:
                    raise ValueError("element before string pool")
                extension = position + 16
                namespace, name = unpack_from("<II", self.data, extension)
                attribute_start, attribute_size, attribute_count = unpack_from(
                    "<HHH", self.data, extension + 8
                )
                element = ET.Element(self._name(namespace, name))
                attributes = extension + attribute_start
                for index in range(attribute_count):
                    offset = attributes + index * attribute_size
                    attr_namespace, attr_name, raw_value = unpack_from("<III", self.data, offset)
                    value_type = self.data[offset + 15]
                    value_data = unpack_from("<I", self.data, offset + 16)[0]
                    if raw_value != NO_INDEX:
                        value = self.strings.get(raw_value)
                    else:
                        value = self._typed_value(value_type, value_data)
                    if value is not None:
                        element.set(self._name(attr_namespace, attr_name), value)
                if stack:
                    stack[-1].append(element)
                elif root is None:
                    root = element
                stack.append(element)
            elif kind == RES_XML_END_ELEMENT and stack:
                stack.pop()
        if root is None:
            raise ValueError("binary XML has no root element")
        return root

    def _chunks(self, start: int, end: int):
        while start + 8 <= end:
            kind, header_size, size = unpack_from("<HHI", self.data, start)
            if size < header_size or header_size < 8 or start + size > end:
                raise ValueError("invalid binary XML chunk")
            yield kind, start, header_size, size
            start += size

    def _name(self, namespace: int, name: int) -> str:
        local = self.strings.get(name)
        if not local:
            raise ValueError("invalid binary XML name")
        if namespace == NO_INDEX:
            return local
        uri = self.strings.get(namespace)
        return f"{{{uri}}}{local}" if uri else local

    def _typed_value(self, kind: int, data: int):
        if kind == VALUE_STRING:
            return self.strings.get(data)
        if kind == VALUE_REFERENCE:
            return f"@{data:08X}"
        if kind == VALUE_ATTRIBUTE:
            return f"?{data:08X}"
        if kind == VALUE_FLOAT:
            return f"{unpack_from('<f', data.to_bytes(4, 'little'))[0]:g}"
        if kind in (VALUE_DIMENSION, VALUE_FRACTION):
            signed = data & 0xFFFFFF00
            if signed & 0x80000000:
                signed -= 1 << 32
            radix = (data >> 4) & 0x03
            value = signed * (1 / 256, 1 / 32768, 1 / 8388608, 1 / 2147483648)[radix]
            return f"{value:g}"
        if kind == VALUE_INT_BOOLEAN:
            return "true" if data else "false"
        if kind == VALUE_INT_DEC:
            return str(data if data < 0x80000000 else data - (1 << 32))
        if kind == VALUE_INT_HEX:
            return f"0x{data:X}"
        if kind in VALUE_COLORS:
            return f"#{data:08X}"
        return None


class ResourceTable:
    """A `resources.arsc` reader, cut down to resolving one id at a time.

    Resource tables are walked chunk by chunk from their declared offsets.
    Unknown chunks remain skippable, including sparse entries and 16-bit entry
    offsets emitted by modern aapt2.
    """

    def __init__(self, data: bytes):
        self.data = data
        self.values = None
        self.types = {}

        if len(data) < 12 or unpack_from("<H", data, 0)[0] != RES_TABLE:
            raise ValueError("not a resource table")
        header_size, total = unpack_from("<HI", data, 2)
        self._scan(header_size, min(total, len(data)))
        if self.values is None:
            raise ValueError("no value string pool")

    def entries(self, res_id: int) -> list:
        """Every (density, value) the table holds for a resource id."""
        index = res_id & 0xFFFF
        found = []
        for position, header_size in self.types.get(((res_id >> 24) & 0xFF, (res_id >> 16) & 0xFF), ()):
            try:
                value = self._entry(position, header_size, index)
            except Exception:
                continue  # One malformed type chunk must not sink the others
            if value is not None:
                found.append((self._density(position), value))
        return found

    def _chunks(self, start: int, end: int):
        while start + 8 <= end:
            kind, header_size, size = unpack_from("<HHI", self.data, start)
            if size < 8 or start + size > end:
                return
            yield kind, start, header_size, size
            start += size

    def _scan(self, start: int, end: int) -> None:
        for kind, position, header_size, size in self._chunks(start, end):
            if kind == RES_STRING_POOL and self.values is None:
                self.values = StringPool(self.data, position)
            elif kind == RES_TABLE_PACKAGE:
                self._scan_package(position, header_size, size)

    def _scan_package(self, start: int, header_size: int, size: int) -> None:
        package_id = unpack_from("<I", self.data, start + 8)[0]
        for kind, position, child_header, _ in self._chunks(start + header_size, start + size):
            if kind != RES_TABLE_TYPE:
                continue
            # One chunk per configuration, so a resource appears once per density
            self.types.setdefault((package_id, self.data[position + 8]), []).append((position, child_header))

    def _density(self, position: int) -> int:
        config = position + 20
        return unpack_from("<H", self.data, config + 14)[0] if unpack_from("<I", self.data, config)[0] >= 16 else 0

    def _offset(self, position: int, header_size: int, index: int):
        count = unpack_from("<I", self.data, position + 12)[0]
        flags = self.data[position + 9]
        table = position + header_size

        if flags & TYPE_SPARSE:
            for slot in range(count):
                key, packed = unpack_from("<HH", self.data, table + slot * 4)
                if key == index:
                    return packed * 4
            return None
        if index >= count:
            return None
        if flags & TYPE_OFFSET16:
            packed = unpack_from("<H", self.data, table + index * 2)[0]
            return None if packed == NO_ENTRY16 else packed * 4
        packed = unpack_from("<I", self.data, table + index * 4)[0]
        return None if packed == NO_ENTRY32 else packed

    def _entry(self, position: int, header_size: int, index: int):
        offset = self._offset(position, header_size, index)
        if offset is None:
            return None
        entries_start = unpack_from("<I", self.data, position + 16)[0]
        return self._value(position + entries_start + offset)

    def _value(self, position: int):
        first, flags = unpack_from("<HH", self.data, position)
        if flags & ENTRY_COMPACT:
            return self._literal((flags >> 8) & 0xFF, unpack_from("<I", self.data, position + 4)[0])
        if flags & ENTRY_COMPLEX:
            return None
        # Otherwise `first` is the entry header size, and the value follows it
        return self._literal(self.data[position + first + 3], unpack_from("<I", self.data, position + first + 4)[0])

    def _literal(self, kind: int, data: int):
        if kind == VALUE_STRING:
            return self.values.get(data)
        if kind in (VALUE_REFERENCE, VALUE_ATTRIBUTE):
            return f"@{data:08X}" if data else None
        if kind in VALUE_COLORS:
            return f"#{data:08X}"
        return None


class ApkTable:
    """One APK's manifest and resource table, fetched without pulling the APK."""

    def __init__(self, target_args, path: str):
        self.target_args = target_args
        self.path = path
        self.manifest = None
        self.table = None

        manifest = read_entry(target_args, path, "AndroidManifest.xml")
        arsc = read_entry(target_args, path, "resources.arsc", timeout=TABLE_TIMEOUT)
        if not manifest or not arsc:
            return

        self.manifest = parse_axml(manifest)
        try:
            self.table = ResourceTable(arsc)
        except Exception as exc:
            warn(f"cannot parse {os.path.basename(path)}: {exc}")

    @property
    def valid(self) -> bool:
        return self.table is not None

    def icon_ids(self) -> list:
        """The manifest's icon candidates, best first. Apps that ship a round
        icon as well give a second shot at one that resolves."""
        if self.manifest is None:
            return []
        application = self.manifest.find("application")
        if application is None:
            return []

        found = []
        for attribute in ("icon", "roundIcon", "logo"):
            parsed = parse_reference(attr(application, attribute))
            if parsed is not None and parsed not in found:
                found.append(parsed)

        # Apps that declare no application icon usually put one on the activity
        # the launcher starts.
        for activity in application.iter("activity"):
            parsed = parse_reference(attr(activity, "icon"))
            if parsed is not None and parsed not in found:
                found.append(parsed)
        return found

    def resolve(self, res_id: int) -> list:
        """Every (density, value) this table holds for a resource id."""
        return self.table.entries(res_id) if self.valid else []

    def read(self, entry: str) -> bytes:
        return read_entry(self.target_args, self.path, entry)


class PackageResources:
    """The base APK's table, widened to the config splits only when needed."""

    def __init__(self, target_args, package: str):
        self.target_args = target_args
        self.paths = apk_paths(target_args, package)
        self.tables = []
        self._splits_loaded = False

        if self.paths:
            base = ApkTable(target_args, self.paths[0])
            if base.valid:
                self.tables.append(base)

    @property
    def valid(self) -> bool:
        return bool(self.tables)

    @property
    def base(self) -> ApkTable:
        return self.tables[0]

    def _load_splits(self) -> None:
        if self._splits_loaded:
            return
        self._splits_loaded = True
        for path in self.paths[1:]:
            table = ApkTable(self.target_args, path)
            if table.valid:
                self.tables.append(table)

    def candidates(self, res_id: int, depth: int = 0) -> list:
        """All (table, density, value) entries for a resource id."""
        found = [(table, density, value) for table in self.tables for density, value in table.resolve(res_id)]
        if not found:
            # Density-split APKs carry their own slice of the resource table.
            self._load_splits()
            found = [(table, density, value) for table in self.tables for density, value in table.resolve(res_id)]
        if depth > 3:
            return found

        # An entry can be a plain alias for another resource rather than a value
        resolved = []
        for table, density, value in found:
            alias = parse_reference(value)
            if alias is not None and alias != res_id:
                resolved.extend(self.candidates(alias, depth + 1))
            else:
                resolved.append((table, density, value))
        return resolved

    def best_bitmap(self, res_id: int):
        """Highest-density bitmap for a resource id, as (table, entry)."""
        # Obfuscated APKs strip the extension off their resource files, so
        # anything that is not XML is worth handing to the decoder to find out.
        rasters = [c for c in self.candidates(res_id)
                   if "/" in c[2] and not c[2].lower().endswith(".xml")]
        if not rasters:
            return None
        table, _, entry = max(rasters, key=lambda c: density_rank(c[1]))
        return table, entry

    def drawable_xml(self, res_id: int):
        """Parsed XML drawable for a resource id, as (table, element)."""
        for table, _, value in self.candidates(res_id):
            if not value.lower().endswith(".xml"):
                continue
            element = parse_axml(table.read(value))
            if element is not None:
                return table, element
        return None

    def color(self, res_id: int):
        """A resource id resolved to a #AARRGGBB literal, following one hop
        through a colour state list if that is what it points at."""
        for _, _, value in self.candidates(res_id):
            if value.startswith("#"):
                return normalize_color(value)
        found = self.drawable_xml(res_id)
        if found is None:
            return None
        _, element = found
        for item in element.iter():
            literal = attr(item, "color")
            if literal:
                return self.color_value(literal)
        return None

    def color_value(self, raw: str):
        """A colour attribute that may be a literal or a reference."""
        if not raw:
            return None
        if raw.startswith("#"):
            return normalize_color(raw)
        res_id = parse_reference(raw)
        return self.color(res_id) if res_id is not None else None


def density_rank(density: int) -> int:
    if density in (DENSITY_ANY, DENSITY_NONE):
        return 0
    return density or 160  # A default-config bitmap is mdpi by definition


def attr(node, name: str):
    """An `android:`-prefixed attribute, however this APK happens to spell it.

    Optimised APKs drop the namespace declaration from their compiled XML, and
    the attributes then come back bare. Reading only the namespaced form yields
    a drawable whose paths all look empty — a valid SVG that paints nothing.
    """
    return node.get(f"{ANDROID}{name}", node.get(name))


def parse_reference(value):
    """`@7F0801F1` and `@0x7f0801f1` style resource references."""
    if not isinstance(value, str) or not value.startswith("@"):
        return None
    body = value[1:]
    if body.lower().startswith("0x"):
        body = body[2:]
    try:
        return int(body, 16)
    except ValueError:
        return None


def parse_axml(raw: bytes):
    if not raw:
        return None
    try:
        if raw.lstrip().startswith(b"<"):
            return ET.fromstring(raw)
        return BinaryXML(raw).parse()
    except Exception:
        return None


def normalize_color(literal: str):
    """Android #AARRGGBB / #RGB literals to an (svg colour, opacity) pair."""
    body = literal.lstrip("#")
    if len(body) == 3:
        body = "".join(c * 2 for c in body)
    elif len(body) == 4:
        body = "".join(c * 2 for c in body)
    if len(body) == 8:
        alpha = int(body[0:2], 16) / 255.0
        return f"#{body[2:]}", alpha
    if len(body) == 6:
        return f"#{body}", 1.0
    return None


# ─── Vector drawable to SVG ──────────────────────────────────────────────────

class VectorConverter:
    """Translates a compiled <vector> drawable into SVG.

    Path data survives aapt compilation verbatim and uses the same grammar as
    SVG's `d`, so the conversion is mostly a matter of renaming attributes and
    resolving colour references through the resource table.
    """

    def __init__(self, resources: PackageResources):
        self.resources = resources
        self.defs = []
        self.gradient_seq = 0
        # Whether anything was actually given a colour. A drawable whose paints
        # all failed to resolve still produces valid SVG, just an invisible one,
        # and that has to be caught before it is cached as the app's icon.
        self.painted = False

    def convert(self, vector, view_box: str, background=None) -> str:
        width = float(attr(vector, "viewportWidth") or ADAPTIVE_VIEWPORT)
        height = float(attr(vector, "viewportHeight") or ADAPTIVE_VIEWPORT)
        scale = ""
        if view_box == self.adaptive_view_box() and (width, height) != (ADAPTIVE_VIEWPORT, ADAPTIVE_VIEWPORT):
            # Some foregrounds declare a smaller viewport than the 108 grid.
            scale = f' transform="scale({ADAPTIVE_VIEWPORT / width:.6f},{ADAPTIVE_VIEWPORT / height:.6f})"'

        body = "".join(self.emit_node(child) for child in vector)
        alpha = attr(vector, "alpha")
        opacity = f' opacity="{float(alpha):.3f}"' if alpha else ""

        parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}" '
            f'width="{OUTPUT_SIZE}" height="{OUTPUT_SIZE}">'
        ]
        if self.defs:
            parts.append("<defs>" + "".join(self.defs) + "</defs>")
        if background:
            parts.append(background)
        parts.append(f"<g{scale}{opacity}>{body}</g></svg>")
        return "".join(parts)

    @staticmethod
    def adaptive_view_box() -> str:
        return f"{ADAPTIVE_INSET:g} {ADAPTIVE_INSET:g} {ADAPTIVE_SAFE:g} {ADAPTIVE_SAFE:g}"

    def emit_node(self, node) -> str:
        tag = node.tag.rsplit("}", 1)[-1]
        if tag == "path":
            return self.emit_path(node)
        if tag == "group":
            return self.emit_group(node)
        if tag == "clip-path":
            return ""  # Clips only ever shrink the drawing; ignoring them is safe
        return ""

    def emit_group(self, group) -> str:
        transforms = []
        translate_x = float(attr(group, "translateX") or 0)
        translate_y = float(attr(group, "translateY") or 0)
        pivot_x = float(attr(group, "pivotX") or 0)
        pivot_y = float(attr(group, "pivotY") or 0)
        rotation = float(attr(group, "rotation") or 0)
        scale_x = float(attr(group, "scaleX") or 1)
        scale_y = float(attr(group, "scaleY") or 1)

        if translate_x or translate_y:
            transforms.append(f"translate({translate_x:g},{translate_y:g})")
        if rotation:
            transforms.append(f"rotate({rotation:g},{pivot_x:g},{pivot_y:g})")
        if scale_x != 1 or scale_y != 1:
            if pivot_x or pivot_y:
                transforms.append(f"translate({pivot_x:g},{pivot_y:g})")
            transforms.append(f"scale({scale_x:g},{scale_y:g})")
            if pivot_x or pivot_y:
                transforms.append(f"translate({-pivot_x:g},{-pivot_y:g})")

        body = "".join(self.emit_node(child) for child in group)
        attribute = f' transform="{" ".join(transforms)}"' if transforms else ""
        return f"<g{attribute}>{body}</g>"

    def emit_path(self, path) -> str:
        data = attr(path, "pathData")
        if not data:
            return ""

        attributes = [f'd="{escape(data)}"']
        fill = self.paint(path, "fillColor")
        if fill is None:
            attributes.append('fill="none"')
        else:
            paint, opacity = fill
            attributes.append(f'fill="{paint}"')
            alpha = attr(path, "fillAlpha")
            opacity *= float(alpha) if alpha else 1.0
            if opacity < 1.0:
                attributes.append(f'fill-opacity="{opacity:.3f}"')
            self.painted = self.painted or opacity > 0

        if (attr(path, "fillType") or "0") in ("1", "evenOdd"):
            attributes.append('fill-rule="evenodd"')

        stroke = self.paint(path, "strokeColor")
        stroke_width = float(attr(path, "strokeWidth") or 0)
        if stroke is not None and stroke_width > 0:
            paint, opacity = stroke
            attributes.append(f'stroke="{paint}" stroke-width="{stroke_width:g}"')
            alpha = attr(path, "strokeAlpha")
            opacity *= float(alpha) if alpha else 1.0
            if opacity < 1.0:
                attributes.append(f'stroke-opacity="{opacity:.3f}"')
            self.painted = self.painted or opacity > 0
            cap = attr(path, "strokeLineCap")
            join = attr(path, "strokeLineJoin")
            if cap in ("round", "square"):
                attributes.append(f'stroke-linecap="{cap}"')
            if join in ("round", "bevel"):
                attributes.append(f'stroke-linejoin="{join}"')

        return f"<path {' '.join(attributes)}/>"

    def paint(self, path, attribute: str):
        """A fill/stroke as (svg paint, opacity), following gradients."""
        gradient = self.find_gradient(path, attribute)
        if gradient is not None:
            reference = self.emit_gradient(gradient)
            if reference:
                return reference, 1.0

        colour = self.resources.color_value(attr(path, attribute))
        return colour

    @staticmethod
    def find_gradient(path, attribute: str):
        """aapt inlines `<aapt:attr name="android:fillColor"><gradient/></aapt:attr>`."""
        for child in path:
            if child.tag != f"{AAPT}attr" or child.get("name") != f"android:{attribute}":
                continue
            for grandchild in child:
                if grandchild.tag.rsplit("}", 1)[-1] == "gradient":
                    return grandchild
        return None

    def emit_gradient(self, gradient):
        stops = []
        for item in gradient:
            if item.tag.rsplit("}", 1)[-1] != "item":
                continue
            colour = self.resources.color_value(attr(item, "color"))
            if colour is None:
                continue
            paint, opacity = colour
            offset = float(attr(item, "offset") or 0)
            stops.append(f'<stop offset="{offset:g}" stop-color="{paint}" stop-opacity="{opacity:.3f}"/>')

        if not stops:
            for endpoint in ("startColor", "endColor"):
                colour = self.resources.color_value(attr(gradient, endpoint))
                if colour is None:
                    continue
                paint, opacity = colour
                offset = 0 if endpoint == "startColor" else 1
                stops.append(f'<stop offset="{offset}" stop-color="{paint}" stop-opacity="{opacity:.3f}"/>')
        if not stops:
            return None

        self.gradient_seq += 1
        name = f"g{self.gradient_seq}"
        kind = attr(gradient, "type") or "linear"
        if kind in ("1", "radial"):
            centre_x = attr(gradient, "centerX") or 0
            centre_y = attr(gradient, "centerY") or 0
            radius = attr(gradient, "gradientRadius") or 1
            self.defs.append(
                f'<radialGradient id="{name}" gradientUnits="userSpaceOnUse" '
                f'cx="{centre_x}" cy="{centre_y}" r="{radius}">{"".join(stops)}</radialGradient>'
            )
        elif kind in ("2", "sweep"):
            # SVG has no sweep gradient; fall back to the plain colour attribute.
            self.gradient_seq -= 1
            return None
        else:
            self.defs.append(
                f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" '
                f'x1="{attr(gradient, "startX") or 0}" y1="{attr(gradient, "startY") or 0}" '
                f'x2="{attr(gradient, "endX") or 0}" y2="{attr(gradient, "endY") or 0}">'
                f'{"".join(stops)}</linearGradient>'
            )
        return f"url(#{name})"


def with_extension(stem: Path, extension: str) -> Path:
    # Not Path.with_suffix: package names are dotted, and it would eat the TLD.
    return stem.with_name(stem.name + extension)


def escape(value: str) -> str:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace('"', "&quot;")


def image_type(data: bytes) -> str:
    """The format of an embedded bitmap, by magic number. Obfuscated APKs give
    their resource files no extension, so the name says nothing."""
    if data.startswith(b"\x89PNG"):
        return "png"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    return "jpeg"


# ─── Bitmap output ───────────────────────────────────────────────────────────

def write_bitmap(data: bytes, destination: Path, crop_to_safe_zone: bool, background=None) -> bool:
    if not PIL_AVAILABLE or not data:
        return False
    try:
        image = Image.open(BytesIO(data)).convert("RGBA")
        if background is not None:
            if isinstance(background, bytes):
                backdrop = Image.open(BytesIO(background)).convert("RGBA").resize(image.size, Image.LANCZOS)
            else:
                paint, alpha = background
                rgb = tuple(int(paint[i:i + 2], 16) for i in (1, 3, 5))
                backdrop = Image.new("RGBA", image.size, rgb + (int(alpha * 255),))
            backdrop.alpha_composite(image)
            image = backdrop
        if crop_to_safe_zone:
            inset_x = image.width * ADAPTIVE_INSET / ADAPTIVE_VIEWPORT
            inset_y = image.height * ADAPTIVE_INSET / ADAPTIVE_VIEWPORT
            image = image.crop((round(inset_x), round(inset_y),
                                round(image.width - inset_x), round(image.height - inset_y)))
        if max(image.size) > OUTPUT_SIZE:
            image.thumbnail((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)
        if not image.getchannel("A").getbbox():
            return False  # Fully transparent: a placeholder layer, not an icon
        image.save(destination, "PNG")
        return True
    except Exception as exc:
        warn(f"cannot write {destination.name}: {exc}")
        return False


def background_markup(resources: PackageResources, reference) -> str:
    """The adaptive background layer as SVG markup behind the foreground."""
    res_id = parse_reference(reference)
    if res_id is None:
        colour = resources.color_value(reference)
        if colour is None:
            return ""
        paint, alpha = colour
        return f'<rect x="0" y="0" width="{ADAPTIVE_VIEWPORT:g}" height="{ADAPTIVE_VIEWPORT:g}" fill="{paint}" opacity="{alpha:.3f}"/>'

    colour = resources.color(res_id)
    if colour is not None:
        paint, alpha = colour
        return f'<rect x="0" y="0" width="{ADAPTIVE_VIEWPORT:g}" height="{ADAPTIVE_VIEWPORT:g}" fill="{paint}" opacity="{alpha:.3f}"/>'

    bitmap = find_bitmap(resources, res_id)
    if bitmap is not None:
        table, entry = bitmap
        data = table.read(entry)
        if data:
            mime = image_type(data)
            encoded = base64.b64encode(data).decode("ascii")
            return (f'<image x="0" y="0" width="{ADAPTIVE_VIEWPORT:g}" height="{ADAPTIVE_VIEWPORT:g}" '
                    f'href="data:image/{mime};base64,{encoded}"/>')

    vector = find_vector(resources, res_id)
    if vector is not None:
        nested = VectorConverter(resources)
        inner = "".join(nested.emit_node(child) for child in vector)
        defs = "<defs>" + "".join(nested.defs) + "</defs>" if nested.defs else ""
        return defs + f"<g>{inner}</g>"
    return ""


# ─── Icon resolution ─────────────────────────────────────────────────────────

def wrapped_references(element):
    """Drawable references reachable from a wrapper element.

    `<animated-vector>`, `<bitmap>`, `<layer-list>`, `<inset>` and the rest all
    delegate to another drawable through the same two attributes.
    """
    for node in element.iter():
        for attribute in ("drawable", "src"):
            res_id = parse_reference(attr(node, attribute))
            if res_id is not None:
                yield res_id


def find_bitmap(resources: PackageResources, res_id: int, depth: int = 0):
    """The best bitmap for a resource id, unwrapping XML wrappers on the way."""
    bitmap = resources.best_bitmap(res_id)
    if bitmap is not None:
        return bitmap
    if depth > 3:
        return None
    drawable = resources.drawable_xml(res_id)
    if drawable is None or drawable[1].tag.rsplit("}", 1)[-1] == "adaptive-icon":
        return None
    for nested_id in wrapped_references(drawable[1]):
        found = find_bitmap(resources, nested_id, depth + 1)
        if found is not None:
            return found
    return None


def find_vector(resources: PackageResources, res_id: int, depth: int = 0):
    """The `<vector>` behind a resource id, unwrapping XML wrappers on the way."""
    drawable = resources.drawable_xml(res_id)
    if drawable is None:
        return None
    element = drawable[1]
    if element.tag.rsplit("}", 1)[-1] == "vector":
        return element
    if depth > 3 or element.tag.rsplit("}", 1)[-1] == "adaptive-icon":
        return None
    for nested_id in wrapped_references(element):
        found = find_vector(resources, nested_id, depth + 1)
        if found is not None:
            return found
    return None


def extract_icon(target_args, package: str, destination_stem: Path):
    """Resolve one package's launcher icon. Returns the written path, or None."""
    resources = PackageResources(target_args, package)
    if not resources.valid:
        return None

    for icon_id in resources.base.icon_ids():
        result = render_icon(resources, icon_id, destination_stem)
        if result is not None:
            return result
    return None


def render_icon(resources: PackageResources, icon_id: int, destination_stem: Path):
    """One icon resource: its own bitmap, else the drawable it points at, else
    any bitmap reachable from it. Each step only counts if it produced
    something visible, so an unresolvable layer falls through to the next."""
    bitmap = resources.best_bitmap(icon_id)
    if bitmap is not None:
        destination = with_extension(destination_stem, ".png")
        if write_bitmap(bitmap[0].read(bitmap[1]), destination, crop_to_safe_zone=False):
            return destination

    drawable = resources.drawable_xml(icon_id)
    if drawable is not None:
        result = render_drawable(resources, drawable[1], destination_stem, depth=0)
        if result is not None:
            return result

    fallback = find_bitmap(resources, icon_id)
    if fallback is not None:
        destination = with_extension(destination_stem, ".png")
        if write_bitmap(fallback[0].read(fallback[1]), destination, crop_to_safe_zone=False):
            return destination
    return None


def render_drawable(resources: PackageResources, element, destination_stem: Path, depth: int):
    if depth > 3:
        return None
    tag = element.tag.rsplit("}", 1)[-1]

    if tag == "adaptive-icon":
        return render_adaptive(resources, element, destination_stem)

    if tag == "vector":
        width = attr(element, "viewportWidth") or ADAPTIVE_VIEWPORT
        height = attr(element, "viewportHeight") or ADAPTIVE_VIEWPORT
        converter = VectorConverter(resources)
        svg = converter.convert(element, f"0 0 {float(width):g} {float(height):g}")
        if converter.painted:
            destination = with_extension(destination_stem, ".svg")
            destination.write_text(svg, encoding="utf-8")
            return destination
        # Nothing visible came out; let the caller try a bitmap instead

    for nested_id in wrapped_references(element):
        nested = resources.drawable_xml(nested_id)
        if nested is None:
            continue
        result = render_drawable(resources, nested[1], destination_stem, depth + 1)
        if result is not None:
            return result

    for nested_id in wrapped_references(element):
        bitmap = find_bitmap(resources, nested_id)
        if bitmap is None:
            continue
        destination = with_extension(destination_stem, ".png")
        if write_bitmap(bitmap[0].read(bitmap[1]), destination, crop_to_safe_zone=False):
            return destination
    return None


def layer_ids(layer):
    """The drawables an adaptive layer points at, named by attribute or inlined
    as a child element. Inlined layer lists give several, base first."""
    if layer is None:
        return []
    reference = parse_reference(attr(layer, "drawable"))
    if reference is not None:
        return [reference]
    return [res_id for child in layer for res_id in wrapped_references(child)]


def render_adaptive(resources: PackageResources, element, destination_stem: Path):
    foreground = background = None
    for child in element:
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "foreground":
            foreground = child
        elif tag == "background":
            background = child

    background_reference = attr(background, "drawable") if background is not None else None
    for foreground_id in layer_ids(foreground):
        result = render_adaptive_layer(resources, foreground_id, background_reference, destination_stem)
        if result is not None:
            return result
    return None


def render_adaptive_layer(resources: PackageResources, foreground_id: int, background, destination_stem: Path):
    bitmap = find_bitmap(resources, foreground_id)
    if bitmap is not None:
        table, entry = bitmap
        backdrop = None
        if background is not None:
            background_id = parse_reference(background)
            colour = resources.color(background_id) if background_id is not None else resources.color_value(background)
            if colour is not None:
                backdrop = colour
            elif background_id is not None:
                layer = find_bitmap(resources, background_id)
                if layer is not None:
                    backdrop = layer[0].read(layer[1])
        destination = with_extension(destination_stem, ".png")
        if write_bitmap(table.read(entry), destination, crop_to_safe_zone=True, background=backdrop):
            return destination

    vector = find_vector(resources, foreground_id)
    if vector is None:
        return None

    converter = VectorConverter(resources)
    backdrop = background_markup(resources, background) if background is not None else ""
    svg = converter.convert(vector, VectorConverter.adaptive_view_box(), background=backdrop)
    if not converter.painted:
        return None  # A foreground that resolved to nothing is not an icon

    destination = with_extension(destination_stem, ".svg")
    destination.write_text(svg, encoding="utf-8")
    return destination


# ─── Cache ───────────────────────────────────────────────────────────────────

def cache_dir(device_id: str) -> Path:
    safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in (device_id or "default"))
    directory = CACHE_ROOT / safe
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def miss_file(device_id: str) -> Path:
    return cache_dir(device_id) / "_misses.json"


def load_misses(device_id: str) -> dict:
    try:
        return json.loads(miss_file(device_id).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def record_miss(device_id: str, package: str) -> None:
    misses = load_misses(device_id)
    misses[package] = int(time.time())
    try:
        miss_file(device_id).write_text(json.dumps(misses), encoding="utf-8")
    except OSError as exc:
        warn(f"cannot record miss: {exc}")


def cached_icon(device_id: str, package: str):
    for suffix in (".png", ".svg"):
        candidate = cache_dir(device_id) / f"{package}{suffix}"
        if candidate.exists():
            return candidate
    return None


def scan_cache(device_id: str) -> dict:
    icons = {}
    for entry in cache_dir(device_id).iterdir():
        if entry.suffix in (".png", ".svg"):
            icons[entry.name[:-len(entry.suffix)]] = str(entry)
    return icons


# ─── Worker loop ─────────────────────────────────────────────────────────────

work_queue = queue.Queue()
in_flight = set()
in_flight_lock = threading.Lock()


def handle_fetch(package: str, device_id: str, target_args: list) -> None:
    cached = cached_icon(device_id, package)
    if cached is not None:
        emit({"event": "icon", "package": package, "path": str(cached)})
        return

    misses = load_misses(device_id)
    if time.time() - misses.get(package, 0) < MISS_TTL:
        emit({"event": "icon", "package": package, "path": ""})
        return

    if not device_online(target_args):
        emit({"event": "icon", "package": package, "path": "", "retry": True})
        return

    result = None
    try:
        result = extract_icon(target_args, package, cache_dir(device_id) / package)
    except Exception as exc:
        warn(f"{package}: {exc}")

    if result is None:
        # A phone that went away mid-fetch says nothing about the app's icon.
        # Recording that as a miss would blacklist it for a week over what is
        # really a dropped connection.
        if not device_online(target_args):
            emit({"event": "icon", "package": package, "path": "", "retry": True})
            return
        record_miss(device_id, package)
        emit({"event": "icon", "package": package, "path": ""})
        return
    emit({"event": "icon", "package": package, "path": str(result)})


def worker() -> None:
    while True:
        job = work_queue.get()
        if job is None:
            return
        package, device_id, target_args = job
        try:
            handle_fetch(package, device_id, target_args)
        finally:
            with in_flight_lock:
                in_flight.discard((device_id, package))
            work_queue.task_done()


def handle_command(message: dict) -> None:
    command = message.get("cmd")
    device_id = message.get("deviceId") or "default"

    if command == "cached":
        emit({"event": "cached", "deviceId": device_id, "icons": scan_cache(device_id)})
        return

    if command == "clear":
        forget_target()
        for entry in cache_dir(device_id).iterdir():
            try:
                entry.unlink()
            except OSError:
                pass
        emit({"event": "cleared", "deviceId": device_id})
        return

    if command != "fetch":
        return

    package = message.get("package")
    if not package:
        return

    key = (device_id, package)
    with in_flight_lock:
        if key in in_flight:
            return
        in_flight.add(key)
    work_queue.put((package, device_id, message.get("target_args") or []))


def main() -> None:
    if not PIL_AVAILABLE:
        emit({"event": "unavailable", "reason": "python-pillow is not installed"})

    workers = [threading.Thread(target=worker, daemon=True) for _ in range(WORKER_COUNT)]
    for thread in workers:
        thread.start()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            handle_command(json.loads(line))
        except ValueError as exc:
            warn(f"bad command: {exc}")

    work_queue.join()  # Let queued extractions finish when stdin closes


if __name__ == "__main__":
    main()
