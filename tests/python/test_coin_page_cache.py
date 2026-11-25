import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class CoinPageCacheTests(unittest.TestCase):
    def test_public_pages_do_not_direct_players_to_payment(self):
        for name in ("index.php", "account.php", "wiki.php"):
            source = (ROOT / "site" / name).read_text(encoding="utf-8")
            self.assertNotIn('href="/coins.php"', source)
            self.assertNotIn("After manual payment approval", source)
        wiki = (ROOT / "site/wiki.php").read_text(encoding="utf-8")
        self.assertIn("Website purchases are disabled.", wiki)
        self.assertIn("The Market supports player offers for items and coins.", wiki)
        translations = (ROOT / "site/i18n-extra.php").read_text(encoding="utf-8")
        self.assertEqual(translations.count("Website purchases are disabled. Player trades remain available in the Market."), 3)

    def test_retired_routes_never_load_private_payment_services(self):
        source = (ROOT / "site/coins.php").read_text(encoding="utf-8")
        for header in ("Cache-Control: private, no-store, max-age=0", "Pragma: no-cache", "Expires: 0"):
            self.assertIn(header, source)
        for private_api in ("webDb(", "pixOrder(", "pixQr(", "pixQuote(", "require ", "PIX_KEY", "pixKey"):
            self.assertNotIn(private_api, source)
        self.assertTrue((ROOT / "tests/php/coin-page-tests.php").is_file())

if __name__ == "__main__":
    unittest.main()
