# Projects

All your git repositories in one Omarchy bar widget: branch, uncommitted
changes, commits to push or pull, stashes. Find one by typing, open it in your
editor and a terminal, start its dev server, switch branch, pull, or fetch
them all at once.

Plugin id: `techspawn.projects`

## What it does

- **Bar:** a git icon with a badge that counts the repos with uncommitted or
  unpushed work.
- **Panel:** a card per repo, the most recently active first (last commit,
  checkout or staging), or sorted by name. Each card shows:
  - the branch, or `detached @ <commit>`, plus the parent folder; git
    worktrees are tagged
  - badges for conflicts, changed files (and how many are staged), commits
    to push, a branch that was never pushed, an upstream branch that was
    deleted, commits behind, stashes, *local only* (no remote), *no commits
    yet* and *clean*
  - the time and subject of the last commit
  - git errors (a broken repository, a timeout) on the card instead of
    hiding the repo
- Filter tabs: **All**, **Uncommitted**, **Unpushed**, **Behind**. Type to
  filter by name, branch or folder.
- Click a card or press `Enter` to open the repo in your editor plus a
  terminal there. The buttons on each card run the dev command, open a
  terminal only, open the editor only, open the repo's web page (GitHub,
  GitLab, Gitea, Codeberg …, worked out from the remote, never with
  credentials), and **Pull** (fast-forward only) when it is behind.
- **Copy path** on each card copies the full local repository path to the
  clipboard, ready to paste into an AI agent's prompt. The panel stays open
  and confirms which path was copied.
- Click the branch name (or `Ctrl+B`) to list the local branches, newest
  first, and switch with a click. Switching is refused while tracked files
  have changes; untracked files are fine.
- **Fetch all** runs `git fetch --all --prune` in every repo, in parallel,
  never asks for a password, and reports which repos failed and why.

Repos are found in each root folder and in folders below it that are not
repos themselves (see `depth`), git worktrees included. `git status` runs
with optional locks turned off, so a refresh never leaves an `index.lock` in
the way of your own git commands.

### Keyboard

The filter box has the focus when the panel opens:

- type to filter; `Esc` closes the branch list, then clears the filter, then
  closes the panel
- Down / Up, `Ctrl+J` / `Ctrl+K`, `Ctrl+N` / `Ctrl+P` or Page Down / Page Up
  select a repo
- `Enter` opens the selected repo (editor and terminal)
- `Ctrl+E` editor only, `Ctrl+T` terminal only, `Ctrl+D` dev command,
  `Ctrl+O` web page
- `Ctrl+B` shows the branches
- `Ctrl+Shift+C` copies the selected repo's full local path
- `Ctrl+F` fetches all, `Ctrl+R` refreshes, `Ctrl+S` sorts by recent
  activity or by name
- `Ctrl+1` to `Ctrl+4` pick a filter tab
- `Tab` moves to the next bar panel

## Install

```bash
omarchy plugin add https://github.com/RajShimpi/omarchy-projects
omarchy bar put techspawn.projects
```

You can also use **Install plugin** in the Omarchy menu with the repository URL.

## Remove

```bash
omarchy plugin remove techspawn.projects
```

To clear what it left behind (your settings):

```bash
rm -f ~/.config/omarchy/projects.json
```

## Settings

Click the pencil in the panel. The first time, this creates
`~/.config/omarchy/projects.json` with the defaults and opens it in your
editor. The plugin never writes that file otherwise. Missing keys use these
defaults:

```json
{
  "roots": ["~/Projects", "~/projects", "~/Code", "~/code", "~/src", "~/dev", "~/Work", "~/work"],
  "depth": 2,
  "repos": [],
  "exclude": [],
  "editor": "omarchy-launch-editor",
  "terminal": "xdg-terminal-exec",
  "openTerminal": true,
  "projects": {}
}
```

| Key | Meaning |
| --- | --- |
| `roots` | Folders that hold your repos. Folders that do not exist are skipped. |
| `depth` | How many folder levels below a root to look, 1 to 4. With 2, both `~/Projects/app` and `~/Projects/clients/app` are found. The plugin never looks inside a repo. |
| `repos` | Extra repos that live anywhere else, by path. |
| `exclude` | Folder names or paths to exclude before scanning. A path excludes the entire subtree, including symlink aliases and entries in `roots` or `repos`; a sibling with the same path prefix is unaffected. A folder name excludes matching repos and prunes matching scan folders. |
| `editor` | Command that opens a repo; its path is added at the end. The default opens the editor chosen with `omarchy default editor`. Other examples: `"code"`, `"cursor"`, `"zeditor"`, `"$VISUAL"`. Terminal editors (`nvim`, `hx` …) open in a terminal. |
| `terminal` | `xdg-terminal-exec` (Omarchy's default terminal), or `ghostty`, `kitty`, `alacritty`, `foot`, `wezterm`, `konsole` or `gnome-terminal`, which get the right working-directory option. For anything else, put `{dir}` where the folder goes, e.g. `"myterm --cwd {dir}"`. |
| `openTerminal` | Whether opening a repo also opens a terminal in it. |
| `projects` | Settings per repo, keyed by folder name, `~/path` or full path. For now only `dev`: the command the play button runs in a terminal. |

Without a `dev` entry the command is guessed from the repo: the `dev`,
`start` or `serve` script of `package.json` (run with bun, pnpm, yarn or npm,
depending on the lock file), `deno task dev`, `bin/dev`,
`docker compose up`, `python manage.py runserver` or `php artisan serve`.

An example:

```json
{
  "roots": ["~/Projects", "~/Work"],
  "repos": ["~/dotfiles"],
  "exclude": ["old-prototype"],
  "editor": "code",
  "terminal": "ghostty",
  "projects": {
    "shop-api": { "dev": "docker compose up -d && npm run dev" },
    "~/Work/website": { "dev": "hugo server" }
  }
}
```

## Command line

The panel runs `scripts/projects`. You can use it too; it prints JSON:

```bash
scripts/projects list                        # every repo with its status
scripts/projects fetch [--quiet]             # fetch all, then list
scripts/projects open <path>                 # editor + terminal
scripts/projects editor|term|dev <path>
scripts/projects branches <path>             # local branches, newest first
scripts/projects pull <path>                 # fast-forward only
scripts/projects switch <path> <branch>
scripts/projects extras                      # branches and recent files of every repo
```

Run from the command line, `fetch`, `pull`, `switch` and failed launches
send a desktop notification. `OMARCHY_NO_NOTIFY=1` prints them instead, and
`PROJECTS_CONFIG` points the script at another settings file.

## How it works and dependencies

- `scripts/projects` is a Python 3 script that uses only the standard
  library, plus `git`.
- It starts apps with `uwsm-app`, `xdg-terminal-exec`, `xdg-open` and
  `omarchy-launch-editor`, and notifies with `omarchy-notification-send`.
  Omarchy ships all of them.
- The status refreshes every 15 s while the panel is open and every 5 min
  otherwise, for the badge. Eight repos are read in parallel; about 30 repos
  take a second.
- Fetch and pull run ssh in batch mode with a 10 s connection timeout (your
  own `core.sshCommand` is kept) and never wait for a password: repos that
  need one are reported as failed. Credential helpers still work.
- Repo names, branches and commit subjects are shown as plain text, so
  markup in a commit message is never rendered or loaded.
- Nothing is sent anywhere.

## License

MIT. See [LICENSE](LICENSE).
