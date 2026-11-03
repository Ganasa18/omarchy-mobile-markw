// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io

// Flash: a PlatformIO front end in an ordinary window, so it tiles beside a
// terminal. Pick a project (or browse to any folder; an Arduino IDE sketch
// gets a platformio.ini), an env and a port; build, upload, watch the
// serial port or clean. Everything runs "pio" or omamobile-flash (the
// helper beside it). Drawn in the Omarchy theme's text colour only
// (docs/design/dev-tools): the chosen action is inverted, outer corners are
// 8 px and inner ones 4 px.
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
  readonly property color fg: themeColor("foreground", "#e8ebf1")
  readonly property color dim: themeColor("dark_foreground", "#8a909b")
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property string mono: "JetBrainsMono Nerd Font"
  readonly property int touch: 48
  readonly property int side: 20
  readonly property int gap: 4

  // ------------------------------------------------------------ state
  property var projects: []           // [{path, kind: pio | ino}]
  property string project: ""
  property var envs: []
  property string env: ""
  property int speed: 115200
  property var ports: []
  property string port: ""
  property string action: ""          // build | upload | clean while pio runs
  property bool monitoring: false
  property int progress: -1
  property string ram: ""
  property string flash: ""
  property string result: ""
  property string tab: "output"
  property string picking: ""         // project | env | port | browse | sketch | board while the sheet is up
  property string browseDir: ""
  property string browseKind: ""      // the browsed folder's own mark: pio, ino or ""
  property var browseDirs: []
  property string sketchDir: ""       // an Arduino sketch waiting for its platformio.ini
  property string sketchIno: ""
  property string board: ""
  property int sketchSpeed: 115200
  readonly property var boards: ["esp32dev", "nodemcu-32s", "esp32-s3-devkitc-1", "esp32-c3-devkitm-1", "nodemcuv2", "d1_mini"]
  property string pioPath: ""         // from "omamobile-flash status"; "" = not installed
  property string pioVersion: ""
  property bool pioKnown: false

  readonly property string projectName: project ? project.replace(/\/+$/, "").split("/").pop() : ""
  readonly property string shortProject: shortPath(project)
  function shortPath(dir) { return dir.indexOf(home) === 0 ? "~" + dir.slice(home.length) : dir }
  readonly property string portName: {
    for (var i = 0; i < ports.length; i++) if (ports[i].path === port) return ports[i].name
    return ""
  }

  // Lines wait here and reach the log five times a second, appended to the
  // model rather than replacing it. A board in a reset loop prints hundreds
  // of lines a second; rebuilding the whole list for each one kept the UI
  // thread busy until Hyprland called the window unresponsive.
  property var pendingOutput: []
  property var pendingSerial: []
  ListModel { id: outputModel }
  ListModel { id: serialModel }
  function append(which, text) {
    var pending = which === "serial" ? pendingSerial : pendingOutput
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) pending.push(lines[i].length > 400 ? lines[i].slice(0, 400) + "…" : lines[i])
    if (pending.length > 500) pending.splice(0, pending.length - 500)
  }
  function flush(model, lines) {
    for (var i = 0; i < lines.length; i++) model.append({ line: lines[i] })
    if (model.count > 1000) model.remove(0, model.count - 1000)
  }
  function clearLog(which, first) {
    var model = which === "serial" ? serialModel : outputModel
    model.clear()
    if (which === "serial") pendingSerial = first ? [first] : []
    else pendingOutput = first ? [first] : []
  }
  Timer {
    interval: 200; repeat: true; running: true
    onTriggered: {
      if (app.pendingOutput.length) { app.flush(outputModel, app.pendingOutput); app.pendingOutput = [] }
      if (app.pendingSerial.length) { app.flush(serialModel, app.pendingSerial); app.pendingSerial = [] }
    }
  }

  // ------------------------------------------------------------ helper calls
  // One process per kind of question, so an answer can't reach the wrong
  // handler; a question asked while its kind runs is asked again after.
  component Asker: Process {
    id: asker
    workingDirectory: app.home
    property string kind: ""
    property var pending: null
    function ask(args) {
      if (running) { pending = args; return }
      command = ["omamobile-flash"].concat(args)
      running = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: app.answer(asker.kind, text)
    }
    onExited: if (pending) { var again = pending; pending = null; ask(again) }
  }
  Asker { id: askStatus; kind: "status" }
  Asker { id: askProjects; kind: "projects" }
  Asker { id: askEnvs; kind: "envs" }
  Asker { id: askPorts; kind: "ports" }
  Asker { id: askExample; kind: "example" }
  Asker { id: askDirs; kind: "dirs" }
  Asker { id: askSketch; kind: "sketch" }
  Asker { id: askInit; kind: "init" }
  function ask(args, handler) {
    ({ status: askStatus, projects: askProjects, envs: askEnvs, ports: askPorts, example: askExample,
       dirs: askDirs, sketch: askSketch, init: askInit })[handler].ask(args)
  }
  function answer(handler, text) {
    var data = null
    if (handler !== "example" && handler !== "init") { try { data = JSON.parse(text) } catch (error) { return } }
    if (handler === "projects") {
      projects = data
      if (!project) for (var k = 0; k < data.length; k++) if (data[k].kind === "pio") { setProject(data[k].path); break }
    } else if (handler === "envs") {
      envs = data
      var keep = false
      for (var i = 0; i < data.length; i++) if (data[i].name === env) { keep = true; speed = data[i].speed }
      if (!keep && data.length) { env = data[0].name; speed = data[0].speed }
    } else if (handler === "ports") {
      ports = data
      var still = false
      for (var j = 0; j < data.length; j++) if (data[j].path === port) still = true
      if (!still) port = data.length ? data[0].path : ""
    } else if (handler === "status") {
      pioPath = data.pio; pioVersion = data.version; pioKnown = true
    } else if (handler === "dirs") {
      browseKind = data.kind; browseDirs = data.dirs
    } else if (handler === "sketch") {
      sketchIno = data.ino; board = data.board; sketchSpeed = data.speed
      picking = "sketch"
    } else if (handler === "example" || handler === "init") {
      if (!text.trim()) { result = handler === "init" ? "could not write platformio.ini" : "could not copy the example"; picking = ""; return }
      setProject(text.trim())
      picking = ""
      ask(["projects"], "projects")
    }
  }
  // The project list is scanned again each time it opens.
  function openProjects() { picking = "project"; ask(["projects"], "projects") }
  function browse(dir) {
    browseDir = dir; browseKind = ""; browseDirs = []
    picking = "browse"
    ask(["dirs", dir], "dirs")
  }
  // A PlatformIO folder becomes the project; a sketch first gets its
  // platformio.ini from the sketch sheet.
  function choose(dir, kind) {
    if (kind === "pio") { setProject(dir); picking = "" }
    else if (kind === "ino") { sketchDir = dir; ask(["sketch", dir], "sketch") }
  }
  function setProject(dir) {
    project = dir
    env = ""; envs = []; ram = ""; flash = ""; result = ""
    ask(["envs", dir], "envs")
  }

  Component.onCompleted: { ask(["status"], "status"); ask(["projects"], "projects"); ask(["ports"], "ports") }

  // The adapter comes and goes with the OTG cable.
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: if (!askPorts.running) app.ask(["ports"], "ports")
  }

  // ------------------------------------------------------------ pio
  function start(what, cmd) {
    action = what; progress = what === "upload" ? 0 : -1; result = ""; tab = "output"
    clearLog("output", "$ " + cmd.join(" "))
    pio.command = cmd
    pio.running = true
  }
  // PlatformIO into ~/.platformio, once, with its output in the log.
  function setup() { if (action === "") start("setup", ["omamobile-flash", "setup"]) }
  function run(what) {
    if (action !== "" || !project || !env) return
    if (!pioPath) { result = "install PlatformIO first"; return }
    if (what === "upload" && !port) { result = "no port: plug the board in"; return }
    if (what === "upload" && monitoring) stopMonitor()
    var cmd = [pioPath, "run", "-d", project, "-e", env]
    if (what === "upload") cmd = cmd.concat(["-t", "upload", "--upload-port", port])
    if (what === "clean") cmd = cmd.concat(["-t", "clean"])
    start(what, cmd)
  }
  function cancel() { pio.running = false }
  function parse(text) {
    var m = /\((\d+) ?%\)/.exec(text)
    if (m && action === "upload") progress = parseInt(m[1], 10)
    var u = /^(RAM|Flash):\s+\[.*\]\s+([\d.]+)%/.exec(text)
    if (u) { if (u[1] === "RAM") ram = u[2]; else flash = u[2] }
  }
  Process {
    id: pio
    workingDirectory: app.home
    stdout: SplitParser { onRead: data => { app.parse(data); app.append("output", data) } }
    stderr: SplitParser { onRead: data => { app.parse(data); app.append("output", data) } }
    onExited: (code, status) => {
      app.result = app.action + (code === 0 ? " done" : " failed (" + code + ")")
      if (code === 0 && app.action === "upload") app.progress = 100
      var after = app.action
      app.action = ""
      if (after === "setup") app.ask(["status"], "status")
      // After an upload the board restarts: show what it prints.
      if (code === 0 && after === "upload") app.startMonitor()
    }
  }

  function startMonitor() {
    if (!port || monitoring) return
    clearLog("serial", "")
    tab = "serial"
    monitor.command = ["omamobile-flash", "monitor", port, String(speed)]
    monitor.running = true
    monitoring = true
  }
  function stopMonitor() { monitor.running = false; monitoring = false }
  Process {
    id: monitor
    workingDirectory: app.home
    stdout: SplitParser { onRead: data => app.append("serial", data) }
    stderr: SplitParser { onRead: data => app.append("serial", data) }
    onExited: app.monitoring = false
  }

  // A label on the left, the value dimmed on the right, a hairline below.
  component Field: Item {
    id: field
    property string label: ""
    property string value: ""
    signal tapped()
    width: parent ? parent.width : 0
    height: app.touch
    Text {
      anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
      text: field.label; color: app.fg; font.family: app.mono; font.pixelSize: 15
    }
    Text {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.65)
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      text: field.value; color: app.dim; font.family: app.mono; font.pixelSize: 15
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: app.line }
    MouseArea { anchors.fill: parent; onClicked: field.tapped() }
  }

  // A full-width button: inverted for the sheet's action, an outline otherwise.
  component Button: Rectangle {
    id: button
    property string label: ""
    property bool primary: true
    signal tapped()
    width: parent ? parent.width : 0
    height: app.touch
    radius: 8
    color: button.primary ? (buttonTouch.pressed ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.85) : app.fg)
      : buttonTouch.pressed ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.08) : "transparent"
    border.width: button.primary ? 0 : 1
    border.color: app.line
    Text {
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - 24)
      elide: Text.ElideLeft
      text: button.label; color: button.primary ? app.bg : app.fg
      font.family: app.mono; font.pixelSize: 15; font.bold: button.primary
    }
    MouseArea { id: buttonTouch; anchors.fill: parent; onClicked: button.tapped() }
  }

  // A small dimmed heading above a list.
  component Heading: Text {
    width: parent ? parent.width : 0
    height: 28
    verticalAlignment: Text.AlignBottom
    bottomPadding: 6
    color: app.dim; font.family: app.mono; font.pixelSize: 12
  }

  // ------------------------------------------------------------ window
  FloatingWindow {
    id: win
    title: "Flash"
    implicitWidth: 480
    implicitHeight: 1000
    color: app.bg

    Column {
      id: page
      x: app.side
      width: parent.width - app.side * 2
      y: 12

      Item {
        width: parent.width; height: 56
        Text { anchors.verticalCenter: parent.verticalCenter; text: "flash"; color: app.fg; font.family: app.mono; font.pixelSize: 19; font.bold: true }
        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: app.projectName; color: app.dim; font.family: app.mono; font.pixelSize: 15 }
      }

      Rectangle { width: parent.width; height: 1; color: app.line }
      Field {
        label: "Project"
        value: app.project ? app.shortProject : "choose"
        onTapped: app.openProjects()
      }
      Field { label: "Env"; value: app.env || "none"; onTapped: if (app.envs.length) app.picking = "env" }
      Field {
        label: "Port"
        value: app.port ? app.port.replace(/^\/dev\//, "") + (app.portName ? " · " + app.portName : "") : "no board"
        onTapped: if (app.ports.length) app.picking = "port"
      }
      // Shown until PlatformIO is installed (or while it installs).
      Field {
        visible: app.pioKnown && !app.pioPath || app.action === "setup"
        label: "PlatformIO"
        value: app.action === "setup" ? "installing…" : "not installed: tap to install"
        onTapped: app.setup()
      }

      Item { width: 1; height: 24 }

      // Actions: one outline, the running one inverted.
      Rectangle {
        width: parent.width; height: app.touch + app.gap * 2
        radius: 8; color: "transparent"; border.width: 1; border.color: app.line
        Row {
          anchors.fill: parent; anchors.margins: app.gap; spacing: app.gap
          Repeater {
            model: ["build", "upload", "monitor", "clean"]
            delegate: Rectangle {
              id: act
              required property string modelData
              readonly property bool on: app.action === act.modelData || (act.modelData === "monitor" && app.monitoring)
              readonly property bool usable: act.modelData === "monitor" ? !!app.port : (app.action === "" && !!app.env)
              width: (parent.width - app.gap * 3) / 4; height: parent.height
              radius: 4
              color: act.on ? app.fg : actTouch.pressed ? Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.08) : "transparent"
              Text {
                anchors.centerIn: parent
                text: act.modelData
                color: act.on ? app.bg : act.usable ? app.fg : app.dim
                font.family: app.mono; font.pixelSize: 15; font.bold: true
              }
              MouseArea {
                id: actTouch; anchors.fill: parent
                onClicked: {
                  if (act.modelData === "monitor") { if (app.monitoring) app.stopMonitor(); else app.startMonitor() }
                  else if (act.usable) app.run(act.modelData)
                }
              }
            }
          }
        }
      }

      Item { width: 1; height: 16 }

      // Progress or the last result; cancel while pio runs.
      Item {
        width: parent.width; height: 20
        Text {
          text: app.action !== "" ? app.action + (app.progress >= 0 ? " " + app.progress + "%" : "…") : app.result
          color: app.fg; font.family: app.mono; font.pixelSize: 13
        }
        Text {
          visible: app.action !== ""
          anchors.right: parent.right
          text: "cancel"; color: app.dim; font.family: app.mono; font.pixelSize: 13
          MouseArea { anchors.fill: parent; anchors.margins: -14; onClicked: app.cancel() }
        }
      }
      Rectangle {
        width: parent.width; height: 4; radius: 2; color: app.line; clip: true
        Rectangle { height: parent.height; radius: 2; color: app.fg; width: parent.width * Math.max(0, app.progress) / 100; visible: app.progress >= 0 }
        // Build, clean and setup print no percentage: a segment sweeps
        // while pio works, so the window doesn't look stuck.
        Rectangle {
          id: sweep
          readonly property bool busy: app.action !== "" && app.progress < 0
          visible: busy
          width: parent.width / 4; height: parent.height; radius: 2; color: app.fg
          SequentialAnimation on x {
            running: sweep.busy
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: sweep.parent.width - sweep.width; duration: 900; easing.type: Easing.InOutQuad }
            NumberAnimation { from: sweep.parent.width - sweep.width; to: 0; duration: 900; easing.type: Easing.InOutQuad }
          }
        }
      }

      Item { width: 1; height: 20 }

      Item {
        width: parent.width; height: 28
        Row {
          spacing: 18
          Repeater {
            model: ["output", "serial"]
            delegate: Text {
              id: tabText
              required property string modelData
              text: tabText.modelData
              color: app.tab === tabText.modelData ? app.fg : app.dim
              font.family: app.mono; font.pixelSize: 13
              Rectangle { visible: app.tab === tabText.modelData; anchors.top: parent.bottom; width: parent.width; height: 1; color: app.fg }
              MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: app.tab = tabText.modelData }
            }
          }
        }
        Text {
          anchors.right: parent.right
          visible: app.ram !== "" || app.flash !== ""
          text: "ram " + (app.ram || "–") + "% · flash " + (app.flash || "–") + "%"
          color: app.dim; font.family: app.mono; font.pixelSize: 13
        }
      }
    }

    Rectangle {
      x: app.side
      anchors.top: page.bottom; anchors.topMargin: 10
      anchors.bottom: parent.bottom; anchors.bottomMargin: 16
      width: parent.width - app.side * 2
      radius: 8; color: "transparent"; border.width: 1; border.color: app.line

      ListView {
        id: log
        anchors.fill: parent; anchors.margins: 12
        clip: true
        model: app.tab === "serial" ? serialModel : outputModel
        onCountChanged: positionViewAtEnd()
        delegate: Text {
          required property string line
          required property int index
          width: log.width
          wrapMode: Text.WrapAnywhere
          textFormat: Text.PlainText
          text: line
          color: index === 0 && app.tab === "output" ? app.dim : Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.8)
          font.family: app.mono; font.pixelSize: 12
        }
      }
    }

    // The sheet over everything: a field's choices, the project list, the
    // folder browser, and a sketch's platformio.ini.
    Rectangle {
      id: sheet
      anchors.fill: parent
      visible: app.picking !== ""
      color: app.bg
      MouseArea { anchors.fill: parent }
      readonly property var options: app.picking === "env" ? app.envs.map(e => e.name)
        : app.picking === "port" ? app.ports.map(p => p.path)
        : app.picking === "board" ? app.boards : []
      // Where the corner goes: the board list back to its sketch, the browser
      // and the sketch back to the project list; the rest closes.
      readonly property string back: app.picking === "board" ? "sketch"
        : app.picking === "browse" || app.picking === "sketch" ? "project" : ""
      readonly property bool atHome: app.browseDir.replace(/\/+$/, "") === app.home.replace(/\/+$/, "")

      Item {
        id: sheetHead
        x: app.side; y: 12; width: parent.width - app.side * 2; height: 56
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: ({ browse: "folder" })[app.picking] || app.picking
          color: app.fg; font.family: app.mono; font.pixelSize: 19; font.bold: true
        }
        Text {
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: sheet.back ? "back" : "close"; color: app.dim; font.family: app.mono; font.pixelSize: 15
          MouseArea {
            anchors.fill: parent; anchors.margins: -14
            onClicked: sheet.back === "project" ? app.openProjects() : app.picking = sheet.back
          }
        }
      }

      Flickable {
        x: app.side; width: parent.width - app.side * 2
        anchors.top: sheetHead.bottom; anchors.bottom: sheetFoot.top; anchors.bottomMargin: 12
        contentHeight: body.height
        clip: true
        Column {
          id: body
          width: parent.width

          // env, port, board: one row per choice
          Rectangle { visible: sheet.options.length > 0; width: parent.width; height: 1; color: app.line }
          Repeater {
            model: sheet.options
            delegate: Field {
              required property string modelData
              label: modelData
              value: (app.picking === "env" && modelData === app.env) || (app.picking === "port" && modelData === app.port)
                || (app.picking === "board" && modelData === app.board) ? "current" : ""
              onTapped: {
                if (app.picking === "board") { app.board = modelData; app.picking = "sketch"; return }
                if (app.picking === "env") {
                  app.env = modelData
                  for (var i = 0; i < app.envs.length; i++) if (app.envs[i].name === modelData) app.speed = app.envs[i].speed
                } else app.port = modelData
                app.picking = ""
              }
            }
          }

          // project: what the scan found, then any folder
          Heading { visible: app.picking === "project" && app.projects.length > 0; text: "recent" }
          Rectangle { visible: app.picking === "project" && app.projects.length > 0; width: parent.width; height: 1; color: app.line }
          Repeater {
            model: app.picking === "project" ? app.projects : []
            delegate: Field {
              required property var modelData
              label: app.shortPath(modelData.path)
              value: modelData.path === app.project ? "current" : modelData.kind
              onTapped: app.choose(modelData.path, modelData.kind)
            }
          }
          Item { visible: app.picking === "project"; width: 1; height: 24 }
          Rectangle { visible: app.picking === "project"; width: parent.width; height: 1; color: app.line }
          Field { visible: app.picking === "project"; label: "Browse folders…"; value: "›"; onTapped: app.browse(app.home) }
          Field {
            visible: app.picking === "project" && app.projects.length === 0
            label: "Copy the blink example"; value: "›"
            onTapped: app.ask(["example"], "example")
          }
          Text {
            visible: app.picking === "project"
            width: parent.width; topPadding: 12; wrapMode: Text.WordWrap
            text: "Folders under ~ with a platformio.ini (pio) or an Arduino sketch (ino), four levels deep."
            color: app.dim; font.family: app.mono; font.pixelSize: 12; lineHeight: 1.3
          }

          // browse: ~ and below, hidden folders left out
          Heading { visible: app.picking === "browse"; text: app.shortPath(app.browseDir) }
          Rectangle { visible: app.picking === "browse"; width: parent.width; height: 1; color: app.line }
          Field {
            visible: app.picking === "browse" && !sheet.atHome
            label: "‹ .."
            onTapped: app.browse(app.browseDir.replace(/\/+$/, "").replace(/\/[^\/]+$/, "") || "/")
          }
          Repeater {
            model: app.picking === "browse" ? app.browseDirs : []
            delegate: Field {
              required property var modelData
              label: modelData.name
              value: modelData.kind ? modelData.kind + " ›" : "›"
              onTapped: app.browse(app.browseDir.replace(/\/+$/, "") + "/" + modelData.name)
            }
          }

          // sketch: an Arduino IDE folder without platformio.ini
          Heading { visible: app.picking === "sketch"; text: "no platformio.ini yet" }
          Rectangle { visible: app.picking === "sketch"; width: parent.width; height: 1; color: app.line }
          Field { visible: app.picking === "sketch"; label: "Sketch"; value: app.sketchIno }
          Field { visible: app.picking === "sketch"; label: "Board"; value: app.board + " ›"; onTapped: app.picking = "board" }
          Field { visible: app.picking === "sketch"; label: "Speed"; value: String(app.sketchSpeed) }
          Text {
            visible: app.picking === "sketch"
            width: parent.width; topPadding: 12; wrapMode: Text.WordWrap
            text: "Flash writes a platformio.ini in " + app.shortPath(app.sketchDir)
              + " (src_dir = .). The sketch stays where it is, and the Arduino IDE still opens it."
            color: app.dim; font.family: app.mono; font.pixelSize: 12; lineHeight: 1.3
          }
        }
      }

      Column {
        id: sheetFoot
        x: app.side; width: parent.width - app.side * 2
        anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        spacing: 8
        Button {
          visible: app.picking === "browse"
          primary: app.browseKind !== ""
          label: app.browseKind === "" ? "no project here" : "choose " + app.shortPath(app.browseDir)
          onTapped: app.choose(app.browseDir, app.browseKind)
        }
        Button {
          visible: app.picking === "sketch"
          label: "create platformio.ini"
          onTapped: app.ask(["init", app.sketchDir, app.board, String(app.sketchSpeed)], "init")
        }
        Button { visible: app.picking === "sketch"; primary: false; label: "cancel"; onTapped: app.openProjects() }
      }
    }
  }
}
