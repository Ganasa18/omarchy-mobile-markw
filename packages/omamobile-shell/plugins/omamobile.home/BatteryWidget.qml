// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons

// Battery level, charging state, time left and temperature. The level and
// state are UPower's display device (live); the temperature is one read of
// the battery's power_supply node when the widget appears and every five
// minutes while the home screen is on top. Nothing animates.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property var battery: UPower.displayDevice
  readonly property bool present: !!battery && battery.isPresent === true
  readonly property int percent: present ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: present && !UPower.onBattery
  readonly property bool full: present && battery.state === UPowerDeviceState.FullyCharged
  readonly property real seconds: !present ? 0 : (charging ? battery.timeToFull : battery.timeToEmpty)

  function duration(s) {
    if (!s || s <= 0) return ""
    var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
    return h > 0 ? h + " h " + m + " min" : m + " min"
  }

  readonly property string detail: !present ? "No battery"
    : full ? "Full"
    : charging ? (duration(seconds) ? "Full in " + duration(seconds) : "Charging")
    : (duration(seconds) ? duration(seconds) + " left" : "Discharging")

  // Tenths of a degree, from the first power_supply of type Battery.
  property real temperature: NaN
  Process {
    id: tempRead
    command: ["sh", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat \"$d/type\" 2>/dev/null)\" = Battery ] && { cat \"$d/temp\" 2>/dev/null; break; }; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        widget.temperature = isFinite(n) ? n / 10 : NaN
      }
    }
  }
  Component.onCompleted: tempRead.running = true
  Timer {
    interval: 300000
    repeat: true
    running: !(widget.home && widget.home.owlPaused)
    onTriggered: if (!tempRead.running) tempRead.running = true
  }

  readonly property string line: detail + (isNaN(temperature) ? "" : " · " + temperature.toFixed(0) + " °C")
  readonly property color levelColor: percent >= 0 && percent <= 15 && !charging ? Commons.Color.urgent
    : home && home.okColor ? home.okColor : Commons.Color.accent
  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"
  readonly property string textFont: home && home.textFont ? home.textFont : Style.font.family
  readonly property bool compact: width < 100

  // A label, the number, the level bar and what the battery is doing.
  Column {
    visible: !widget.compact
    anchors.verticalCenter: parent.verticalCenter
    x: Style.spacing.xl
    width: widget.width - Style.spacing.xl * 2
    spacing: Style.spacing.sm

    Text {
      visible: widget.height >= 110
      textFormat: Text.PlainText
      text: "BATTERY"
      color: widget.dim
      font.family: widget.textFont
      font.pixelSize: Style.font.caption + 1
      font.weight: Font.DemiBold
      font.letterSpacing: 1
    }
    Row {
      spacing: Style.spacing.xs
      Text {
        id: number
        textFormat: Text.PlainText
        text: widget.percent >= 0 ? String(widget.percent) : "–"
        color: widget.fg
        font.family: widget.textFont
        font.pixelSize: Math.max(Style.font.display, Math.min(widget.height * 0.3, 48))
        font.weight: Font.DemiBold
      }
      Text {
        anchors.baseline: number.baseline
        textFormat: Text.PlainText
        text: "%"
        color: widget.dim
        font.family: widget.textFont
        font.pixelSize: Style.font.heading
      }
      Text {
        anchors.baseline: number.baseline
        visible: widget.charging && !widget.full
        textFormat: Text.PlainText
        text: " 󱐋"
        color: widget.levelColor
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }
    }
    Rectangle {
      width: parent.width; height: 6; radius: 3
      color: Qt.rgba(widget.fg.r, widget.fg.g, widget.fg.b, 0.15)
      Rectangle { width: parent.width * Math.max(0, widget.percent) / 100; height: parent.height; radius: 3; color: widget.levelColor }
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: widget.line
      color: widget.dim
      font.family: widget.textFont
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  // One cell: just the number over a level bar.
  Column {
    anchors.centerIn: parent
    visible: widget.compact
    spacing: Style.spacing.sm

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: widget.percent >= 0 ? widget.percent + "%" : "–"
      color: widget.fg
      font.family: widget.textFont
      font.pixelSize: Style.font.heading
    }
    Rectangle {
      width: widget.width * 0.6; height: 4; radius: 2
      color: Qt.rgba(1, 1, 1, 0.2)
      Rectangle { width: parent.width * Math.max(0, widget.percent) / 100; height: parent.height; radius: 2; color: widget.levelColor }
    }
  }
}
