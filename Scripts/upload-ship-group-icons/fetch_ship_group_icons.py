#!/usr/bin/env python3
"""
One-time prep script for EVEOps' Discord Rich Presence ship icons.

Discord's local Rich Presence can only display images pre-uploaded as named
"Art Assets" on the Application (capped at 300 per app) — it cannot fetch an
arbitrary URL or a file from EVEOps itself at runtime. EVE has 400+ individual
ship hulls, too many to cover 1:1, so EVEOps keys the image by *ship group*
(Frigate, Cruiser, Battleship, etc.) instead of exact hull — see
`DiscordRichPresence.largeImageAssetKey(forShipGroupID:)` in the app.

This script does the one-time prep: it walks every published ship group via
ESI, picks one representative published hull per group, and downloads that
hull's render from CCP's public image server (images.evetech.net). It does
NOT talk to Discord at all — Discord's Rich Presence asset upload is tied to
your Developer Portal login session, so automating it here would mean
scripting against your personal Discord account, which this deliberately
avoids. Upload the resulting files by hand:

    Discord Developer Portal -> your application -> Rich Presence -> Art Assets
    -> Add Image -> name it exactly as the file's stem (e.g. "shipgroup_25")

Usage:
    python3 fetch_ship_group_icons.py [--out DIR]

Requires only the Python 3 standard library — no pip installs.
"""

from __future__ import annotations

import argparse
import csv
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

ESI_BASE = "https://esi.evetech.net/latest"
IMAGES_BASE = "https://images.evetech.net"
SHIP_CATEGORY_ID = 6

# CCP's ESI best-practice guidelines ask for a descriptive User-Agent with
# contact info: https://developers.eveonline.com/docs/guides/esi-guide/
USER_AGENT = "EVEOps-RichPresence-IconPrep/1.0 (github.com/MikeManzo/EVEOps; contact: manzo.mike@gmail.com)"

REQUEST_DELAY_SECONDS = 0.1


def get_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


CONTENT_TYPE_EXTENSIONS = {"image/png": ".png", "image/jpeg": ".jpg"}


def download(url: str, dest_stem: Path) -> Path | None:
    """Downloads to `dest_stem` with an extension matching the real content type —
    images.evetech.net serves /render as JPEG and /icon as PNG, so the extension
    can't be assumed up front."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            content_type = response.headers.get_content_type()
            extension = CONTENT_TYPE_EXTENSIONS.get(content_type, ".img")
            dest = dest_stem.with_suffix(extension)
            dest.write_bytes(response.read())
            return dest
    except urllib.error.HTTPError:
        return None


def pick_representative_type(type_ids: list[int]) -> dict | None:
    """First published type in the group, by ascending type ID (deterministic)."""
    for type_id in sorted(type_ids):
        time.sleep(REQUEST_DELAY_SECONDS)
        try:
            type_info = get_json(f"{ESI_BASE}/universe/types/{type_id}/?datasource=tranquility")
        except urllib.error.HTTPError:
            continue
        if type_info.get("published"):
            return type_info
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="output", help="Output directory (default: ./output)")
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching ship category (id={SHIP_CATEGORY_ID}) from ESI...")
    category = get_json(f"{ESI_BASE}/universe/categories/{SHIP_CATEGORY_ID}/?datasource=tranquility")
    group_ids = category["groups"]
    print(f"Found {len(group_ids)} ship groups.")

    manifest_rows = []
    covered, skipped = 0, 0

    for group_id in sorted(group_ids):
        time.sleep(REQUEST_DELAY_SECONDS)
        group = get_json(f"{ESI_BASE}/universe/groups/{group_id}/?datasource=tranquility")
        if not group.get("published", False):
            print(f"  skip group {group_id} ({group['name']}) — unpublished")
            skipped += 1
            continue

        representative = pick_representative_type(group["types"])
        if representative is None:
            print(f"  skip group {group_id} ({group['name']}) — no published hull found")
            skipped += 1
            continue

        asset_key = f"shipgroup_{group_id}"
        dest_stem = out_dir / asset_key

        dest = download(f"{IMAGES_BASE}/types/{representative['type_id']}/render?size=512", dest_stem)
        if dest is None:
            # Some hulls (e.g. certain structures/rigs miscategorized as ships) have
            # no render — fall back to the icon variant.
            dest = download(f"{IMAGES_BASE}/types/{representative['type_id']}/icon?size=512", dest_stem)

        if dest is None:
            print(f"  skip group {group_id} ({group['name']}) — image download failed")
            skipped += 1
            continue

        print(f"  {dest.name} <- {group['name']!r} using {representative['name']!r} (type {representative['type_id']})")
        manifest_rows.append({
            "asset_key": asset_key,
            "group_id": group_id,
            "group_name": group["name"],
            "representative_type_id": representative["type_id"],
            "representative_type_name": representative["name"],
        })
        covered += 1

    manifest_path = out_dir / "manifest.csv"
    with manifest_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "asset_key", "group_id", "group_name", "representative_type_id", "representative_type_name"
        ])
        writer.writeheader()
        writer.writerows(manifest_rows)

    print(f"\nDone: {covered} ship-group icons written to {out_dir}/, {skipped} skipped.")
    print(f"Review {manifest_path} — swap in a different representative hull per group if you'd prefer.")
    print("Then upload each image to Discord Developer Portal -> Rich Presence -> Art Assets,")
    print("naming each asset exactly after its filename stem (no extension), e.g. \"shipgroup_25\".")
    print("Also upload EVEOps/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png as \"eveops_icon\" (the fallback image).")


if __name__ == "__main__":
    main()
