// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io

// Flash: a PlatformIO front end in an ordinary window, so it tiles beside a
// terminal. Pick a project, an env and a port; build, upload, watch the
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
  property var projects: []
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
  property var outputLines: []
  property var serialLines: []
  property string picking: ""         // project | env | port while the list is up
  property string pioPath: ""         // from "omamobile-flash status"; "" = not installed
  property string pioVersion: ""
  property bool pioKnown: false

  readonly property string projectName: project ? project.replace(/\/+$/, "").split("/").pop() : ""
  readonly property string shortProject: project.indexOf(home) === 0 ? "~" + project.slice(home.length) : project
  readonly property string portName: {
    for (var i = 0; i < ports.length; i++) if (ports[i].path === port) return ports[i].name
    return ""
  }

  function append(which, text) {
    var list = (which === "serial" ? serialLines : outputLines).concat(String(text).split("\n"))
    if (list.length > 1000) list = list.slice(list.length - 1000)
    if (which === "serial") serialLines = list; else outputLines = list
  }

  // ------------------------------------------------------------ helper calls
  // One helper call at a time; each answer goes to its handler by name.
  property var queue: []
  function ask(args, handler) {
    queue = queue.concat([[args, handler]])
    if (!helper.running) nextAsk()
  }
  function nextAsk() {
    if (queue.length === 0) return
    helper.handler = queue[0][1]
    helper.command = ["omamobile-flash"].concat(queue[0][0])
    queue = queue.slice(1)
    helper.running = true
  }
  Process {
    id: helper
    property string handler: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: app.answer(helper.handler, text)
    }
    onExited: app.nextAsk()
  }
  function answer(handler, text) {
    var data = null
    if (handler !== "example") { try { data = JSON.parse(text) } catch (error) { return } }
    if (handler === "projects") {
      projects = data
      if (!project && data.length) setProject(data[0])
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
    } else if (handler === "example") {
      setProject(text.trim())
      ask(["projects"], "projects")
    }
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
    onTriggered: if (!helper.running) app.ask(["ports"], "ports")
  }

  // ------------------------------------------------------------ pio
  function start(what, cmd) {
    action = what; progress = what === "upload" ? 0 : -1; result = ""; tab = "output"
    outputLines = ["$ " + cmd.join(" ")]
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
    serialLines = []
    tab = "serial"
    monitor.command = ["omamobile-flash", "monitor", port, String(speed)]
    monitor.running = true
    monitoring = true
  }
  function stopMonitor() { monitor.running = false; monitoring = false }
  Process {
    id: monitor
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
        value: app.project ? app.shortProject : (app.projects.length ? "choose" : "none: tap for an example")
        onTapped: app.projects.length ? app.picking = "project" : app.ask(["example"], "example")
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
        model: app.tab === "serial" ? app.serialLines : app.outputLines
        onCountChanged: positionViewAtEnd()
        delegate: Text {
          required property string modelData
          required property int index
          width: log.width
          wrapMode: Text.WrapAnywhere
          textFormat: Text.PlainText
          text: modelData
          color: index === 0 && app.tab === "output" ? app.dim : Qt.rgba(app.fg.r, app.fg.g, app.fg.b, 0.8)
          font.family: app.mono; font.pixelSize: 12
        }
      }
    }

    // The choice list for a field, over everything.
    Rectangle {
      anchors.fill: parent
      visible: app.picking !== ""
      color: app.bg
      MouseArea { anchors.fill: parent }
      readonly property var options: app.picking === "project" ? app.projects
        : app.picking === "env" ? app.envs.map(e => e.name)
        : app.picking === "port" ? app.ports.map(p => p.path) : []
      Column {
        x: app.side; y: 12; width: parent.width - app.side * 2
        Item {
          width: parent.width; height: 56
          Text { anchors.verticalCenter: parent.verticalCenter; text: app.picking; color: app.fg; font.family: app.mono; font.pixelSize: 19; font.bold: true }
          Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "close"; color: app.dim; font.family: app.mono; font.pixelSize: 15
            MouseArea { anchors.fill: parent; anchors.margins: -14; onClicked: app.picking = "" }
          }
        }
        Rectangle { width: parent.width; height: 1; color: app.line }
        Repeater {
          model: parent.parent.options
          delegate: Field {
            required property string modelData
            label: app.picking === "project" && modelData.indexOf(app.home) === 0 ? "~" + modelData.slice(app.home.length) : modelData
            value: (app.picking === "project" && modelData === app.project) || (app.picking === "env" && modelData === app.env)
              || (app.picking === "port" && modelData === app.port) ? "current" : ""
            onTapped: {
              if (app.picking === "project") app.setProject(modelData)
              else if (app.picking === "env") {
                app.env = modelData
                for (var i = 0; i < app.envs.length; i++) if (app.envs[i].name === modelData) app.speed = app.envs[i].speed
              } else app.port = modelData
              app.picking = ""
            }
          }
        }
      }
    }
  }
}
