// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io

// Storage: each drive on its own (the eMMC and the microSD card are never
// summed), where the internal drive's space goes, a clean-up of what is safe
// to rebuild, and the apps by size with uninstall. Everything it shows or
// does goes through omamobile-storage (the helper beside it); the system
// items and uninstall go through pkexec, so Omarchy's polkit agent asks for
// the password. Drawn in the Omarchy theme (docs/design/dev-tools style):
// outer corners 12 px, inner 4-8 px, the chosen tab inverted.
ShellRoot {
  id: app

  // ------------------------------------------------------------ theme
  readonly property string home: Quickshell.env("HOME")
  FileView {
    id: themeFile
    path: app.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
  }
  function themeColor(key, fallback) {
    var m = new RegExp("^" + key + "\\s*=\\s*\"(#[0-9a-fA-F]{6})\"", "m").exec(themeFile.text() || "")
    return m ? m[1] : fallback
  }
  readonly property color bg: themeColor("background", "#0b0d11")
  readonly property color card: themeColor("dark_background", "#12151b")
  readonly property color raised: themeColor("lighter_background", "#1c2029")
  readonly property color fg: themeColor("foreground", "#e8ebf1")
  readonly property color dim: themeColor("dark_foreground", "#7d8492")
  readonly property color soft: themeColor("light_foreground", "#c3c8d2")
  readonly property color cFiles: themeColor("green", "#9ddbb4")
  readonly property color cSystem: themeColor("blue", "#9cc2ff")
  readonly property color cLogs: themeColor("yellow", "#ffe09a")
  readonly property color cCache: themeColor("magenta", "#c4b5ff")
  readonly property color cOther: themeColor("muted", "#6b7280")
  readonly property color cRed: themeColor("red", "#ffa8ae")
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property string mono: "JetBrainsMono Nerd Font"
  readonly property int touch: 48
  readonly property int side: 20

  // ------------------------------------------------------------ state
  // overview | clean | apps; `omamobile-storage clean-up` or `uninstall` opens on its tab.
  property string tab: ["overview", "clean", "apps"].indexOf(Quickshell.env("OMAMOBILE_STORAGE_TAB")) >= 0 ? Quickshell.env("OMAMOBILE_STORAGE_TAB") : "overview"
  property var drives: []
  property var places: []             // [{key, label, path, bytes, partial}] of the internal drive
  property var driveUsage: ({})       // mount -> usage answer, for drives other than "/"
  property var cleanItems: []
  property var selected: ({ cache: true, logs: true, packages: true, trash: true })
  property var apps: []
  property var folderStack: []        // paths, the last one shown
  property var folder: null           // usage answer for the folder shown
  property var sheetApp: null         // the app the uninstall sheet is about
  property bool deleteData: false
  property string busy: ""            // what is running: "" when idle
  property string message: ""
  property real usedBefore: -1        // the internal drive's used bytes before a clean-up

  readonly property var internal: {
    for (var i = 0; i < drives.length; i++) if (drives[i].mount === "/") return drives[i]
    return null
  }

  function fmt(b) {
    if (b === null || b === undefined || isNaN(b)) return "–"
    if (b >= 1e9) return (b / 1e9).toFixed(b >= 1e11 ? 0 : 1) + " GB"
    if (b >= 1e6) return Math.round(b / 1e6) + " MB"
    if (b >= 1e3) return Math.round(b / 1e3) + " KB"
    return b + " B"
  }
  function pct(part, whole) { return whole > 0 ? Math.max(0, Math.min(1, part / whole)) : 0 }
  function place(key) {
    for (var i = 0; i < places.length; i++) if (places[i].key === key) return places[i]
    return null
  }
  function placeBytes(key) { var p = place(key); return p && p.bytes ? p.bytes : 0 }

  // The internal drive split into what the legend lists; "other" is the
  // rest of what df counts as used (packages, /var, /opt, trash).
  readonly property var internalParts: {
    if (!internal || places.length === 0) return []
    var cache = placeBytes("cache"), trash = placeBytes("trash")
    var files = Math.max(0, placeBytes("home") - cache - trash)
    var system = placeBytes("system"), logs = placeBytes("logs")
    var other = Math.max(0, internal.used - files - system - logs - cache)
    return [
      { label: "Your files", bytes: files, color: cFiles, path: home },
      { label: "Apps and system", bytes: system, color: cSystem, path: "/usr" },
      { label: "System logs", bytes: logs, color: cLogs, path: "/var/log" },
      { label: "App caches", bytes: cache, color: cCache, path: home + "/.cache" },
      { label: "Packages and other", bytes: other, color: cOther, path: "/" }
    ]
  }
  // A drive other than "/": its top folders, or for the card that still
  // holds the previous system, that backup and the data folder.
  function partsOf(d) {
    var u = driveUsage[d.mount]
    if (!u || !u.items) return []
    if (d.system_copy) {
      var data = 0, dataPath = d.mount + "/data"
      for (var i = 0; i < u.items.length; i++) if (u.items[i].name === "data") data = u.items[i].bytes
      return [
        { label: "Previous system", badge: "backup", bytes: Math.max(0, d.used - data), color: cLogs, path: d.mount },
        { label: "data/", bytes: data, color: cFiles, path: dataPath }
      ]
    }
    var out = [], palette = [cFiles, cSystem, cCache, cLogs]
    for (var j = 0; j < u.items.length && out.length < 4; j++) {
      var it = u.items[j]
      if (it.bytes <= 0) continue
      out.push({ label: it.name + (it.dir ? "/" : ""), bytes: it.bytes, color: palette[out.length], path: it.dir ? it.path : d.mount })
    }
    return out
  }

  readonly property real cleanTotal: {
    var t = 0
    for (var i = 0; i < cleanItems.length; i++) if (selected[cleanItems[i].key]) t += cleanItems[i].bytes
    return t
  }
  readonly property bool cleanExact: {
    for (var i = 0; i < cleanItems.length; i++)
      if (selected[cleanItems[i].key] && cleanItems[i].bytes > 0 && !cleanItems[i].exact) return false
    return true
  }
  readonly property real appsMax: apps.length ? Math.max(1, apps[0].bytes) : 1

  // ------------------------------------------------------------ helper calls
  component Asker: Process {
    id: asker
    workingDirectory: app.home
    property string kind: ""
    property var pending: null
    function ask(args) {
      if (running) { pending = args; return }
      command = ["omamobile-storage"].concat(args)
      running = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: app.answer(asker.kind, text)
    }
    onExited: if (pending) { var again = pending; pending = null; ask(again) }
  }
  Asker { id: askDrives; kind: "drives" }
  Asker { id: askPlaces; kind: "places" }
  Asker { id: askCard; kind: "card" }
  Asker { id: askClean; kind: "clean-info" }
  Asker { id: askApps; kind: "apps" }
  Asker { id: askFolder; kind: "folder" }

  function answer(kind, text) {
    var data
    try { data = JSON.parse(text) } catch (error) { return }
    if (kind === "drives") {
      drives = data
      if (usedBefore >= 0 && internal) {
        var freed = usedBefore - internal.used
        message = freed > 0 ? "freed " + fmt(freed) : "nothing more to free"
        usedBefore = -1
      }
      for (var i = 0; i < data.length; i++) if (data[i].mount !== "/") askCard.ask(["usage", data[i].mount])
    } else if (kind === "places") {
      places = data
    } else if (kind === "card") {
      var map = Object.assign({}, driveUsage)
      map[data.dir] = data
      driveUsage = map
    } else if (kind === "clean-info") {
      cleanItems = data
    } else if (kind === "apps") {
      apps = data
    } else if (kind === "folder") {
      if (folderStack.length && data.dir === folderStack[folderStack.length - 1]) folder = data
    }
  }

  function refresh() {
    askDrives.ask(["drives"])
    askPlaces.ask(["places"])
    askClean.ask(["clean-info"])
    askApps.ask(["apps"])
  }
  Component.onCompleted: refresh()

  function openFolder(path) {
    folderStack = folderStack.concat([path])
    folder = null
    askFolder.ask(["usage", path])
  }
  function closeFolder() {
    var s = folderStack.slice(0, -1)
    folderStack = s
    folder = null
    if (s.length) askFolder.ask(["usage", s[s.length - 1]])
  }

  // ------------------------------------------------------------ actions
  // One action at a time; its output is read back as the message.
  Process {
    id: worker
    workingDirectory: app.home
    stderr: StdioCollector { id: workerErr; waitForEnd: true }
    onExited: (code, status) => {
      var what = app.busy
      app.busy = ""
      if (code !== 0) {
        var err = (workerErr.text || "").trim().split("\n").pop()
        app.message = what + " stopped" + (err ? ": " + err.replace(/^omamobile-storage: /, "") : "")
        app.usedBefore = -1
      } else if (what === "uninstall") {
        app.message = "uninstalled"
      }
      app.refresh()
    }
  }
  function startWork(what, cmd) {
    if (busy !== "") return
    message = ""
    busy = what
    worker.command = cmd
    worker.running = true
  }
  function cleanUp() {
    var user = [], root = []
    for (var i = 0; i < cleanItems.length; i++) {
      var it = cleanItems[i]
      if (!selected[it.key] || it.bytes <= 0) continue
      if (it.key === "cache" || it.key === "trash") user.push(it.key)
      else if (it.key === "logs") root.push("clean-logs")
      else if (it.key === "packages") root.push("clean-packages")
    }
    if (!user.length && !root.length) return
    // Fixed words only: the keys come from the helper's own list.
    var script = "set -e\n"
    if (user.length) script += "omamobile-storage clean " + user.join(" ") + " >/dev/null\n"
    if (root.length) script += "pkexec omamobile-storage root " + root.join(" ") + " >/dev/null\n"
    usedBefore = internal ? internal.used : -1
    startWork("clean-up", ["sh", "-c", script])
  }
  function uninstall() {
    var a = sheetApp
    if (!a || a.locked || !/^[a-z0-9@._+-]+$/.test(a.pkg)) return
    var paths = []
    if (deleteData) for (var i = 0; i < a.data.length; i++) paths.push(a.data[i].path)
    sheetApp = null
    // The package and the paths travel as arguments, never inside the script.
    startWork("uninstall", ["sh", "-c",
      'pkexec omamobile-storage root remove "$1" >/dev/null && shift && if [ $# -gt 0 ]; then omamobile-storage remove-data "$@" >/dev/null; fi',
      "sh", a.pkg].concat(paths))
  }

  // ------------------------------------------------------------ pieces
  component Label: Text {
    color: app.fg; font.family: app.mono; font.pixelSize: 14
  }
  component Dim: Text {
    color: app.dim; font.family: app.mono; font.pixelSize: 12
  }

  // A row with a coloured dot, a label, a size and a chevron.
  component LegendRow: Item {
    id: lr
    property string label: ""
    property string badge: ""
    property real bytes: 0
    property color dot: app.fg
    property bool first: false
    signal tapped()
    width: parent ? parent.width : 0
    height: 38
    Rectangle { visible: !lr.first; width: parent.width; height: 1; color: app.line }
    Rectangle { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 3; color: lr.dot }
    Row {
      x: 21; anchors.verticalCenter: parent.verticalCenter; spacing: 8
      Label { text: lr.label; font.pixelSize: 14 }
      Rectangle {
        visible: lr.badge !== ""; anchors.verticalCenter: parent.verticalCenter
        width: badgeText.implicitWidth + 12; height: 18; radius: 4; color: app.cLogs
        Text { id: badgeText; anchors.centerIn: parent; text: lr.badge; color: app.bg; font.family: app.mono; font.pixelSize: 10; font.bold: true }
      }
    }
    Label { anchors.right: chev.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: app.fmt(lr.bytes); color: app.soft; font.pixelSize: 14 }
    Dim { id: chev; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "›" }
    MouseArea { anchors.fill: parent; onClicked: lr.tapped() }
  }

  // A stacked bar: parts [{bytes, color}] of a whole.
  component StackBar: Rectangle {
    id: sb
    property var parts: []
    property real whole: 1
    width: parent ? parent.width : 0
    height: 10; radius: 5; color: app.raised; clip: true
    Row {
      height: parent.height; spacing: 2
      Repeater {
        model: sb.parts
        delegate: Rectangle {
          required property var modelData
          height: sb.height
          width: Math.max(modelData.bytes > 0 ? 3 : 0, (sb.width - 2 * sb.parts.length) * app.pct(modelData.bytes, sb.whole))
          color: modelData.color
        }
      }
    }
  }

  component Button: Rectangle {
    id: button
    property string label: ""
    property string kind: "primary"     // primary | ghost | danger
    property bool enabled: true
    signal tapped()
    height: 52; radius: 10
    color: kind === "ghost" ? (buttonTouch.pressed ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.08) : "transparent")
      : kind === "danger" ? app.cRed : app.fg
    opacity: enabled ? (buttonTouch.pressed && kind !== "ghost" ? 0.85 : 1) : 0.35
    border.width: kind === "ghost" ? 1 : 0
    border.color: app.line
    Text {
      anchors.centerIn: parent; text: button.label
      color: button.kind === "ghost" ? app.fg : app.bg
      font.family: app.mono; font.pixelSize: 15; font.bold: true
    }
    MouseArea { id: buttonTouch; anchors.fill: parent; onClicked: if (button.enabled) button.tapped() }
  }

  // ------------------------------------------------------------ window
  FloatingWindow {
    id: win
    title: "Storage"
    implicitWidth: 480
    implicitHeight: 1000
    color: app.bg

    Item {
      id: page
      anchors.fill: parent
      anchors.leftMargin: app.side
      anchors.rightMargin: app.side

      // Title, then the tabs.
      Item {
        id: header
        width: parent.width; height: 56; y: 8
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: app.folderStack.length ? "‹  " + app.shortPath(app.folderStack[app.folderStack.length - 1]) : "storage"
          width: parent.width - 80; elide: Text.ElideLeft
          color: app.fg; font.family: app.mono; font.pixelSize: 19; font.bold: true
          MouseArea { anchors.fill: parent; enabled: app.folderStack.length > 0; onClicked: app.closeFolder() }
        }
        Dim {
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: 13
          text: app.busy !== "" ? app.busy + "…" : app.folderStack.length ? (app.folder ? app.fmt(app.folder.total) : "")
            : app.tab === "overview" ? app.drives.length + (app.drives.length === 1 ? " drive" : " drives")
            : app.tab === "apps" ? app.apps.length + " apps" : "internal"
          MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: if (app.busy === "") app.refresh() }
        }
      }
      Rectangle {
        id: tabs
        visible: app.folderStack.length === 0
        anchors.top: header.bottom; anchors.topMargin: 6
        width: parent.width; height: 48; radius: 8; color: "transparent"; border.width: 1; border.color: app.line
        Row {
          anchors.fill: parent; anchors.margins: 4; spacing: 4
          Repeater {
            model: [["overview", "overview"], ["clean", "clean up"], ["apps", "apps"]]
            delegate: Rectangle {
              required property var modelData
              width: (parent.width - 8) / 3; height: parent.height; radius: 4
              color: app.tab === modelData[0] ? app.fg : "transparent"
              Text {
                anchors.centerIn: parent; text: modelData[1]
                color: app.tab === modelData[0] ? app.bg : app.fg
                font.family: app.mono; font.pixelSize: 14; font.bold: true
              }
              MouseArea { anchors.fill: parent; onClicked: app.tab = modelData[0] }
            }
          }
        }
      }

      Flickable {
        id: scroll
        anchors.top: app.folderStack.length ? header.bottom : tabs.bottom
        anchors.topMargin: 16
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: body.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: body
          width: scroll.width
          spacing: 14

          // ---------------------------------------------------- folder view
          Column {
            visible: app.folderStack.length > 0
            width: parent.width
            Dim {
              width: parent.width; wrapMode: Text.Wrap; bottomPadding: 10
              text: !app.folder ? "measuring…"
                : app.folder.error ? app.folder.error
                : app.folder.unreadable ? "Some folders here need the system password to read; they are not counted." : ""
              visible: text !== ""
            }
            Repeater {
              model: app.folder && app.folder.items ? app.folder.items.slice(0, 60) : []
              delegate: Item {
                required property var modelData
                required property int index
                width: body.width; height: 52
                Rectangle { visible: index > 0; width: parent.width; height: 1; color: app.line }
                Label {
                  y: 9; width: parent.width - 110; elide: Text.ElideMiddle
                  text: modelData.name + (modelData.dir ? "/" : "")
                  color: modelData.dir ? app.fg : app.soft
                }
                Dim {
                  y: 31; text: modelData.other_drive ? "on another drive" : ""
                  visible: text !== ""
                }
                Rectangle {
                  y: 34; width: parent.width - 110; height: 3; radius: 2; color: app.raised
                  visible: !modelData.other_drive
                  Rectangle { height: parent.height; radius: 2; color: app.cSystem; width: parent.width * app.pct(modelData.bytes, app.folder.total) }
                }
                Label { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: app.fmt(modelData.bytes); font.bold: true; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; enabled: modelData.dir && !modelData.other_drive; onClicked: app.openFolder(modelData.path) }
              }
            }
          }

          // ---------------------------------------------------- overview
          Repeater {
            model: app.folderStack.length === 0 && app.tab === "overview" ? app.drives : []
            delegate: Rectangle {
              id: driveCard
              required property var modelData
              readonly property var parts: modelData.mount === "/" ? app.internalParts : app.partsOf(modelData)
              width: body.width
              height: cardCol.height + 30
              radius: 12; color: app.card; border.width: 1; border.color: app.line
              Column {
                id: cardCol
                x: 16; y: 16; width: parent.width - 32
                Item {
                  width: parent.width; height: 38
                  Label { text: driveCard.modelData.name; font.pixelSize: 15; font.bold: true }
                  Dim {
                    y: 21; font.pixelSize: 11
                    text: (driveCard.modelData.kind === "emmc" ? "eMMC" : driveCard.modelData.disk) + " · " + driveCard.modelData.fstype
                      + " · " + (driveCard.modelData.mount === "/" ? "system drive" : driveCard.modelData.mount)
                  }
                  Dim { anchors.right: parent.right; text: Math.round(100 * app.pct(driveCard.modelData.used, driveCard.modelData.size)) + "%"; font.pixelSize: 13 }
                  MouseArea { anchors.fill: parent; onClicked: app.openFolder(driveCard.modelData.mount) }
                }
                Item { width: 1; height: 12 }
                Row {
                  spacing: 8
                  Label { id: usedBig; text: app.fmt(driveCard.modelData.used); font.pixelSize: 30; font.bold: true }
                  Dim { anchors.baseline: usedBig.baseline; text: "of " + app.fmt(driveCard.modelData.size) + " used"; font.pixelSize: 14 }
                }
                Label { text: app.fmt(driveCard.modelData.free) + " free"; color: app.cFiles; font.pixelSize: 13 }
                Item { width: 1; height: 14 }
                StackBar {
                  parts: driveCard.parts.length ? driveCard.parts : [{ bytes: driveCard.modelData.used, color: app.soft }]
                  whole: driveCard.modelData.size
                }
                Item { width: 1; height: 10 }
                Dim { visible: driveCard.parts.length === 0; text: "measuring…"; topPadding: 4 }
                Repeater {
                  model: driveCard.parts
                  delegate: LegendRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    label: modelData.label; badge: modelData.badge || ""
                    bytes: modelData.bytes; dot: modelData.color
                    onTapped: app.openFolder(modelData.path)
                  }
                }
                Dim {
                  visible: driveCard.modelData.system_copy
                  width: parent.width; wrapMode: Text.Wrap; topPadding: 10; lineHeight: 1.3
                  text: "This card still holds the previous system, kept as the way back. Storage never cleans it."
                }
              }
            }
          }

          // ---------------------------------------------------- clean up
          Column {
            visible: app.folderStack.length === 0 && app.tab === "clean"
            width: parent.width
            spacing: 14
            Column {
              width: parent.width; topPadding: 10; bottomPadding: 10
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: app.cleanItems.length ? app.fmt(app.cleanTotal) : "…"
                color: app.fg; font.family: app.mono; font.pixelSize: 40; font.bold: true
              }
              Dim {
                anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 13
                text: app.message !== "" && app.tab === "clean" ? app.message
                  : app.cleanExact ? "can be freed safely" : "up to this much can be freed safely"
              }
            }
            Rectangle {
              width: parent.width; height: cleanCol.height + 8
              radius: 12; color: app.card; border.width: 1; border.color: app.line
              Column {
                id: cleanCol
                x: 16; y: 4; width: parent.width - 32
                Repeater {
                  model: app.cleanItems
                  delegate: Item {
                    id: ci
                    required property var modelData
                    required property int index
                    readonly property bool empty: modelData.bytes <= 0
                    readonly property bool on: !empty && !!app.selected[modelData.key]
                    width: cleanCol.width
                    height: ciCol.height + 28
                    Rectangle { visible: ci.index > 0; width: parent.width; height: 1; color: app.line }
                    Rectangle {
                      y: 15; width: 22; height: 22; radius: 6
                      color: ci.on ? app.fg : "transparent"
                      border.width: ci.on ? 0 : 1.5; border.color: app.dim
                      opacity: ci.empty ? 0.35 : 1
                      Text { anchors.centerIn: parent; visible: ci.on; text: "✓"; color: app.bg; font.pixelSize: 14; font.bold: true }
                    }
                    Column {
                      id: ciCol
                      x: 36; y: 14; width: parent.width - 36; spacing: 5
                      Item {
                        width: parent.width; height: 20
                        Label { text: ci.modelData.label; font.pixelSize: 15; color: ci.empty ? app.dim : app.fg }
                        Label {
                          anchors.right: parent.right; font.bold: true; color: ci.empty ? app.dim : app.fg
                          text: ci.empty ? "empty" : (ci.modelData.exact ? "" : "up to ") + app.fmt(ci.modelData.bytes)
                        }
                      }
                      Dim { visible: !ci.empty; width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 11; lineHeight: 1.25; text: ci.modelData.detail }
                      Rectangle {
                        visible: ci.modelData.root && !ci.empty
                        width: needText.implicitWidth + 12; height: 18; radius: 4; color: "transparent"; border.width: 1; border.color: app.line
                        Text { id: needText; anchors.centerIn: parent; text: "needs password"; color: app.soft; font.family: app.mono; font.pixelSize: 10 }
                      }
                    }
                    MouseArea {
                      anchors.fill: parent; enabled: !ci.empty
                      onClicked: { var s = Object.assign({}, app.selected); s[ci.modelData.key] = !s[ci.modelData.key]; app.selected = s }
                    }
                  }
                }
              }
            }
            Button {
              width: parent.width
              label: app.busy === "clean-up" ? "cleaning…" : "Clean up selected"
              enabled: app.busy === "" && app.cleanTotal > 0
              onTapped: app.cleanUp()
            }
            Dim {
              width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; font.pixelSize: 11
              text: "Nothing in your files or the backup on the card is touched."
            }
          }

          // ---------------------------------------------------- apps
          Column {
            visible: app.folderStack.length === 0 && app.tab === "apps"
            width: parent.width
            Item {
              width: parent.width; height: 26
              Dim { text: "sorted by size" }
              Dim {
                anchors.right: parent.right
                text: app.message !== "" && app.tab === "apps" ? app.message : "tap remove to uninstall"
              }
            }
            Dim { visible: app.apps.length === 0; text: "reading apps…"; topPadding: 10 }
            Repeater {
              model: app.apps
              delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: body.width; height: 58
                Rectangle { visible: row.index > 0; width: parent.width; height: 1; color: app.line }
                Rectangle {
                  id: iconBox
                  anchors.verticalCenter: parent.verticalCenter
                  width: 34; height: 34; radius: 9; color: app.raised
                  Image {
                    id: icon
                    anchors.centerIn: parent; width: 26; height: 26
                    sourceSize.width: 52; sourceSize.height: 52
                    source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.centerIn: parent; visible: icon.status !== Image.Ready
                    text: row.modelData.name.slice(0, 2)
                    color: app.soft; font.family: app.mono; font.pixelSize: 13; font.bold: true
                  }
                }
                Column {
                  x: 48; anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 48 - 170
                  Label { width: parent.width; elide: Text.ElideRight; text: row.modelData.name }
                  Dim { width: parent.width; elide: Text.ElideRight; font.pixelSize: 11; text: row.modelData.locked || row.modelData.pkg }
                }
                Rectangle {
                  anchors.right: sizeText.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                  width: 44; height: 4; radius: 2; color: app.raised
                  Rectangle { height: parent.height; radius: 2; color: app.cSystem; width: Math.max(2, parent.width * app.pct(row.modelData.bytes, app.appsMax)) }
                }
                Label {
                  id: sizeText
                  anchors.right: action.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                  text: app.fmt(row.modelData.bytes); font.bold: true; font.pixelSize: 14
                }
                Text {
                  id: action
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  width: 54; horizontalAlignment: Text.AlignRight
                  text: row.modelData.locked ? "system" : "remove"
                  color: row.modelData.locked ? app.dim : app.cRed
                  font.family: app.mono; font.pixelSize: row.modelData.locked ? 11 : 12
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: !row.modelData.locked && app.busy === ""
                  onClicked: { app.deleteData = false; app.sheetApp = row.modelData }
                }
              }
            }
          }
        }
      }
    }

    // ---------------------------------------------------- uninstall sheet
    Rectangle {
      anchors.fill: parent
      visible: app.sheetApp !== null
      color: Qt.rgba(0.02, 0.02, 0.04, 0.6)
      MouseArea { anchors.fill: parent; onClicked: app.sheetApp = null }
    }
    Rectangle {
      id: sheet
      visible: app.sheetApp !== null
      anchors.bottom: parent.bottom
      width: parent.width
      height: sheetCol.height + 40
      radius: 22
      color: app.card
      border.width: 1; border.color: app.line
      MouseArea { anchors.fill: parent }       // keeps taps off the scrim
      readonly property real dataBytes: {
        var t = 0
        if (app.sheetApp) for (var i = 0; i < app.sheetApp.data.length; i++) t += app.sheetApp.data[i].bytes
        return t
      }
      Column {
        id: sheetCol
        x: app.side + 2; y: 14; width: parent.width - 2 * (app.side + 2)
        spacing: 0
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 42; height: 4; radius: 2; color: app.dim; opacity: 0.5 }
        Item { width: 1; height: 18 }
        Label { text: app.sheetApp ? "Uninstall " + app.sheetApp.name + "?" : ""; font.pixelSize: 18; font.bold: true; width: parent.width; elide: Text.ElideRight }
        Dim {
          width: parent.width; wrapMode: Text.Wrap; topPadding: 6; bottomPadding: 14; font.pixelSize: 12; lineHeight: 1.3
          text: "Removes the app and the packages only it uses. Other apps keep working."
        }
        Repeater {
          model: app.sheetApp ? [["Frees", app.fmt(app.sheetApp.bytes)], ["Package", app.sheetApp.pkg + " " + app.sheetApp.version]] : []
          delegate: Item {
            required property var modelData
            width: sheetCol.width; height: 42
            Rectangle { width: parent.width; height: 1; color: app.line }
            Label { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.pixelSize: 14 }
            Label { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: app.soft; font.pixelSize: 14 }
          }
        }
        // Its own folders, shown before they can go.
        Item {
          visible: !!app.sheetApp && app.sheetApp.data.length > 0
          width: parent.width; height: 42
          Rectangle { width: parent.width; height: 1; color: app.line }
          Label { anchors.verticalCenter: parent.verticalCenter; text: "Also delete its data · " + app.fmt(sheet.dataBytes); font.pixelSize: 14 }
          Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 24; radius: 12
            color: app.deleteData ? app.cRed : app.raised; border.width: 1; border.color: app.line
            Rectangle { x: app.deleteData ? parent.width - width - 3 : 3; y: 3; width: 18; height: 18; radius: 9; color: app.deleteData ? app.bg : app.dim }
          }
          MouseArea { anchors.fill: parent; onClicked: app.deleteData = !app.deleteData }
        }
        Repeater {
          model: app.sheetApp && app.deleteData ? app.sheetApp.data : []
          delegate: Dim {
            required property var modelData
            width: sheetCol.width; elide: Text.ElideMiddle; font.pixelSize: 11; bottomPadding: 4
            text: app.shortPath(modelData.path) + "  " + app.fmt(modelData.bytes)
          }
        }
        Item { width: 1; height: 16 }
        Row {
          width: parent.width; spacing: 10
          Button { width: (parent.width - 10) / 2; kind: "ghost"; label: "Cancel"; onTapped: app.sheetApp = null }
          Button { width: (parent.width - 10) / 2; kind: "danger"; label: "Uninstall"; onTapped: app.uninstall() }
        }
        Dim {
          width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 12; font.pixelSize: 11
          text: "Needs your password · reinstall any time with pacman"
        }
      }
    }
  }

  function shortPath(p) { return p && p.indexOf(home) === 0 ? "~" + p.slice(home.length) : p }
}
