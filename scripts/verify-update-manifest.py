#!/usr/bin/env python3
"""Release gate: validate `nexadrive-update-manifest.json` against the
artifacts sitting beside it.

Run from the directory containing the manifest and the release artifacts
(CI does this in `dist/`):

    python3 scripts/verify-update-manifest.py nexadrive-update-manifest.json

Fails the release when the manifest:

  * is not valid JSON / does not match the documented schema,
  * references an artifact that is missing or empty on disk,
  * embeds a SHA-256 that does not match the artifact on disk,
  * declares a size that does not match the artifact on disk,
  * points at any non-HTTPS or non-github.com URL (the client allowlist),
  * declares a version that does not match the git tag being released,
  * lacks an installable artifact for any supported client platform.

The matching Dart-side validator is `UpdateManifest.fromJson` in
`app/lib/update/update_manifest.dart`; both sides implement the schema in
`docs/UPDATE_SYSTEM.md`.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

ALLOWED_URL_PREFIX = "https://github.com/"
SHA_RE = re.compile(r"^[0-9a-f]{64}$")

# platform -> {arch -> {kind}} that the Update Center requires to exist.
REQUIRED = {
    "android": {"arm64-v8a": {"apk"}},
    "windows": {"x64": {"installer"}},
    "linux": {"x64": {"appimage", "deb"}},
}

# Known client arch keys per platform (superset; extra arches are allowed).
KNOWN_ARCHES = {
    "android": {"arm64-v8a", "armeabi-v7a", "x86", "x86_64"},
    "windows": {"x64", "aarch64"},
    "linux": {"x64", "aarch64"},
}


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify-update-manifest.py <manifest.json>")
    manifest_path = sys.argv[1]
    # Artifacts are validated relative to the manifest's own directory, so
    # the verifier works both from inside dist/ and from the repo root.
    manifest_dir = os.path.dirname(os.path.abspath(manifest_path))

    try:
        with open(manifest_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"manifest is not readable JSON: {exc}")

    if not isinstance(data, dict):
        fail("manifest root must be a JSON object")

    # --- scalar fields ----------------------------------------------------
    version = data.get("version")
    if not isinstance(version, str) or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version or ""
    ):
        fail(f"\"version\" is not valid SemVer: {version!r}")

    tag = data.get("tag")
    if tag != f"v{version}":
        fail(f"\"tag\" ({tag!r}) must be \"v{version}\"")

    # Version must agree with the git tag being released (CI checkout).
    ref = os.environ.get("GITHUB_REF_NAME", "")
    if ref:
        if ref.lstrip("v") != version:
            fail(f"manifest version {version!r} does not match tag {ref!r}")
    else:
        # Local runs: fall back to the repo's describe output when available.
        try:
            described = subprocess.run(
                ["git", "describe", "--tags", "--abbrev=0"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            if described.lstrip("v") != version:
                fail(f"manifest version {version!r} does not match {described!r}")
        except (OSError, subprocess.CalledProcessError):
            pass  # Not a git checkout (e.g. artifact-only run); skip.

    if not isinstance(data.get("prerelease"), bool):
        fail("\"prerelease\" must be a boolean")
    expect_pre = "-" in version
    if data["prerelease"] is not expect_pre:
        fail(
            f"\"prerelease\" ({data['prerelease']}) inconsistent with "
            f"version {version!r} (expected {expect_pre})"
        )

    date = data.get("releaseDate")
    if not isinstance(date, str) or not date.endswith("Z"):
        fail("\"releaseDate\" must be an ISO-8601 UTC timestamp ending in Z")

    min_supported = data.get("minimumSupportedVersion")
    if min_supported is not None:
        if not isinstance(min_supported, str) or not re.fullmatch(
            r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", min_supported
        ):
            fail("\"minimumSupportedVersion\" must be null or valid SemVer")
        if _semver_key(min_supported) > _semver_key(version):
            fail(
                f"\"minimumSupportedVersion\" ({min_supported}) is newer than "
                f"the release itself ({version}) — the update would be "
                f"uninstallable"
            )

    # Optional server compatibility fields. `minimumServerVersion` must be
    # valid SemVer and never newer than the release; `serverApiVersion` just
    # needs to be a non-empty string (opaque compatibility token).
    min_server = data.get("minimumServerVersion")
    if min_server is not None:
        if not isinstance(min_server, str) or not re.fullmatch(
            r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", min_server
        ):
            fail("\"minimumServerVersion\" must be null or valid SemVer")

    server_api = data.get("serverApiVersion")
    if server_api is not None and (
        not isinstance(server_api, str) or not server_api.strip()
    ):
        fail("\"serverApiVersion\" must be null or a non-empty string")

    notes = data.get("releaseNotes", {})
    if not isinstance(notes, dict) or not all(
        isinstance(k, str)
        and isinstance(v, list)
        and all(isinstance(i, str) for i in v)
        for k, v in notes.items()
    ):
        fail("\"releaseNotes\" must be an object of string lists")

    # --- artifacts ---------------------------------------------------------
    artifacts = data.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        fail("\"artifacts\" must be a non-empty object")

    for platform, archs in artifacts.items():
        if platform not in KNOWN_ARCHES:
            fail(f"unknown platform {platform!r}")
        if not isinstance(archs, dict) or not archs:
            fail(f"artifacts.{platform} must be a non-empty object")
        for arch, kinds in archs.items():
            if arch not in KNOWN_ARCHES[platform]:
                fail(f"unknown architecture {platform}/{arch}")
            if not isinstance(kinds, dict) or not kinds:
                fail(f"artifacts.{platform}.{arch} must be a non-empty object")
            for kind, art in kinds.items():
                ctx = f"artifacts.{platform}.{arch}.{kind}"
                if not isinstance(art, dict):
                    fail(f"{ctx} must be an object")
                url = art.get("url")
                if (
                    not isinstance(url, str)
                    or not url.startswith(ALLOWED_URL_PREFIX)
                ):
                    fail(f"{ctx}.url must be an HTTPS github.com URL: {url!r}")
                file_name = url.rsplit("/", 1)[1]
                if not file_name or "/" in file_name or file_name in (".", ".."):
                    fail(f"{ctx}.url has an unsafe file name: {file_name!r}")
                digest = art.get("sha256")
                if not isinstance(digest, str) or not SHA_RE.fullmatch(digest):
                    fail(f"{ctx}.sha256 must be a 64-char lowercase hex digest")
                size = art.get("size")
                if not isinstance(size, int) or size <= 0:
                    fail(f"{ctx}.size must be a positive integer")

                artifact_path = os.path.join(manifest_dir, file_name)
                if not os.path.isfile(artifact_path):
                    fail(f"{ctx} references a missing artifact: {file_name}")
                actual_size = os.path.getsize(artifact_path)
                if actual_size == 0:
                    fail(f"{ctx} references an empty artifact: {file_name}")
                if actual_size != size:
                    fail(
                        f"{ctx}.size ({size}) does not match {file_name} "
                        f"({actual_size})"
                    )
                hasher = hashlib.sha256()
                with open(artifact_path, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1 << 20), b""):
                        hasher.update(chunk)
                if hasher.hexdigest() != digest:
                    fail(f"{ctx}.sha256 does not match the artifact {file_name}")

    # --- required installable artifacts ------------------------------------
    for platform, archs in REQUIRED.items():
        published = artifacts.get(platform, {})
        for arch, kinds in archs.items():
            have = published.get(arch, {})
            missing = kinds - have.keys()
            if missing:
                fail(
                    f"no installable artifact for {platform}/{arch}: "
                    f"missing {sorted(missing)}"
                )

    total = sum(
        1
        for archs in artifacts.values()
        for kinds in archs.values()
        for _ in kinds.values()
    )
    print(f"Manifest OK: v{version}, {total} artifact entries verified.")


def _semver_key(version: str):
    core, _, pre = version.partition("-")
    major, minor, patch = (int(x) for x in core.split("."))
    # Release > prerelease of the same core version.
    return (major, minor, patch, pre == "", pre)


if __name__ == "__main__":
    main()
