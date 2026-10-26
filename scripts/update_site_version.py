#!/usr/bin/env python3
"""Point the website at a published Android release.

Reads site/next_changelog.txt when it exists, then deletes it so the same
note is not reused for the next tag.
"""

import argparse
import json
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--build-number", required=True, type=int)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--changelog", default="")
    parser.add_argument("--site-dir", type=Path, default=None)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    site = args.site_dir or (root / "site")
    version_path = site / "version.json"
    html_path = site / "index.html"
    notes_path = site / "next_changelog.txt"

    previous = {}
    if version_path.exists():
        previous = json.loads(version_path.read_text(encoding="utf-8"))

    changelog = args.changelog.strip()
    if not changelog and notes_path.exists():
        changelog = notes_path.read_text(encoding="utf-8").strip()
        notes_path.unlink()
    if not changelog:
        if previous.get("version") == args.version and previous.get("changelog"):
            changelog = str(previous["changelog"])
        else:
            changelog = f"إصدار {args.version}"

    download = (
        f"https://github.com/{args.repo}/releases/download/"
        f"{args.tag}/money_traker-{args.tag}.apk"
    )
    data = {
        "version": args.version,
        "build_number": args.build_number,
        "force_update": bool(previous.get("force_update", False)),
        "download_url": download,
        "changelog": changelog,
    }
    version_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if not html_path.exists():
        return
    html = html_path.read_text(encoding="utf-8")
    html = re.sub(
        r"https://github\.com/[^\"']+/releases/download/v[^\"']+\.apk",
        download,
        html,
    )
    html = re.sub(
        r'(<strong id="version-label">)[^<]*(</strong>)',
        rf"\g<1>{args.version}\g<2>",
        html,
        count=1,
    )
    safe = (
        changelog.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )
    html = re.sub(
        r'(<p id="changelog" class="changelog">)[\s\S]*?(</p>)',
        rf"\g<1>\n            {safe}\n          \g<2>",
        html,
        count=1,
    )
    html_path.write_text(html, encoding="utf-8")


if __name__ == "__main__":
    main()
