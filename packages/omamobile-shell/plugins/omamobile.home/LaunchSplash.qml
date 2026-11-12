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
// tap, or after a few seconds if the app never shows a window.
// The same file is in omamobile.home and omamobile.launcher: plugins don't
// share QML, and IPC between them (omarchy-shell, about 300 ms) is too slow
// for this.
Rectangle {
  id: splash

  property string iconSource: ""
  property string name: ""
  property int timeout: 5000
  signal finished()

  visible: false
  color: Commons.Color.menu.background

  function show(icon, text) {
    iconSource = String(icon || "")
    name = String(text || "")
    visible = true
    timer.restart()
  }

  // Quietly, as when the surface closes: no finished().
  function reset() {
    timer.stop()
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
}
