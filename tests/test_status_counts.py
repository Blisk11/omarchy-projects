"""Count Git files once while retaining overlapping staged/unstaged badges."""
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

status = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/projects'))['status']


class StatusCountTests(unittest.TestCase):
    def test_staged_and_unstaged_changes_on_one_file_count_once(self):
        porcelain = '# branch.oid (initial)\n# branch.head main\n1 MM N... 100644 100644 100644 a b mixed.txt\n1 .M N... 100644 100644 100644 a b other.txt\n? new.txt\nu UU N... 100644 100644 100644 100644 a b c conflict.txt\n'
        def git(path, *args, **kwargs):
            return (True, porcelain, '') if args[0] == 'status' else (False, '', '')
        with patch.dict(status.__globals__, git=git, git_dirs=lambda p: ('/nonexistent', '/nonexistent'), dev_command=lambda p, s: ''):
            value = status('/synthetic/project', {})
        self.assertEqual(value['staged'], 1)
        self.assertEqual(value['modified'], 2)
        self.assertEqual(value['conflicts'], 1)
        self.assertEqual(value['untracked'], 1)
        self.assertEqual(value['changes'], 4)
