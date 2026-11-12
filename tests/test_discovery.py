"""Discovery regressions using disposable trees; no Git or desktop commands."""
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest import mock


HELPER = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/projects"))
find_repos = HELPER["find_repos"]
excluded = HELPER["excluded"]


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="projects-discovery-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def repo(self, name):
        path = self.root / name
        # Discovery uses the marker only, so no real Git repository is needed.
        (path / ".git").mkdir(parents=True)
        return path

    def discover(self, **changes):
        config = {"roots": [str(self.root)], "depth": 4, "exclude": [], "repos": []}
        config.update(changes)
        return find_repos(config)

    def test_path_exclusion_prunes_subtree_before_listing(self):
        self.repo("blocked/group/hidden")
        visible = self.repo("visible")
        blocked = self.root / "blocked"
        with mock.patch.object(os, "listdir", wraps=os.listdir) as listing:
            self.assertEqual(self.discover(exclude=[str(blocked)]), [str(visible)])
        self.assertNotIn(str(blocked), [call.args[0] for call in listing.call_args_list])

    def test_basename_exclusion_prunes_plain_folders(self):
        self.repo("archive/group/hidden")
        visible = self.repo("visible")
        with mock.patch.object(os, "listdir", wraps=os.listdir) as listing:
            self.assertEqual(self.discover(exclude=["archive"]), [str(visible)])
        self.assertNotIn(str(self.root / "archive"), [c.args[0] for c in listing.call_args_list])

    def test_symlink_alias_of_excluded_subtree_is_pruned(self):
        self.repo("blocked/nested/hidden")
        (self.root / "alias").symlink_to(self.root / "blocked", target_is_directory=True)
        self.assertEqual(self.discover(exclude=[str(self.root / "blocked")]), [])

    def test_exclusion_through_symlink_also_matches_real_path(self):
        self.repo("blocked/nested/hidden")
        alias = self.root / "alias"
        alias.symlink_to(self.root / "blocked", target_is_directory=True)
        self.assertEqual(self.discover(exclude=[str(alias)]), [])

    def test_explicit_repos_and_roots_cannot_bypass_path_exclusion(self):
        hidden = self.repo("blocked/nested/hidden")
        alias = self.root / "alias"
        alias.symlink_to(self.root / "blocked/nested", target_is_directory=True)
        self.assertEqual(self.discover(roots=[str(alias)], repos=[str(hidden)],
                                       exclude=[str(self.root / "blocked")]), [])

    def test_excluded_scan_root_is_not_listed(self):
        self.repo("nested/hidden")
        with mock.patch.object(os, "listdir", wraps=os.listdir) as listing:
            self.assertEqual(self.discover(exclude=[str(self.root)]), [])
        listing.assert_not_called()

    def test_path_boundary_and_trailing_separator(self):
        hidden = self.repo("blocked/hidden")
        sibling = self.repo("blocked-other/visible")
        self.assertEqual(self.discover(exclude=[str(self.root / "blocked") + os.sep]),
                         [str(sibling)])
        self.assertTrue(excluded(str(hidden), {"exclude": [str(self.root / "blocked")]}))

    def test_filesystem_root_exclusion(self):
        self.repo("visible")
        with mock.patch.object(os, "listdir", wraps=os.listdir) as listing:
            self.assertEqual(self.discover(exclude=[os.path.abspath(os.sep)]), [])
        listing.assert_not_called()

    def test_environment_path_expansion_and_normalization(self):
        self.repo("blocked/nested/hidden")
        with mock.patch.dict(os.environ, PROJECTS_TEST_ROOT=str(self.root)):
            self.assertEqual(self.discover(exclude=["$PROJECTS_TEST_ROOT/other/../blocked"]), [])

    def test_ordinary_discovery_and_no_descent_into_repos(self):
        direct = self.repo("direct")
        nested = self.repo("group/nested")
        self.repo("direct/embedded")
        self.repo("node_modules/hidden")
        self.repo(".hidden/repo")
        self.assertEqual(self.discover(), [str(direct), str(nested)])

    def test_repo_roots_explicit_repos_and_alias_deduplication(self):
        repo = self.repo("actual")
        alias = self.root / "alias"
        alias.symlink_to(repo, target_is_directory=True)
        self.assertEqual(self.discover(roots=[str(repo), str(alias)], repos=[str(repo)]),
                         [str(repo)])

    def test_depth_limits_and_invalid_depth_fallback(self):
        repos = [self.repo("/".join(["group"] * (level - 1) + [f"repo{level}"]))
                 for level in range(1, 6)]
        for depth, count in [(1, 1), (2, 2), (4, 4), (0, 1), (99, 4), ("invalid", 2)]:
            with self.subTest(depth=depth):
                self.assertCountEqual(self.discover(depth=depth),
                                      [str(path) for path in repos[:count]])


if __name__ == "__main__":
    unittest.main()
