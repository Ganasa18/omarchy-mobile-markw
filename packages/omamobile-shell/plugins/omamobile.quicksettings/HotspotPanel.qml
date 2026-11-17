// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The page behind the Hotspot tile (omamobile-hotspot): switch the hotspot on
// or off, see and change its name and password, and a QR code another phone's
// camera joins with. Flat rows in the text colour only, as the SSH Wi-Fi page
// (docs/design/dev-tools); the switch is drawn inverted, not in the accent.
//
// Tap Name or Password for a sheet above the on-screen keyboard. Save sends
// the new value to `omamobile-hotspot set` on stdin, never in argv; a running
// hotspot restarts with it.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  readonly property color background: Commons.Color.popups.background
  // The last `omamobile-hotspot status --json`.
  property var info: ({ available: false, on: false, name: "", password: "", security: "WPA2", clients: null, qr: "" })
  property bool ready: false
  property bool busy: false
  property string error: ""

  // The sheet: "" | "name" | "password".
  property string sheet: ""
  property bool showPassword: true

  signal backRequested()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Math.max(2, Style.space(4))
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)

  function open() { opened = true; error = ""; refresh() }
  function close() { opened = false; cancelSheet() }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  // `shell call omamobile.quicksettings hotspotPanel`: never the password.
  function snapshot() {
    return JSON.stringify({ opened: opened, available: info.available, on: info.on, name: info.name,
                            clients: info.clients, hasQr: info.qr !== "", sheet: sheet, error: error })
  }

  function setOn(on) {
    if (busy || !info.available) return
    busy = true
    error = ""
    info = Object.assign({}, info, { on: on })
    switchProc.command = ["omamobile-hotspot", on ? "on" : "off"]
    switchProc.running = true
  }

  readonly property string statusLine: {
    if (!ready) return ""
    if (!info.available) return "No Wi-Fi radio"
    if (busy) return info.on ? "Starting…" : "Stopping…"
    if (!info.on) return "Off"
    if (info.clients === null || info.clients === undefined) return "On"
    return "On · " + (info.clients === 1 ? "1 device" : info.clients + " devices") + " connected"
  }

  // ---------------------------------------------------------------- editing

  function utf8Length(text) { return unescape(encodeURIComponent(text)).length }

  function problem(kind, text) {
    if (kind === "name") {
      if (text.trim() === "") return "Enter a name"
      if (utf8Length(text) > 32) return "At most 32 bytes"
      return ""
    }
    if (text.length < 8) return "At least 8 characters"
    if (text.length > 63) return "At most 63 characters"
    if (!/^[\x20-\x7e]*$/.test(text)) return "Letters, digits and symbols only"
    return ""
  }

  readonly property string fieldProblem: sheet ? problem(sheet, field.text) : ""
  readonly property bool fieldChanged: sheet !== "" && field.text !== (sheet === "name" ? info.name : info.password)

  function openSheet(kind) {
    if (busy || !info.available) return
    sheet = kind
    error = ""
    showPassword = true
    field.text = kind === "name" ? info.name : info.password
    Qt.callLater(function() { field.forceActiveFocus(); field.cursorPosition = field.text.length })
  }

  function cancelSheet() {
    sheet = ""
    field.text = ""
    if (opened) panel.forceActiveFocus()
  }

  function save() {
    if (!sheet || fieldProblem !== "" || !fieldChanged || saveProc.running) return
    var change = {}
    change[sheet] = field.text
    saveProc.payload = JSON.stringify(change)
    busy = true
    error = ""
    cancelSheet()
    saveProc.running = true
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: statusProc
    command: ["omamobile-hotspot", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (e) { return }
        if (!root.busy) root.info = data
        root.ready = true
      }
    }
  }

  Process {
    id: switchProc
    stderr: StdioCollector { id: switchErrors; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.error = switchErrors.text.trim() || "The hotspot didn't start"
      root.refresh()
    }
  }

  // The new value goes in on stdin, one JSON line, and is dropped after.
  Process {
    id: saveProc
    property string payload: ""
    command: ["omamobile-hotspot", "set"]
    stdinEnabled: true
    onStarted: { write(payload + "\n"); payload = "" }
    stderr: StdioCollector { id: saveErrors; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.error = saveErrors.text.trim() || "Not saved"
      root.refresh()
    }
  }

  // Devices come and go while the page is up.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.sheet === ""
    onTriggered: root.refresh()
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // A label on the left, a value on the right, a hairline below.
  component Line: Item {
    id: row
    property string label: ""
    property string value: ""
    property bool tappable: false
    property bool last: false
    default property alias control: slot.data
    signal tapped()
    width: parent ? parent.width : 0
    height: Math.max(root.touchSize, Style.space(56))
    Rectangle {
      anchors.fill: parent
      color: rowTouch.pressed ? root.hairline : "transparent"
    }
    MouseArea { id: rowTouch; anchors.fill: parent; enabled: row.tappable; onClicked: row.tapped() }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      // Next to the chevron on a tappable row, else at the edge: the hidden
      // chevron keeps its width, so nothing binds a width to implicitWidth.
      anchors.right: row.tappable ? chevron.left : parent.right
      anchors.rightMargin: row.tappable ? Style.spacing.md : root.pad
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, row.width * 0.6)
      horizontalAlignment: Text.AlignRight
      visible: row.value !== ""
      textFormat: Text.PlainText
      text: row.value
      color: root.dim
      elide: Text.ElideLeft
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      visible: row.tappable
      textFormat: Text.PlainText
      text: "󰅂"
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Item {
      id: slot
      anchors.right: parent.right
      anchors.rightMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
    Rectangle {
      visible: !row.last
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.pad
      height: 1
      color: root.hairline
    }
  }

  // A rounded group of lines, a shade off the page.
  component Group: Rectangle {
    default property alias rows: groupColumn.data
    width: parent ? parent.width : 0
    height: groupColumn.height
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    clip: true
    Column { id: groupColumn; width: parent.width }
  }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: fit between the status bar and the on-screen keyboard, so the
    // sheet stays above the keys.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-hotspot"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: panel

      x: Style.gapsOut
      width: parent.width - Style.gapsOut * 2
      height: parent.height - Style.gapsOut * 2
      y: Style.gapsOut + Math.round((1 - root.reveal) * Style.space(60))
      opacity: root.reveal
      color: root.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      focus: root.opened
      Keys.onEscapePressed: root.sheet ? root.cancelSheet() : root.close()

      MouseArea { anchors.fill: parent }

      Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: panel.contentTopInset
        anchors.rightMargin: panel.contentRightInset
        anchors.bottomMargin: panel.contentBottomInset
        anchors.leftMargin: panel.contentLeftInset

        // ---------- Header: back, title, the switch; the state under it
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          GlyphButton {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰁍"
            foreground: root.foreground
            onTapped: root.backRequested()
          }

          Text {
            anchors.left: back.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: toggle.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Hotspot"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          // The switch: the track inverts when on.
          Rectangle {
            id: toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44); height: Style.space(24)
            radius: height / 2
            color: root.info.on ? root.foreground : "transparent"
            border.width: 1
            border.color: root.foreground
            opacity: root.ready && root.info.available && !root.busy ? 1 : 0.4
            Rectangle {
              readonly property int inset: Style.space(3)
              width: parent.height - inset * 2; height: width
              radius: width / 2
              y: inset
              x: root.info.on ? parent.width - width - inset : inset
              color: root.info.on ? root.background : root.foreground
              Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(10)
              onClicked: root.setOn(!root.info.on)
            }
          }
        }

        Text {
          id: stateLine
          anchors.top: header.bottom
          anchors.left: parent.left
          anchors.leftMargin: back.width + Style.spacing.lg
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: root.error || root.statusLine
          color: root.error ? Commons.Color.urgent : root.dim
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Flickable {
          anchors.top: stateLine.bottom
          anchors.topMargin: root.pad * 1.5
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentHeight: content.height
          clip: true

          Column {
            id: content
            width: parent.width
            spacing: root.pad

            Group {
              Line {
                label: "Name"
                value: root.info.name
                tappable: root.ready && root.info.available
                onTapped: root.openSheet("name")
              }
              Line {
                label: "Password"
                value: root.info.password
                tappable: root.ready && root.info.available
                onTapped: root.openSheet("password")
              }
              Line { label: "Security"; value: root.info.security; last: true }
            }

            // Scan to join: the QR's own white with a quiet border, as cameras need.
            Group {
              visible: root.info.qr !== ""
              Item {
                width: parent.width
                height: qrBox.height + root.pad * 2
                Rectangle {
                  id: qrBox
                  x: root.pad; y: root.pad
                  width: Style.space(120); height: width
                  radius: Style.space(8)
                  color: "#ffffff"
                  Image {
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    source: root.info.qr ? "file://" + root.info.qr : ""
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                  }
                }
                Column {
                  anchors.left: qrBox.right
                  anchors.leftMargin: root.pad
                  anchors.right: parent.right
                  anchors.rightMargin: root.pad
                  anchors.verticalCenter: qrBox.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Scan to join"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Point another phone's camera here to connect without typing the password."
                    color: root.dim
                    wrapMode: Text.Wrap
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }

            Text {
              width: parent.width
              leftPadding: root.pad
              rightPadding: root.pad
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Shares mobile data. Wi-Fi turns off while the hotspot is on."
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---------- The edit sheet, above the keyboard
        Rectangle {
          anchors.fill: parent
          visible: root.sheet !== ""
          color: Commons.Color.menu.scrim
          MouseArea { anchors.fill: parent; onClicked: root.cancelSheet() }
        }

        BorderSurface {
          id: sheetCard
          visible: root.sheet !== ""
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: sheetContent.implicitHeight + sheetCard.contentTopInset + sheetCard.contentBottomInset
          color: root.background
          borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
          radius: Style.cornerRadius
          padding: root.pad

          MouseArea { anchors.fill: parent }

          Column {
            id: sheetContent
            anchors.fill: parent
            anchors.topMargin: sheetCard.contentTopInset
            anchors.rightMargin: sheetCard.contentRightInset
            anchors.bottomMargin: sheetCard.contentBottomInset
            anchors.leftMargin: sheetCard.contentLeftInset
            spacing: Style.spacing.xl

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.sheet === "name" ? "Name" : "Password"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item {
              width: parent.width
              height: root.touchSize

              TextField {
                id: field
                anchors.left: parent.left
                anchors.right: reveal.left
                anchors.rightMargin: Style.spacing.lg
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.title
                foreground: root.foreground
                password: root.sheet === "password" && !root.showPassword
                inputMethodHints: root.sheet === "password"
                  ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                  : Qt.ImhNoPredictiveText
                onAccepted: root.save()
                Keys.onEscapePressed: root.cancelSheet()
              }

              GlyphButton {
                id: reveal
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.sheet === "password" ? implicitWidth : 0
                visible: root.sheet === "password"
                glyph: root.showPassword ? "󰈉" : "󰈈"
                foreground: root.foreground
                onTapped: root.showPassword = !root.showPassword
              }
            }

            // The rule on the left, the count on the right.
            Item {
              width: parent.width
              height: hint.implicitHeight
              Text {
                id: hint
                anchors.left: parent.left
                anchors.right: count.left
                textFormat: Text.PlainText
                text: root.fieldProblem || (root.sheet === "password"
                  ? "Connected devices join again with the new password" : "Devices see this name")
                color: root.fieldProblem ? Commons.Color.urgent : root.dim
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                id: count
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: root.sheet === "password"
                  ? field.text.length + " / " + (field.text.length < 8 ? 8 : 63)
                  : root.utf8Length(field.text) + " / 32"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              width: parent.width
              height: root.touchSize
              spacing: Style.spacing.lg
              layoutDirection: Qt.RightToLeft

              SheetButton {
                width: (parent.width - parent.spacing) / 2
                label: "Save"
                primary: true
                enabled: root.fieldProblem === "" && root.fieldChanged
                onTapped: root.save()
              }

              SheetButton {
                width: (parent.width - parent.spacing) / 2
                label: "Cancel"
                onTapped: root.cancelSheet()
              }
            }
          }
        }
      }
    }
  }
}
