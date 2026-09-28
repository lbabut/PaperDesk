import importlib.util
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import shutil
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
stub = types.ModuleType("tkinter")
stub.messagebox = types.SimpleNamespace()
stub.ttk = types.SimpleNamespace()
with patch.dict(sys.modules, {"tkinter": stub}):
    spec = importlib.util.spec_from_file_location(
        "paperdesk_desktop_installer", ROOT / "desktop-installer.py")
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)


class DesktopInstallerTests(unittest.TestCase):
    def test_bundled_payload_is_verified(self):
        installer.verify_package()

    def test_modified_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory)
            (copied / "payload").mkdir()
            shutil.copy2(installer.PRODUCT / "install.sh", copied / "payload/install.sh")
            from hashlib import sha256
            original = (copied / "payload/install.sh").read_bytes()
            (copied / "SHA256SUMS").write_text(
                sha256(original).hexdigest() + "  ./payload/install.sh\n")
            (copied / "payload/install.sh").write_bytes(original + b"changed")
            with patch.object(installer, "PRODUCT", copied):
                with self.assertRaisesRegex(ValueError, "verification failed"):
                    installer.verify_package()

    def test_archive_excludes_management_code_and_contains_installer(self):
        data = installer.make_archive()
        with tarfile.open(fileobj=io.BytesIO(data.read()), mode="r:gz") as archive:
            names = archive.getnames()
        self.assertIn("install.sh", names)
        self.assertIn("SHA256SUMS", names)
        self.assertFalse(any(name.endswith("paperdesk.local.conf") for name in names))


if __name__ == "__main__":
    unittest.main()
