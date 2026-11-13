#!/usr/bin/env python3
"""Align Android library plugin modules with the app's required compile SDK."""
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

CONFIG = Path(".dart_tool/package_config.json")
TARGET_SDK = 36
REQUIRED_PACKAGES = {"file_picker", "flutter_plugin_android_lifecycle"}

if not CONFIG.is_file():
    raise SystemExit("Missing .dart_tool/package_config.json; run flutter pub get first.")

packages = json.loads(CONFIG.read_text(encoding="utf-8"))["packages"]
changed = []
seen_required = set()

# Flutter plugins are separate Gradle subprojects. Updating only android/app
# does not change the compileSdk declared by those plugin projects.
pattern = re.compile(
    r"(?m)^([ \t]*(?:compileSdkVersion|compileSdk)\s*(?:=\s*)?)"
    r"(flutter\.compileSdkVersion|[0-9]+)([ \t]*(?://.*)?$)"
)

for package in packages:
    name = package.get("name")
    root_uri = package.get("rootUri", "")
    parsed = urlparse(root_uri)
    if parsed.scheme == "file":
        root = Path(unquote(parsed.path))
    else:
        root = (CONFIG.parent / unquote(root_uri)).resolve()

    gradle_files = [
        root / "android" / "build.gradle",
        root / "android" / "build.gradle.kts",
    ]
    gradle = next((path for path in gradle_files if path.is_file()), None)
    if gradle is None:
        continue

    source = gradle.read_text(encoding="utf-8")
    result, count = pattern.subn(
        lambda match: (
            match.group(1) + str(TARGET_SDK) + match.group(3)
            if match.group(2) == "flutter.compileSdkVersion"
            or int(match.group(2)) < TARGET_SDK
            else match.group(0)
        ),
        source,
    )
    if name in REQUIRED_PACKAGES:
        seen_required.add(name)
        effective = re.search(
            r"(?m)^\s*(?:compileSdkVersion|compileSdk)\s*(?:=\s*)?([0-9]+)\b",
            result,
        )
        if not effective or int(effective.group(1)) < TARGET_SDK:
            raise SystemExit(
                f"Could not align {name}: no compileSdk >= {TARGET_SDK} in {gradle}."
            )

    if count and result != source:
        gradle.write_text(result, encoding="utf-8")
        changed.append((name, str(gradle), count))
        print(f"{name}: compileSdk aligned to {TARGET_SDK} in {gradle}.")

missing = REQUIRED_PACKAGES - seen_required
if missing:
    raise SystemExit("Required Android plugin package(s) not found: " + ", ".join(sorted(missing)))

if not changed:
    print(f"Required Android plugin compileSdk declarations already use {TARGET_SDK} or newer.")
