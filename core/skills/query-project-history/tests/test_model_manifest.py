from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from model_manifest import ManifestError, verify_model_manifest


class ModelManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.snapshot = self.root / "repo" / "snapshots" / "abc"
        self.snapshot.mkdir(parents=True)
        (self.snapshot / "model.onnx").write_bytes(b"trusted model")
        digest = hashlib.sha256(b"trusted model").hexdigest()
        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "model_id": "example/model",
                    "repository": "example/model-onnx",
                    "revision": "abc",
                    "cache_path": "repo",
                    "files": [
                        {
                            "path": "model.onnx",
                            "sha256": digest,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_accepts_exact_manifest(self) -> None:
        result = verify_model_manifest(self.root, self.manifest)
        self.assertEqual(result["revision"], "abc")
        self.assertEqual(result["verified_files"], 1)

    def test_rejects_modified_file(self) -> None:
        (self.snapshot / "model.onnx").write_bytes(b"modified")
        with self.assertRaisesRegex(ManifestError, "hash mismatch"):
            verify_model_manifest(self.root, self.manifest)

    def test_rejects_missing_file(self) -> None:
        (self.snapshot / "model.onnx").unlink()
        with self.assertRaisesRegex(ManifestError, "missing"):
            verify_model_manifest(self.root, self.manifest)

    def test_rejects_unknown_snapshot_file(self) -> None:
        (self.snapshot / "payload.bin").write_bytes(b"unknown")
        with self.assertRaisesRegex(ManifestError, "unexpected"):
            verify_model_manifest(self.root, self.manifest)

    def test_rejects_path_traversal(self) -> None:
        value = json.loads(self.manifest.read_text(encoding="utf-8"))
        value["files"][0]["path"] = "../outside"
        self.manifest.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(ManifestError, "relative"):
            verify_model_manifest(self.root, self.manifest)


if __name__ == "__main__":
    unittest.main()
