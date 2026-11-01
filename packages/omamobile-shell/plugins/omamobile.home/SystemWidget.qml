// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel

// This phone: the OS, the device, its chip, kernel and boot path, and the battery. The level and
// state are UPower's (live, no polling); the rest is one short shell read
// (HomeModel.SYSTEM_COMMAND) when the widget appears and every five minutes
// while the home screen is on top. Nothing animates: this sits on the home
// screen all day, and it should cost nothing while it does.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"

  readonly property var battery: UPower.displayDevice
  readonly property bool present: !!battery && battery.isPresent === true
  readonly property int percent: present ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: present && !UPower.onBattery
  readonly property bool full: present && battery.state === UPowerDeviceState.FullyCharged
  readonly property color okColor: home && home.okColor ? home.okColor : Commons.Color.accent

  readonly property var cached: home && entry ? home.widgetCache(entry.id) : null
  property var info: HomeModel.systemInfo(cached ? cached.data : "")

  Process {
    id: proc
    command: ["timeout", "5", "sh", "-c", HomeModel.SYSTEM_COMMAND]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        widget.info = HomeModel.systemInfo(text)
        if (widget.home && widget.entry) widget.home.setWidgetCache(widget.entry.id, { at: Date.now(), data: String(text || "") })
      }
    }
  }

  function refresh(force) {
    if (proc.running) return
    var c = home && entry ? home.widgetCache(entry.id) : null
    if (!force && c && Date.now() - c.at < 300000) return
    proc.running = true
  }

  Component.onCompleted: refresh(false)
  Timer {
    interval: 300000
    repeat: true
    running: !(widget.home && widget.home.owlPaused)
    onTriggered: widget.refresh(true)
  }

  readonly property string textFont: home && home.textFont ? home.textFont : Style.font.family
  // A third row (memory, battery) only on a card taller than the default.
  readonly property bool tall: height >= 250
  readonly property string batteryLine: {
    if (!present) return "No battery"
    var parts = [percent + "%", full ? "Full" : charging ? "Charging" : "On battery"]
    if (info.temperature !== null) parts.push(info.temperature.toFixed(0) + " °C")
    if (info.health) parts.push(info.health)
    return parts.join(" · ")
  }
  readonly property string upText: HomeModel.uptimeText(info.uptime)

  // Centred in the card, so a taller cell spreads its margin evenly.
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 18
    spacing: 12

    // The system's mark, its name and base, and how long it has been up.
    Row {
      width: parent.width
      spacing: 12

      Rectangle {
        id: mark
        width: 44; height: 44
        radius: 12
        color: Qt.rgba(widget.fg.r, widget.fg.g, widget.fg.b, 0.85)
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "󰆧"
          color: widget.home ? widget.home.cardSolid : "black"
          font.family: Style.font.family
          font.pixelSize: 22
        }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - mark.width - pill.width - parent.spacing * 2
        spacing: Style.spacing.xxs
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Omarchy Mobile"
          color: widget.fg
          font.family: widget.textFont
          font.pixelSize: 17
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: [widget.info.os, widget.info.base].filter(function(s) { return !!s }).join(" · ") || "…"
          color: widget.dim
          font.family: widget.textFont
          font.pixelSize: 13
          elide: Text.ElideRight
        }
      }
      Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        visible: widget.upText.length > 0
        width: visible ? upLabel.implicitWidth + 20 : 0
        height: upLabel.implicitHeight + 10
        radius: 12
        color: widget.home && widget.home.darkCards ? Qt.rgba(34 / 255, 165 / 255, 91 / 255, 0.18) : Qt.rgba(widget.okColor.r, widget.okColor.g, widget.okColor.b, 0.16)
        Text {
          id: upLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Up " + widget.upText
          color: widget.home && widget.home.darkCards ? "#5fd38f" : widget.okColor
          font.family: widget.textFont
          font.pixelSize: 12
          font.weight: Font.DemiBold
        }
      }
    }

    // Two columns of facts.
    Grid {
      width: parent.width
      columns: 2
      rowSpacing: 8
      columnSpacing: 16

      Repeater {
        // Without a boot label in the descriptor, memory takes its place.
        readonly property var memory: ({ k: "Memory", v: widget.info.memoryGb !== null ? widget.info.memoryGb + " GB" : "" })
        model: [
          { k: "Device", v: widget.info.device },
          { k: "SoC", v: widget.info.soc },
          { k: "Kernel", v: widget.info.kernel },
          widget.info.boot ? { k: "Boot", v: widget.info.boot } : memory
        ].concat(widget.tall ? (widget.info.boot ? [memory] : []).concat([{ k: "Battery", v: widget.batteryLine }]) : [])
        delegate: Column {
          required property var modelData
          width: (widget.width - 36 - 16) / 2
          spacing: 1
          Text {
            textFormat: Text.PlainText
            text: modelData.k
            color: widget.dim
            font.family: widget.textFont
            font.pixelSize: 13
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.v || "–"
            color: widget.fg
            font.family: widget.textFont
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !widget.editing
    onClicked: widget.refresh(true)
  }
}
