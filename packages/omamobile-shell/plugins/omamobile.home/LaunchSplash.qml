// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

// Android's launch splash: the moment an app is tapped, its icon and name
// fill the screen, so the tap shows at once. An app takes about a second to
// map its window on markw, and Omarchy's own "Launching…" note waits 2 s,
// so a tap looked ignored. The app's window covers the splash when it maps;
// the splash goes away when a window opens or an open one takes focus, on a
// tap, or after 30 s if the app never shows a window. Chromium took over
// 20 s to map its first window on markw: a 5 s splash gave way to the home
// screen, as if the tap had failed, and a second tap opened a second
// window. After 5 s a line says it is still starting and that a tap goes
// back.
// The same file is in omamobile.home and omamobile.launcher: plugins don't
// share QML, and IPC between them (omarchy-shell, about 300 ms) is too slow
// for this.
Rectangle {
  id: splash

  property string iconSource: ""
  property string name: ""
  property int timeout: 30000
  property int slowAfter: 5000
  property bool slow: false
  signal finished()

  visible: false
  color: Commons.Color.menu.background

  function show(icon, text) {
    iconSource = String(icon || "")
    name = String(text || "")
    slow = false
    visible = true
    timer.restart()
    slowTimer.restart()
  }

  // Quietly, as when the surface closes: no finished().
  function reset() {
    timer.stop()
    slowTimer.stop()
    slow = false
    visible = false
  }

  function hide() {
    if (!visible) return
    reset()
    finished()
  }

  Timer {
    id: timer
    interval: splash.timeout
    onTriggered: splash.hide()
  }

  Timer {
    id: slowTimer
    interval: splash.slowAfter
    onTriggered: splash.slow = true
  }

  Connections {
    target: Hyprland
    enabled: splash.visible
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "openwindow") splash.hide()
      // An open window focused instead of a new one started; not the empty
      // home screen a launch may switch to first ("activewindow>>,").
      else if (event.name === "activewindow" && String(event.data || "").charAt(0) !== ",") splash.hide()
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: splash.hide()
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.spacing.lg

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 96
      height: 96
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: splash.iconSource
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, splash.width - 2 * Style.spacing.xxl)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: splash.name
      color: Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: 16
      font.weight: Font.Medium
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.xxl * 2
    width: Math.min(implicitWidth, splash.width - 2 * Style.spacing.xxl)
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: "Still starting… tap to go back"
    color: Commons.Color.menu.text
    opacity: splash.slow ? 0.6 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    font.family: Style.font.family
    font.pixelSize: 13
    wrapMode: Text.WordWrap
  }
}
