import json
import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PublicReadmeTests(unittest.TestCase):
    def test_banner_is_wide_png_with_readable_alt_text(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        banner = ROOT / "docs/assets/tibia74-banner.png"
        self.assertTrue(banner.is_file())
        data = banner.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", data[16:24])
        self.assertGreaterEqual(width, 1200)
        self.assertGreater(width, height * 3)
        self.assertRegex(
            readme,
            r"!\[([^\]]*Tibia 7\.4[^\]]*)\]\(docs/assets/tibia74-banner\.png\)",
        )

    def test_readme_has_player_and_contributor_paths_and_public_boundary(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        required = (
            "https://tibia74.tech/",
            "https://tibia74.tech/index.php?jogar=1#criar-conta",
            "https://tibia74.tech/index.php?jogar=1#download",
            "https://tibia74.tech/wiki.php",
            "https://discord.gg/CVneyh53mZ",
            "docs/building.md",
            "CONTRIBUTING.md",
            "SECURITY.md",
            "cliente completo",
            "serviços privados",
            "local/README.md",
            "Tibia74-Local.exe",
            "SHA-256",
        )
        for link_or_phrase in required:
            with self.subTest(link_or_phrase=link_or_phrase):
                self.assertIn(link_or_phrase, readme)
        self.assertNotIn("cliente oficial assinado", readme)

    def test_readme_launcher_version_matches_release_manifest(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        manifest = json.loads((ROOT / "site/client-release.json").read_text(encoding="utf-8"))
        match = re.search(r"versão atual: \*\*v(\d+)\*\*", readme)
        self.assertIsNotNone(match, "README precisa citar a versão atual do launcher")
        self.assertEqual(int(match.group(1)), int(manifest["version"]))

    def test_repository_has_license_and_changelog(self):
        license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
        self.assertIn("GNU GENERAL PUBLIC LICENSE", license_text)
        self.assertIn("Version 2", license_text)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("](LICENSE)", readme)
        self.assertIn("](CHANGELOG.md)", readme)
        self.assertTrue((ROOT / "CHANGELOG.md").is_file())


if __name__ == "__main__":
    unittest.main()
