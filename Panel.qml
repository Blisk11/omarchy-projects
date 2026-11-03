import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Projects: every git repo under the configured roots with its git status.
// Open = editor (+ terminal), Dev = terminal running the dev command, Web =
// the repo's page on GitHub/GitLab/…, branch label = switch branch.
// scripts/projects does the work and prints JSON.
Panel {
  id: root
  moduleName: "techspawn.projects"
  ipcTarget: "techspawn.projects"
  manageIpc: true

  readonly property string helper: Qt.resolvedUrl("scripts/projects").toString().replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family

  // Nerd Font (Material Design) glyphs: md-git, md-source_branch, md-source_commit, md-source_merge, md-pencil,
  // md-arrow_up, md-arrow_down, md-cloud_off_outline, md-link_off, md-archive_outline, md-check, md-play,
  // md-console, md-file_code, md-github, md-gitlab, md-web, md-download, md-reload, md-sort_clock_descending,
  // md-sort_alphabetical_ascending, md-alert_circle_outline, md-file_tree, md-magnify.
  readonly property var glyphs: ({ git: 0xf02a2, branch: 0xf062c, commit: 0xf0718, conflict: 0xf062d, changed: 0xf03eb,
                                   ahead: 0xf005d, behind: 0xf0045, noUpstream: 0xf0164, gone: 0xf0338, stash: 0xf120e,
                                   clean: 0xf012c, play: 0xf040a, terminal: 0xf018d, editor: 0xf022e, github: 0xf02a4,
                                   gitlab: 0xf0ba0, web: 0xf059f, fetch: 0xf01da, refresh: 0xf0453, recent: 0xf154b,
                                   byName: 0xf05bd, error: 0xf05d6, worktree: 0xf0645, search: 0xf0349, edit: 0xf03eb,
                                   copy: 0xf018f })
  function glyph(name) { return String.fromCodePoint(glyphs[name]) }

  property var repos: []
  property string lastText: ""
  property string listError: ""
  property string filter: "all"
  property string query: ""
  property string sortBy: "recent"
  property string status: ""
  property bool statusError: false
  property bool fetching: false
  property string selectedPath: ""
  property string branchPath: ""        // card whose branch list is open
  property var branchList: []
  property double now: Date.now() / 1000

  function unpushed(r) { return r.ahead > 0 || (r.branch !== "" && !r.detached && !r.unborn && r.upstream === "" && r.remotes > 0) }
  function needsAttention(r) { return r.changes > 0 || r.conflicts > 0 || unpushed(r) }
  readonly property int attention: repos.filter(needsAttention).length
  readonly property var counts: ({
    changes: repos.filter(function(r) { return r.changes > 0 }).length,
    unpushed: repos.filter(unpushed).length,
    behind: repos.filter(function(r) { return r.behind > 0 }).length
  })

  function matches(r) {
    var words = query.toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
    if (!words.length) return true
    var hay = (r.name + " " + r.branch + " " + r.group + " " + r.path).toLowerCase()
    return words.every(function(w) { return hay.indexOf(w) >= 0 })
  }
  readonly property var shown: {
    var list = repos.filter(function(r) {
      if (!matches(r)) return false
      if (filter === "changes") return r.changes > 0
      if (filter === "unpushed") return unpushed(r)
      if (filter === "behind") return r.behind > 0
      return true
    })
    if (sortBy === "name")
      list = list.slice().sort(function(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
    return list
  }
  readonly property int selectedIndex: {
    for (var i = 0; i < shown.length; i++) if (shown[i].path === selectedPath) return i
    return shown.length ? 0 : -1
  }
  readonly property var selected: selectedIndex >= 0 ? shown[selectedIndex] : null

  function refresh() { if (!listProc.running && !fetching) listProc.running = true }
  function say(text, isError) { status = text; statusError = !!isError }

  function select(i) {
    if (!shown.length) return
    i = Math.max(0, Math.min(shown.length - 1, i))
    selectedPath = shown[i].path
    ensureVisible(i)
  }
  function ensureVisible(i) {
    var item = cards.itemAt(i)
    if (!item) return
    if (item.y < list.contentY) list.contentY = item.y
    else if (item.y + item.height > list.contentY + list.height) list.contentY = item.y + item.height - list.height
  }

  function fetchAll() {
    if (fetching) return
    fetching = true
    say("Fetching every repo…", false)
    fetchProc.running = true
  }

  // Runs a helper command; closes the panel when it worked, else shows why.
  function run(args, closeOnOk) {
    if (actProc.running) return
    actProc.closeOnOk = closeOnOk
    actProc.command = [helper].concat(args)
    actProc.running = true
  }
  function openWeb(r) {
    if (!r || !r.web) return
    Quickshell.execDetached(["xdg-open", r.web])
    close()
  }
  function copyPath(r) {
    if (!r || !r.path || copyProc.running) return
    copyProc.path = r.path
    copyProc.stdinEnabled = true
    copyProc.running = true
  }
  function toggleBranches(r) {
    if (!r) return
    if (branchPath === r.path) { branchPath = ""; return }
    branchPath = r.path
    branchList = []
    if (branchProc.running) branchProc.running = false
    branchProc.command = [helper, "branches", r.path]
    branchProc.running = true
  }

  function ago(ts) {
    if (!ts) return ""
    var s = Math.max(0, Math.floor(now - ts))
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    if (s < 86400 * 60) return Math.floor(s / 86400) + "d ago"
    return Math.floor(s / 86400 / 30) + "mo ago"
  }
  function webGlyph(url) {
    if (url.indexOf("github") >= 0) return glyph("github")
    if (url.indexOf("gitlab") >= 0) return glyph("gitlab")
    return glyph("web")
  }
  function shortPath(p) {
    var home = Quickshell.env("HOME")
    return p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p
  }

  function parseList(text, fromFetch) {
    if (text === lastText && !fromFetch) return
    lastText = text
    try {
      var d = JSON.parse(text)
      repos = d.repos || []
      listError = d.error || ""
      now = Date.now() / 1000
      if (d.fetch) {
        var f = d.fetch
        var msg = "Fetched " + f.fetched + " repo" + (f.fetched === 1 ? "" : "s")
        if (f.failed && f.failed.length)
          say(msg + " · " + f.failed.length + " failed: " + f.failed.slice(0, 3).map(function(x) { return x.name + " (" + x.error + ")" }).join(", "), true)
        else say(msg + ". Behind counts are up to date.", false)
      }
    } catch (e) {
      listError = "Couldn't read the project list (scripts/projects list)"
    }
  }

  onOpenedChanged: {
    if (!opened) return
    status = ""
    branchPath = ""
    search.text = ""
    selectedPath = ""
    list.contentY = 0
    refresh()
  }
  onQueryChanged: { selectedPath = ""; list.contentY = 0 }
  onFilterChanged: { selectedPath = ""; list.contentY = 0 }

  Process {
    id: listProc
    command: [root.helper, "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseList(text, false) }
  }

  Process {
    id: fetchProc
    command: [root.helper, "fetch", "--quiet"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseList(text, true) }
    onExited: root.fetching = false
  }

  Process {
    id: actProc
    property bool closeOnOk: false
    environment: ({ OMARCHY_NO_NOTIFY: "1" })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = {}
        try { d = JSON.parse(text) } catch (e) { d = { error: "The helper gave no answer" } }
        if (d.error) { root.say(d.error, true); return }
        if (actProc.closeOnOk) { root.close(); return }
        root.say(d.message || "Done", false)
      }
    }
    onExited: {
      if (actProc.closeOnOk) return
      root.lastText = ""
      root.refresh()
      if (root.branchPath !== "") { branchProc.command = [root.helper, "branches", root.branchPath]; branchProc.running = true }
    }
  }

  Process {
    id: copyProc
    property string path: ""
    command: ["wl-copy", "--type", "text/plain"]
    onStarted: {
      copyProc.write(copyProc.path)
      copyProc.stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) root.say("Copied path: " + copyProc.path, false)
      else root.say("Couldn't copy the repo path to the clipboard", true)
    }
  }

  Process {
    id: branchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.branchList = JSON.parse(text).branches || [] } catch (e) { root.branchList = [] }
      }
    }
  }

  Timer {
    interval: root.opened ? 15000 : 300000
    repeat: true
    running: true
    onTriggered: { root.now = Date.now() / 1000; root.refresh() }
  }
  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph("git")
    tooltipText: root.attention > 0 ? root.attention + " project" + (root.attention === 1 ? "" : "s") + " with uncommitted or unpushed work" : "Projects"
    onPressed: function(b) { root.toggle() }

    Rectangle {
      visible: root.attention > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -2
      width: Math.max(height, attText.implicitWidth + 3)
      height: attText.implicitHeight
      radius: height / 2
      color: "#f76b15"
      Text {
        id: attText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.attention > 9 ? "9+" : String(root.attention)
        color: root.bar ? root.bar.background : Commons.Color.background
        font.family: root.font
        font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.7))
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: search
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(10)

      Column {
        id: chrome
        width: parent.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          implicitHeight: hero.implicitHeight
          Row {
            id: hero
            spacing: Style.space(14)
            Text { textFormat: Text.PlainText; text: root.glyph("git"); color: root.fg; font.family: root.font; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text { textFormat: Text.PlainText; text: "Projects"; color: root.fg; font.family: root.font; font.pixelSize: Style.font.title; font.bold: true }
              Text {
                textFormat: Text.PlainText
                text: (root.repos.length + " repos · " + root.attention + " need attention" + (listProc.running ? " · updating…" : "")).toUpperCase()
                color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2
              }
            }
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Button {
              iconText: root.fetching ? root.glyph("refresh") : root.glyph("fetch")
              iconSpinning: root.fetching
              text: root.fetching ? "Fetching…" : "Fetch all"
              tooltipText: "git fetch every repo to see what you're behind on (Ctrl+F)"
              fontSize: Style.font.caption
              foreground: root.fg; fontFamily: root.font; bordered: true
              enabled: !root.fetching
              onClicked: root.fetchAll()
            }
            Button {
              iconText: root.sortBy === "recent" ? root.glyph("recent") : root.glyph("byName")
              tooltipText: root.sortBy === "recent" ? "Sorted by recent activity — sort by name (Ctrl+S)" : "Sorted by name — sort by recent activity (Ctrl+S)"
              foreground: root.fg; fontFamily: root.font
              onClicked: root.sortBy = root.sortBy === "recent" ? "name" : "recent"
            }
            Button {
              iconText: root.glyph("edit"); tooltipText: "Settings: roots, editor, terminal, dev commands"
              foreground: root.fg; fontFamily: root.font
              onClicked: root.run(["settings"], true)
            }
          }
        }

        TextField {
          id: search
          width: parent.width
          placeholderText: root.glyph("search") + "  Filter by name, branch or folder…"
          foreground: root.fg
          font.family: root.font
          onTextChanged: root.query = text
          Keys.onPressed: function(e) {
            var ctrl = e.modifiers & Qt.ControlModifier
            var r = root.selected
            if (e.key === Qt.Key_Escape) {
              if (root.branchPath !== "") root.branchPath = ""
              else if (search.text !== "") search.text = ""
              else root.close()
            }
            else if (e.key === Qt.Key_Down || (ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N))) root.select(root.selectedIndex + 1)
            else if (e.key === Qt.Key_Up || (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P))) root.select(root.selectedIndex - 1)
            else if (e.key === Qt.Key_PageDown) root.select(root.selectedIndex + 5)
            else if (e.key === Qt.Key_PageUp) root.select(root.selectedIndex - 5)
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && r) root.run(["open", r.path], true)
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) root.switchPanel((e.modifiers & Qt.ShiftModifier) || e.key === Qt.Key_Backtab ? -1 : 1)
            else if (ctrl && e.key === Qt.Key_E && r) root.run(["editor", r.path], true)
            else if (ctrl && e.key === Qt.Key_T && r) root.run(["term", r.path], true)
            else if (ctrl && e.key === Qt.Key_D && r) root.run(["dev", r.path], true)
            else if (ctrl && e.key === Qt.Key_O && r) root.openWeb(r)
            else if (ctrl && (e.modifiers & Qt.ShiftModifier) && e.key === Qt.Key_C && r) root.copyPath(r)
            else if (ctrl && e.key === Qt.Key_B && r) root.toggleBranches(r)
            else if (ctrl && e.key === Qt.Key_F) root.fetchAll()
            else if (ctrl && e.key === Qt.Key_R) { root.lastText = ""; root.refresh() }
            else if (ctrl && e.key === Qt.Key_S) root.sortBy = root.sortBy === "recent" ? "name" : "recent"
            else if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_4) root.filter = ["all", "changes", "unpushed", "behind"][e.key - Qt.Key_1]
            else return
            e.accepted = true
          }
        }

        ButtonGroup {
          width: parent.width
          focusable: false
          foreground: root.fg
          fontFamily: root.font
          fontSize: Style.font.bodySmall
          value: root.filter
          options: [
            { value: "all", label: "All " + root.repos.length },
            { value: "changes", label: "Uncommitted " + root.counts.changes },
            { value: "unpushed", label: "Unpushed " + root.counts.unpushed },
            { value: "behind", label: "Behind " + root.counts.behind }
          ]
          onChanged: function(v) { root.filter = v }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.listError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.listError
          color: Commons.Color.urgent; font.family: root.font; font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          visible: root.status !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.status
          color: root.statusError ? Commons.Color.urgent : Commons.Color.accent
          font.family: root.font; font.pixelSize: Style.font.bodySmall
        }
      }

      Item {
        width: parent.width
        height: list.height

        Flickable {
          id: list
          width: parent.width - (scrollbar.visible ? Style.space(8) : 0)
          // Never taller than the screen allows: the rest scrolls.
          height: Math.min(listCol.implicitHeight, Style.space(500),
                           Math.max(Style.space(120), panel.availableCardHeight - panel.verticalContentInset - chrome.height - column.spacing - 2))
          contentHeight: listCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: listCol
            width: list.width
            spacing: Style.space(5)

            Repeater {
              id: cards
              model: root.shown

              delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property var r: modelData
                readonly property bool isSelected: root.selectedIndex === index
                readonly property bool expanded: root.branchPath === r.path
                width: listCol.width
                implicitHeight: body.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: isSelected || area.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
                                                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
                border.width: isSelected || root.needsAttention(r) ? 1 : 0
                border.color: isSelected ? Commons.Color.accent : Qt.rgba(0.97, 0.42, 0.08, 0.6)

                MouseArea {
                  id: area
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.run(["open", card.r.path], true)
                }

                Column {
                  id: body
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  anchors.topMargin: Style.space(7)
                  spacing: Style.space(6)

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(info.implicitHeight, actions.implicitHeight)

                    Column {
                      id: info
                      anchors.left: parent.left
                      anchors.right: actions.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(3)

                      Row {
                        width: parent.width
                        spacing: Style.space(8)
                        Text {
                          id: nameText
                          textFormat: Text.PlainText
                          text: card.r.name
                          color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                          elide: Text.ElideRight
                          width: Math.min(implicitWidth, parent.width * 0.5)
                        }
                        Text {
                          id: branchText
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: (card.r.detached ? root.glyph("commit") + " detached @ " + card.r.head : root.glyph("branch") + " " + (card.r.branch || "?"))
                                + (card.r.unborn || card.r.error ? "" : (card.expanded ? " ▴" : " ▾"))
                          color: branchArea.containsMouse ? Commons.Color.accent : Qt.darker(root.fg, 1.3)
                          font.family: root.font; font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          width: Math.max(0, Math.min(implicitWidth, parent.width - nameText.width - tagText.width - Style.space(16)))
                          MouseArea {
                            id: branchArea
                            anchors.fill: parent
                            enabled: !card.r.unborn && !card.r.error
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBranches(card.r)
                          }
                        }
                        Text {
                          id: tagText
                          textFormat: Text.PlainText
                          anchors.verticalCenter: parent.verticalCenter
                          text: (card.r.worktree ? root.glyph("worktree") + " worktree · " : "") + card.r.group
                          color: Qt.darker(root.fg, 1.9); font.family: root.font; font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          width: Math.min(implicitWidth, parent.width * 0.3)
                        }
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(8)
                        Chip { visible: card.r.error !== ""; label: root.glyph("error") + " " + card.r.error; tint: Commons.Color.urgent }
                        Chip { visible: card.r.conflicts > 0; label: root.glyph("conflict") + " " + card.r.conflicts + " conflict" + (card.r.conflicts === 1 ? "" : "s"); tint: "#e5484d" }
                        Chip {
                          visible: card.r.changes - card.r.conflicts > 0
                          label: root.glyph("changed") + " " + (card.r.changes - card.r.conflicts) + " changed" + (card.r.staged ? " (" + card.r.staged + " staged)" : "")
                          tint: "#f76b15"
                        }
                        Chip { visible: card.r.ahead > 0; label: root.glyph("ahead") + " " + card.r.ahead + " to push"; tint: "#f76b15" }
                        Chip {
                          visible: card.r.upstream === "" && card.r.remotes > 0 && !card.r.detached && !card.r.unborn && card.r.error === ""
                          label: root.glyph("noUpstream") + " not pushed"; tint: "#ffc53d"
                        }
                        Chip { visible: card.r.upstreamGone; label: root.glyph("gone") + " upstream gone"; tint: "#ffc53d" }
                        Chip { visible: card.r.behind > 0; label: root.glyph("behind") + " " + card.r.behind + " behind"; tint: "#3e9bff" }
                        Chip { visible: card.r.stashes > 0; label: root.glyph("stash") + " " + card.r.stashes + " stash" + (card.r.stashes === 1 ? "" : "es"); tint: Qt.darker(root.fg, 1.4) }
                        Chip { visible: card.r.remotes === 0 && card.r.error === ""; label: "local only"; tint: Qt.darker(root.fg, 1.6) }
                        Chip {
                          visible: !root.needsAttention(card.r) && card.r.behind === 0 && card.r.upstream !== "" && !card.r.upstreamGone && card.r.error === ""
                          label: root.glyph("clean") + " clean"; tint: "#30a46c"
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: card.r.unborn ? "no commits yet"
                          : root.ago(card.r.lastCommit) + (card.r.lastSubject ? " · " + card.r.lastSubject : "")
                        color: Qt.darker(root.fg, 1.7); font.family: root.font; font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Row {
                      id: actions
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      Button {
                        iconText: root.glyph("copy")
                        tooltipText: "Copy local repo path: " + card.r.path + " (Ctrl+Shift+C)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        enabled: !copyProc.running
                        onClicked: root.copyPath(card.r)
                      }
                      Button {
                        visible: card.r.behind > 0 && card.r.upstream !== "" && !card.r.detached
                        iconText: root.glyph("fetch")
                        tooltipText: "Pull " + card.r.behind + " commit" + (card.r.behind === 1 ? "" : "s") + " (fast-forward only)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.run(["pull", card.r.path], false)
                      }
                      Button {
                        iconText: root.glyph("play")
                        tooltipText: card.r.dev ? "Run " + card.r.dev + " (Ctrl+D)" : "No dev command — set one under \"projects\" in the settings"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        opacity: card.r.dev ? 1 : 0.35
                        onClicked: {
                          if (card.r.dev) root.run(["dev", card.r.path], true)
                          else root.say("No dev command for " + card.r.name + " — add one under \"projects\" in the settings (pencil).", true)
                        }
                      }
                      Button {
                        iconText: root.glyph("terminal")
                        tooltipText: "Terminal in " + root.shortPath(card.r.path) + " (Ctrl+T)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.run(["term", card.r.path], true)
                      }
                      Button {
                        iconText: root.glyph("editor")
                        tooltipText: "Open in the editor only (Ctrl+E)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.run(["editor", card.r.path], true)
                      }
                      Button {
                        visible: card.r.web !== ""
                        iconText: root.webGlyph(card.r.web)
                        tooltipText: "Open " + card.r.web.replace(/^https:\/\//, "") + " (Ctrl+O)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.openWeb(card.r)
                      }
                    }
                  }

                  // Branch switcher (click the branch name or Ctrl+B).
                  Flow {
                    visible: card.expanded
                    width: parent.width
                    spacing: Style.space(4)
                    bottomPadding: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      visible: root.branchList.length === 0
                      text: branchProc.running ? "Loading branches…" : "No local branches"
                      color: Qt.darker(root.fg, 1.6); font.family: root.font; font.pixelSize: Style.font.caption
                    }
                    Repeater {
                      model: card.expanded ? root.branchList : []
                      delegate: Button {
                        required property var modelData
                        text: modelData.name + (modelData.track ? "  " + modelData.track : "")
                        iconText: modelData.current ? root.glyph("clean") : ""
                        selected: modelData.current
                        bordered: true
                        fontSize: Style.font.caption
                        foreground: root.fg; fontFamily: root.font
                        tooltipText: modelData.current ? "Current branch" : "Switch " + card.r.name + " to " + modelData.name
                        onClicked: if (!modelData.current) root.run(["switch", card.r.path, modelData.name], false)
                      }
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: card.r.staged + card.r.modified + card.r.conflicts > 0
                      text: "Commit or stash your changes before switching."
                      color: "#f76b15"; font.family: root.font; font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.shown.length === 0
              width: parent.width
              topPadding: Style.space(10)
              bottomPadding: Style.space(6)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: root.repos.length === 0 ? (root.lastText === "" ? "Looking for repos…" : "No projects found")
                  : root.query !== "" ? "Nothing matches “" + root.query + "”"
                  : "Nothing here — all good"
              color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              visible: root.shown.length > 0
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: "↑↓ select · Enter open · Ctrl+Shift+C copy path · Ctrl+E editor · Ctrl+T terminal · Ctrl+D dev · Ctrl+O web · Ctrl+B branches · Ctrl+F fetch"
              color: Qt.darker(root.fg, 1.9); font.family: root.font; font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle {
          id: scrollbar
          visible: list.contentHeight > list.height + 1
          anchors.right: parent.right
          y: list.visibleArea.yPosition * list.height
          width: Style.space(3)
          height: Math.max(Style.space(20), list.visibleArea.heightRatio * list.height)
          radius: width / 2
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
        }
      }
    }
  }

  component Chip: Text {
    textFormat: Text.PlainText
    property string label: ""
    property color tint: root.fg
    width: Math.min(implicitWidth, parent ? parent.width : implicitWidth)
    elide: Text.ElideRight
    text: label
    color: tint
    font.family: root.font
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
