// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The page behind the SSH Wi-Fi tile (omamobile-ssh-wifi): switch SSH on
// Wi-Fi on or off, pick when it turns itself off, and see the address, the
// ssh command to copy and the sessions in. Flat rows in the text colour only
// (docs/design/dev-tools): the selected choice is drawn inverted, not in the
// accent. Inner corners are the panel's radius minus the gap between them.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  readonly property color background: Commons.Color.popups.background
  // The last omamobile-ssh-wifi status --json; on, minutes, left, address, sessions.
  property var info: ({ on: false, minutes: null, left: null, address: "", sessions: [] })
  property bool ready: false
  // Minutes for the next "on"; follows the running instance.
  property int minutes: 30
  property string copied: ""

  signal backRequested()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Math.max(2, Style.space(4))
  readonly property int innerRadius: Math.max(0, Style.cornerRadius - gap)
  readonly property string user: Quickshell.env("USER") || "user"

  readonly property var choices: [
    { minutes: 15, label: "15 min" },
    { minutes: 30, label: "30 min" },
    { minutes: 60, label: "1 h" },
    { minutes: 0, label: "Until off" }
  ]

  function open() { opened = true; refresh() }
  function close() { opened = false }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  function run(args) {
    actionProc.command = ["omamobile-ssh-wifi"].concat(args)
    actionProc.running = true
  }

  function setOn(on) {
    if (actionProc.running) return
    root.info = Object.assign({}, root.info, { on: on })
    run(on ? ["on", String(root.minutes)] : ["off"])
  }

  function choose(m) {
    root.minutes = m
    if (root.info.on && root.info.minutes !== m) run(["on", String(m)])
  }

  function copy(text) {
    Quickshell.execDetached(["wl-copy", "--", text])
    root.copied = text
    copiedReset.restart()
  }

  readonly property string statusLine: {
    if (!ready) return ""
    if (!info.on) return "off"
    if (info.left === null || info.left === undefined) return "on until off"
    return "on · " + info.left + " min left"
  }

  Process {
    id: statusProc
    command: ["omamobile-ssh-wifi", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (error) { return }
        root.info = data
        root.ready = true
        if (data.on && typeof data.minutes === "number") root.minutes = data.minutes
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  // Minutes left and sessions change while the page is up.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copied = ""
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // A label on the left, a value or control on the right, a hairline below.
  component Line: Item {
    id: row
    property string label: ""
    property string value: ""
    property bool tappable: false
    default property alias control: slot.data
    signal tapped()
    width: parent ? parent.width : 0
    height: root.touchSize
    MouseArea { anchors.fill: parent; enabled: row.tappable; onClicked: row.tapped() }
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: row.value !== ""
      textFormat: Text.PlainText
      text: row.value
      color: root.foreground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: root.foreground
      opacity: 0.08
    }
  }

  component Heading: Text {
    width: parent ? parent.width : 0
    topPadding: root.pad
    bottomPadding: root.gap
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.small
  }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-ssh-wifi"
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
      Keys.onEscapePressed: root.close()

      MouseArea { anchors.fill: parent }

      Item {
        anchors.fill: parent
        anchors.topMargin: panel.contentTopInset
        anchors.rightMargin: panel.contentRightInset
        anchors.bottomMargin: panel.contentBottomInset
        anchors.leftMargin: panel.contentLeftInset

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
            anchors.right: headerState.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "SSH over Wi-Fi"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: headerState
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.statusLine
            color: root.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.small
          }
        }

        Flickable {
          anchors.top: header.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentHeight: content.height
          clip: true

          Column {
            id: content
            width: parent.width

            Line {
              label: "Allow on Wi-Fi"
              tappable: root.ready
              onTapped: root.setOn(!root.info.on)
              // A small switch: the track inverts when on.
              Rectangle {
                width: Style.space(40); height: Style.space(22)
                radius: Math.round(height * 0.27)
                color: root.info.on ? root.foreground : "transparent"
                border.width: 1
                border.color: root.foreground
                opacity: root.ready ? 1 : 0.4
                Rectangle {
                  readonly property int inset: Style.space(3)
                  width: parent.height - inset * 2; height: width
                  radius: Math.max(0, parent.radius - inset)
                  y: inset
                  x: root.info.on ? parent.width - width - inset : inset
                  color: root.info.on ? root.background : root.foreground
                  Behavior on x { NumberAnimation { duration: 120 } }
                }
              }
            }

            Heading { text: "turn off after" }

            // Segmented choice: an outer outline, the chosen segment filled.
            Rectangle {
              width: parent.width
              height: root.touchSize
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Grid {
                anchors.fill: parent
                anchors.margins: root.gap
                columns: root.choices.length
                spacing: root.gap
                Repeater {
                  model: root.choices
                  delegate: Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool chosen: root.minutes === seg.modelData.minutes
                    width: (parent.width - parent.spacing * (root.choices.length - 1)) / root.choices.length
                    height: parent.height
                    radius: root.innerRadius
                    color: seg.chosen ? root.foreground : segTouch.pressed
                      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: seg.modelData.label
                      color: seg.chosen ? root.background : root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.small
                    }
                    MouseArea { id: segTouch; anchors.fill: parent; onClicked: root.choose(seg.modelData.minutes) }
                  }
                }
              }
            }

            Heading { text: "copy a command" }

            Column {
              width: parent.width
              spacing: root.gap * 2
              Repeater {
                model: root.info.address ? [root.user, "root"] : []
                delegate: Rectangle {
                  id: cmd
                  required property string modelData
                  readonly property string line: "ssh " + cmd.modelData + "@" + root.info.address
                  width: parent.width
                  height: root.touchSize
                  radius: Style.cornerRadius
                  color: cmdTouch.pressed ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.lg
                    anchors.right: cmdHint.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: cmd.line
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    id: cmdHint
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.copied === cmd.line ? "copied" : "copy"
                    color: root.foreground
                    opacity: 0.6
                    font.family: Style.font.family
                    font.pixelSize: Style.font.small
                  }
                  MouseArea { id: cmdTouch; anchors.fill: parent; onClicked: root.copy(cmd.line) }
                }
              }
            }

            Text {
              visible: !root.info.address
              width: parent.width
              height: root.touchSize
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: root.ready ? "Not connected to Wi-Fi" : ""
              color: root.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Heading { text: "sessions" }

            Repeater {
              model: root.info.sessions || []
              delegate: Line { required property string modelData; label: modelData; value: "over Wi-Fi" }
            }

            Line {
              visible: !(root.info.sessions && root.info.sessions.length)
              label: "None"
            }

            Text {
              width: parent.width
              topPadding: root.pad
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Keys only, no passwords. The phone stays awake while a session is open; "
                + "without one it sleeps and can't be reached until the screen is on. "
                + "Turning this off ends the Wi-Fi sessions."
              color: root.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.small
            }
          }
        }

      }
    }
  }
}
