#!/usr/bin/env python3
"""Build the flat Hellenic insignias supplied by the NixOS Hyperion port."""

from __future__ import annotations

import argparse
import hashlib
import math
import re
from pathlib import Path
from xml.etree import ElementTree as ET

from achievement_motifs import MOTIFS, MOTIF_BY_ID

ROOT = Path(__file__).resolve().parents[1]
BADGES = ROOT / "assets/hyperion-progression/badges"
INKS = {
    "common": ("#727982", "#959da8"),
    "uncommon": ("#839546", "#a1b85d"),
    "rare": ("#13599e", "#2179bc"),
    "epic": ("#80208f", "#a43eb1"),
    "legendary": ("#f4bd22", "#ffce47"),
    "mythic": ("#bd1738", "#f02e51"),
    "holographic": ("#8ceaf0", "#d9a7fa"),
}
IVORY = "#f0e8dc"
BLACK = "#08090b"


def path(points, fill="P"):
    return f'<polygon points="{points}" fill="{fill}"/>'


def laurels():
    out = []
    for side in (-1, 1):
        for i in range(6):
            y = 240 - i * 23
            x = 160 + side * (87 + 17 * math.sin(i * 0.48))
            tipx = x + side * (29 - i)
            tipy = y - 17
            innerx = x - side * 10
            out.append(path(f"{x:.1f},{y} {tipx:.1f},{tipy} {x+side*12:.1f},{y-25} {innerx:.1f},{y-10}", "I"))
    return "".join(out)


def greek_key(side):
    chunks = []
    for i in range(4):
        x = (47 + 23 * i) if side < 0 else (273 - 23 * i)
        y = 90 - (i * 14)
        if side < 0:
            d = f"M{x} {y+16}v-13h17v12h-9v-5"
        else:
            d = f"M{x} {y+16}v-13h-17v12h9v-5"
        chunks.append(f'<path d="{d}" fill="none" stroke="I" stroke-width="6" stroke-linecap="square" stroke-linejoin="miter"/>')
    return "".join(chunks)


def frame(form):
    if form == 0:
        outer = '<path d="M160 14L211 41Q268 58 284 126Q303 209 253 258L160 309L67 258Q17 209 36 126Q52 58 109 41Z" fill="P"/>'
        inner = '<path d="M160 28L207 54Q255 69 270 129Q286 203 242 245L160 291L78 245Q34 203 50 129Q65 69 113 54Z" fill="N"/>'
    elif form == 1:
        outer = '<path d="M160 13L211 43L284 77V205L253 260L160 309L67 260L36 205V77L109 43Z" fill="P"/>'
        inner = '<path d="M160 29L209 58L269 88V201L242 247L160 290L78 247L51 201V88L111 58Z" fill="N"/>'
    else:
        outer = '<path d="M160 14L211 39Q272 45 287 122Q305 207 254 258L160 309L66 258Q15 207 33 122Q48 45 109 39Z" fill="P"/>'
        inner = '<path d="M160 29L209 52Q260 58 272 127Q289 200 243 246L160 291L77 246Q31 200 48 127Q60 58 111 52Z" fill="N"/>'
    return outer + inner


def emblem(badge_id, title, rarity, form, variation):
    motif = MOTIF_BY_ID[badge_id]
    if motif == "laurel":
        motif = "olive"
    icon = MOTIFS[motif]
    icon = icon.replace('fill="P"', 'fill="I"').replace('stroke="P"', 'stroke="I"')
    icon = icon.replace('fill="N"', 'fill="N"').replace('stroke="N"', 'stroke="N"')
    rays = ""
    if rarity in ("legendary", "mythic", "holographic"):
        rays = "".join(
            path(f"160,73 154,98 166,98", "P").replace('<polygon ', f'<polygon transform="rotate({i * 30} 160 162)" ', 1)
            for i in range(12)
        )
    tabs = '<path d="M125 29L160 8L195 29L188 61L160 72L132 61Z" fill="P"/>'
    tabs += '<path d="M160 23L166 38L181 38L169 48L173 62L160 54L147 62L151 48L139 38L154 38Z" fill="N"/>'
    centre = f'<g transform="translate(160 162) scale(1.58)">{icon}</g>'
    insignia = (
        frame(form) + greek_key(-1) + greek_key(1) + rays
        + '<circle cx="160" cy="162" r="70" fill="P"/>'
        + '<circle cx="160" cy="162" r="60" fill="N"/>'
        + centre + laurels() + tabs
        + '<path d="M138 271L160 290L182 271L160 280Z" fill="P"/>'
    )
    return insignia


def render(badge_id, title, rarity, form, variant=0):
    primary, secondary = INKS[rarity]
    if rarity == "holographic":
        primary, secondary = [
            ("#8ceaf0", "#d9a7fa"),
            ("#d9a7fa", "#ffd0e6"),
            ("#ffd0e6", "#b5f7ec"),
            ("#b5f7ec", "#8ceaf0"),
        ][variant]
    if rarity == "mythic" and variant:
        primary, secondary = secondary, primary
    body = emblem(badge_id, title, rarity, form, variant)
    body = body.replace('fill="P"', f'fill="{primary}"')
    body = body.replace('fill="I"', f'fill="{IVORY}"')
    body = body.replace('fill="N"', f'fill="{BLACK}"')
    body = body.replace('stroke="I"', f'stroke="{IVORY}"')
    body = body.replace('stroke="N"', f'stroke="{BLACK}"')
    body = body.replace('stroke="P"', f'stroke="{primary}"')
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="320" viewBox="0 0 320 320">\n'
        f'<title>{title.replace("&", "&amp;")}</title>\n'
        f'<desc>Flat Hellenic achievement insignia. {rarity.title()} rarity.</desc>\n'
        f'<g stroke-linecap="square" stroke-linejoin="miter">{body}</g>\n'
        '</svg>\n'
    )
    ET.fromstring(svg)
    return svg


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    assets = [p for p in BADGES.glob("*.svg") if ".foil" not in p.stem and not p.stem.endswith(".pulse")]
    if len(assets) != 72:
        raise RuntimeError(f"Expected 72 badges, found {len(assets)}")
    for original in assets:
        root = ET.parse(original).getroot()
        title = root.find("{http://www.w3.org/2000/svg}title").text or original.stem
        desc = root.find("{http://www.w3.org/2000/svg}desc").text or ""
        rarity_match = re.search(r"\b(Common|Uncommon|Rare|Epic|Legendary|Mythic|Holographic) rarity", desc)
        if not rarity_match:
            raise RuntimeError(f"Cannot determine rarity for {original.name}")
        rarity = rarity_match.group(1).lower()
        if original.stem not in MOTIF_BY_ID:
            raise RuntimeError(f"Missing motif for {original.stem}")
        digest = hashlib.sha256(original.stem.encode()).digest()
        form = digest[0] % 3
        variants = 2 if rarity in ("mythic", "holographic") else 1
        for variant in range(variants):
            suffix = ".foil" if rarity == "holographic" and variant else ".pulse" if variant else ""
            target = original.with_name(original.stem + suffix + ".svg")
            svg = render(original.stem, title, rarity, form, 2 if rarity == "holographic" and variant else variant)
            if args.check:
                if not target.exists() or target.read_text() != svg:
                    raise RuntimeError(f"Out-of-date insignia: {target}")
            else:
                target.write_text(svg)
    print("Validated 72 badges with Mythic and Holographic colour frames")


if __name__ == "__main__":
    main()
