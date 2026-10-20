import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class LearningCanaryTests(unittest.TestCase):
    def test_shadow_launcher_requires_qa_marker_and_never_targets_public_host(self):
        text = (ROOT / 'output/autonomous_learning_shadow.ps1').read_text()
        self.assertIn('QA_ONLY', text)
        self.assertIn('shadow', text.lower())
        self.assertIn('127.0.0.1', text)
        self.assertIn("$qaHost = '127.0.0.1'", text)

    def test_status_helper_is_read_only_and_redacts_secrets(self):
        text = (ROOT / 'output/autonomous_learning_read_status.ps1').read_text()
        self.assertIn('Get-Content', text)
        self.assertNotIn('Set-Content', text)
        self.assertIn('Select-Object at,agents,shadow', text)
        self.assertIn('Select-Object at,sample,population,sql_measured_at,error', text)


if __name__ == '__main__':
    unittest.main()
