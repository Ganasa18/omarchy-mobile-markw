// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel

// Clock and date. Formats are Qt date formats from the widget's settings;
// without a time format the clock follows the system's 12- or 24-hour
// choice, the bar's clockFormat in shell.json.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false
  readonly property var config: entry && entry.config ? entry.config : ({})

  property string barFormat: ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var shell = JSON.parse(text() || "{}")
        widget.barFormat = shell.bar && shell.bar.clockFormat ? String(shell.bar.clockFormat) : ""
      } catch (e) { widget.barFormat = "" }
    }
  }

  readonly property string timeFormat: widget.config.timeFormat || HomeModel.systemTimeFormat(widget.barFormat)

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property bool wide: width > height * 1.6

  // With no card behind it (Home.qml's `bare`), a raised outline keeps the
  // text readable on a light wallpaper; a text style, not a shadow effect.
  readonly property bool bare: config.card !== true
  readonly property color shade: Qt.rgba(0, 0, 0, 0.55)
  // "align": "left" puts it at the start of its cell (beside a weather widget).
  readonly property int alignment: config.align === "left" ? Text.AlignLeft : Text.AlignHCenter

  readonly property string textFont: home && home.textFont ? home.textFont : Style.font.family

  // On a card ("card": true): the day as a small label, the time, the date,
  // all from the start edge.
  Column {
    visible: !widget.bare
    anchors.verticalCenter: parent.verticalCenter
    x: Style.spacing.xl
    width: widget.width - Style.spacing.xl * 2
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      visible: widget.height >= 110
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
      color: widget.home ? widget.home.dimForeground : "white"
      font.family: widget.textFont
      font.pixelSize: Style.font.caption + 1
      font.weight: Font.DemiBold
      font.letterSpacing: 1
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.timeFormat)
      color: widget.home ? widget.home.foreground : "white"
      font.family: widget.textFont
      font.pixelSize: Math.max(Style.font.display, Math.min(widget.height * 0.36, widget.width * 0.3))
      font.weight: Font.Light
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Style.font.title
    }
    Text {
      width: parent.width
      visible: widget.height >= 80
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.config.dateFormat && widget.config.dateFormat !== "dddd d MMMM" ? widget.config.dateFormat : "d MMMM")
      color: widget.home ? widget.home.dimForeground : "white"
      font.family: widget.textFont
      font.pixelSize: Style.font.body + 1
      elide: Text.ElideRight
    }
  }

  Column {
    visible: widget.bare
    anchors.verticalCenter: parent.verticalCenter
    x: Style.spacing.xxl
    width: widget.width - Style.spacing.xxl * 2
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      horizontalAlignment: widget.alignment
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.timeFormat)
      color: widget.home ? widget.home.foreground : "white"
      font.family: Style.font.family
      font.pixelSize: Math.max(Style.font.display, Math.min(widget.height * 0.46, widget.width * (config.align === "left" ? 0.42 : 0.26)))
      font.weight: Font.Light
      style: widget.bare ? Text.Raised : Text.Normal
      styleColor: widget.shade
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Style.font.title
    }

    Text {
      width: parent.width
      visible: widget.height >= 80
      horizontalAlignment: widget.alignment
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.config.dateFormat || "dddd d MMMM")
      color: widget.home ? widget.home.dimForeground : "white"
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      style: widget.bare ? Text.Raised : Text.Normal
      styleColor: widget.shade
      elide: Text.ElideRight
    }
  }
}
