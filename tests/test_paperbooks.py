import json
import pathlib
import re
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "product/payload/apps/paperbooks"
BOOKS = APP / "books"


class PaperBooksTests(unittest.TestCase):
    def test_manifest_and_integration(self):
        manifest = json.loads((APP / "manifest.json").read_text())
        self.assertEqual(manifest["id"], "paperbooks")
        self.assertEqual(manifest["entry"], "/ui/main.qml")
        installer = (ROOT / "product/install.sh").read_text()
        uninstaller = (ROOT / "product/uninstall.sh").read_text()
        hub = (ROOT / "product/payload/apps/paperdesk/ui/main.qml").read_text()
        self.assertGreaterEqual(installer.count("paperbooks"), 3)
        self.assertIn("paperbooks", uninstaller)
        self.assertIn('objectName: "booksButton"', hub)
        self.assertIn('applicationId: "paperbooks"', hub)

    def test_iliad_is_complete_and_bundled(self):
        source = (BOOKS / "iliad-2199.txt").read_text(encoding="utf8").replace("\r\n", "\n")
        parts = [(BOOKS / f"iliad-{i:03}.txt").read_text(encoding="utf8") for i in range(25)]
        self.assertEqual("".join(parts), source)
        self.assertIn("Samuel Butler", parts[0])
        self.assertIn("*** START OF THE PROJECT GUTENBERG EBOOK", parts[0])
        self.assertIn("BOOK I.", parts[1])
        self.assertIn("BOOK XXIV.", parts[24])
        self.assertIn("END OF THE PROJECT GUTENBERG EBOOK", parts[-1])
        qrc = ET.parse(APP / "application.qrc")
        resources = {f.text for f in qrc.findall(".//file")}
        self.assertIn("ui/main.qml", resources)
        self.assertIn("books/iliad-2199.txt", resources)
        self.assertIn("books.js", resources)

    def test_javascript_engine_parses(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js unavailable")
        engine = (APP / "books.js").read_text().replace(".pragma library", "", 1)
        result = subprocess.run([node, "--check"], input=engine, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_offline_behavior_without_sqlite(self):
        node = shutil.which("node") or shutil.which("nodejs")
        if not node:
            self.skipTest("Node.js unavailable")
        result = subprocess.run(
            [node, str(ROOT / "tests/paperbooks-engine.cjs")],
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("complete downloads, continuous full text", result.stdout)

    def test_binary_resource_includes_text(self):
        resource = APP / "resources.rcc"
        self.assertTrue(resource.exists())
        self.assertGreater(resource.stat().st_size, 500_000)

    def test_source_preferences_and_font_independent_selection(self):
        qml = (APP / "ui/main.qml").read_text()
        self.assertIn('property string preferredSources: "gutenberg,europepmc"', qml)
        self.assertIn('objectName: "booksSource_" + modelData.code', qml)
        self.assertIn('objectName: "booksResultSource_" + bookId', qml)
        self.assertIn('objectName: "booksSettingsPage"', qml)
        self.assertIn('id: selectionMark', qml)
        self.assertNotIn('"✓"', qml)
        svg = (APP / "icon.svg").read_text()
        self.assertEqual(svg, (APP / "assets/icon.svg").read_text())
        self.assertIn('rx="34"', svg)
        self.assertIn('stroke-width="14"', svg)


if __name__ == "__main__":
    unittest.main()
