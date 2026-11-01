// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel

// This phone: the OS, the device, the kernel and the battery. The level and
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
  readonly property color levelColor: percent >= 0 && percent <= 15 && !charging ? Commons.Color.urgent : Commons.Color.accent

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

  readonly property bool tall: height >= 150
  readonly property string batteryLine: {
    if (!present) return "No battery"
    var parts = [full ? "Full" : charging ? "Charging" : "On battery"]
    if (info.temperature !== null) parts.push(info.temperature.toFixed(0) + " °C")
    if (info.voltage !== null) parts.push(info.voltage.toFixed(2) + " V")
    if (info.health) parts.push(info.health)
    return parts.join(" · ")
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.md

    // Title row: the system, the device, the battery number.
    Row {
      width: parent.width
      spacing: Style.spacing.lg

      Column {
        width: parent.width - pct.width - parent.spacing
        spacing: Style.spacing.xxs
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Omarchy Mobile"
          color: widget.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: [widget.info.os, widget.info.device].filter(function(s) { return !!s }).join(" · ") || "…"
          color: widget.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
      Text {
        id: pct
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: widget.percent >= 0 ? widget.percent + "%" : "–"
        color: widget.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
      }
    }

    // The level bar and what the battery is doing.
    Rectangle {
      width: parent.width; height: 6; radius: 3
      color: Qt.rgba(widget.fg.r, widget.fg.g, widget.fg.b, 0.15)
      Rectangle { width: parent.width * Math.max(0, widget.percent) / 100; height: parent.height; radius: 3; color: widget.levelColor }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: widget.batteryLine
      color: widget.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    // Two by two: kernel, SoC, memory, uptime. Only when there is room.
    Grid {
      visible: widget.tall
      width: parent.width
      columns: 2
      rowSpacing: Style.spacing.sm
      columnSpacing: Style.spacing.lg

      Repeater {
        model: [
          { k: "Kernel", v: widget.info.kernel },
          { k: "SoC", v: widget.info.soc },
          { k: "Memory", v: widget.info.memoryGb !== null ? widget.info.memoryGb + " GB" : "" },
          { k: "Up", v: HomeModel.uptimeText(widget.info.uptime) }
        ]
        delegate: Column {
          required property var modelData
          width: (widget.width - 2 * Style.spacing.xl - Style.spacing.lg) / 2
          Text {
            textFormat: Text.PlainText
            text: modelData.k
            color: widget.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.v || "–"
            color: widget.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
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
