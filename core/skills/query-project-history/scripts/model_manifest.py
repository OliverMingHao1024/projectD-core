from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$|^[A-Za-z0-9._-]+$")


class ManifestError(ValueError):
    pass


def _safe_relative_path(value: object, field: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{field} must be a non-empty relative path")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ManifestError(f"{field} must be a safe relative path")
    return path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_model_manifest(cache_root: Path, manifest_path: Path) -> dict[str, object]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read model manifest: {error}") from error
    if manifest.get("schema_version") != 1:
        raise ManifestError("unsupported model manifest schema_version")
    for field in ("model_id", "repository"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ManifestError(f"{field} must be a non-empty string")
    revision = manifest.get("revision")
    if not isinstance(revision, str) or not REVISION_PATTERN.fullmatch(revision):
        raise ManifestError("revision is invalid")
    cache_path = _safe_relative_path(manifest.get("cache_path"), "cache_path")
    root = cache_root.resolve()
    snapshot = (root / cache_path / "snapshots" / revision).resolve()
    if root not in snapshot.parents:
        raise ManifestError("model snapshot escapes cache root")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise ManifestError("files must contain at least one entry")

    expected: dict[Path, str] = {}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ManifestError(f"files[{index}] must be an object")
        relative = _safe_relative_path(entry.get("path"), f"files[{index}].path")
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not SHA256_PATTERN.fullmatch(digest):
            raise ManifestError(f"files[{index}].sha256 is invalid")
        if relative in expected:
            raise ManifestError(f"duplicate model file: {relative.as_posix()}")
        expected[relative] = digest

    if not snapshot.is_dir():
        raise ManifestError(f"model snapshot is missing: {snapshot}")
    actual = {
        path.relative_to(snapshot)
        for path in snapshot.rglob("*")
        if path.is_file()
    }
    missing = sorted(expected.keys() - actual)
    unexpected = sorted(actual - expected.keys())
    if missing:
        raise ManifestError(
            "model file missing: " + ", ".join(path.as_posix() for path in missing)
        )
    if unexpected:
        raise ManifestError(
            "unexpected model file: "
            + ", ".join(path.as_posix() for path in unexpected)
        )
    for relative, expected_hash in expected.items():
        actual_hash = _sha256(snapshot / relative)
        if actual_hash != expected_hash:
            raise ManifestError(f"model hash mismatch: {relative.as_posix()}")
    return {
        "model_id": manifest["model_id"],
        "repository": manifest["repository"],
        "revision": revision,
        "verified_files": len(expected),
    }


def download_model_from_manifest(cache_root: Path, manifest_path: Path) -> Path:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read model manifest: {error}") from error
    if manifest.get("schema_version") != 1:
        raise ManifestError("unsupported model manifest schema_version")
    repository = manifest.get("repository")
    revision = manifest.get("revision")
    files = manifest.get("files")
    if not isinstance(repository, str) or not repository.strip():
        raise ManifestError("repository must be a non-empty string")
    if not isinstance(revision, str) or not REVISION_PATTERN.fullmatch(revision):
        raise ManifestError("revision is invalid")
    if not isinstance(files, list) or not files:
        raise ManifestError("files must contain at least one entry")
    allow_patterns = [
        _safe_relative_path(entry.get("path"), f"files[{index}].path").as_posix()
        for index, entry in enumerate(files)
        if isinstance(entry, dict)
    ]
    if len(allow_patterns) != len(files):
        raise ManifestError("every model file entry must be an object")
    try:
        from huggingface_hub import snapshot_download
    except ImportError as error:
        raise ManifestError("huggingface_hub is required to download the model") from error
    downloaded = snapshot_download(
        repo_id=repository,
        revision=revision,
        cache_dir=cache_root,
        allow_patterns=allow_patterns,
    )
    return Path(downloaded)


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify a cached embedding model")
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args(arguments)
    try:
        if args.download:
            download_model_from_manifest(args.cache_root, args.manifest)
        result = verify_model_manifest(args.cache_root, args.manifest)
    except ManifestError as error:
        parser.error(str(error))
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
