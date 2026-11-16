# Drift report — 2026-11-16

Repository: `omarchy-projects-contribution`. Source HEAD: `1768d8acfa8f51d29189356fa90d4dc19eda694d`.

Scope: Entire README compared with discovery, status, launch, switch/fetch and panel source. No settings writes, GUI interaction, app launches, fetch/pull or branch switches run.

Inspected source: `scripts/projects`, `Panel.qml`, `manifest.json`, `tests/test_discovery.py`.

## README.md

- [P3] Panel status claims a count of changed files, but `scripts/projects:317–323` increments staged and modified independently then sums them. One tracked file with both staged and unstaged edits contributes two changes. Count unique porcelain entries for a file count or label it change-state counts.

## Resolution of cross-repository findings (2026-11-16)

The findings above describe the audited baseline. Counted each tracked porcelain file entry once while preserving overlapping staged/modified badges. Added a mixed staged/unstaged regression.

Verification route: python -m unittest discover -s tests; no fetch, app launch or desktop operation.
The original coverage limits remain in force.
