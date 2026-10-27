// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// A "hide keyboard" button, as on Android: while squeekboard is unfolded, a
// small button sits just above the keyboard's top-right corner; a tap folds
// it (sm.puri.OSK0 SetVisible false). Visibility comes from
// bin/omamobile-osk-watch (squeekboard's Visible on the session bus).
//
// Folded by that button, the keyboard stays folded until a text field gets
// a new focus-in, and a tap on the field that already has focus (a
// terminal) gives none. So the button stays in the corner as a "show
// keyboard" button until the keyboard unfolds again (markw, 2026-10-27).
//
// The button's window is anchored to the bottom-right corner with normal
// exclusion, so the compositor places it right above the area the keyboard
// reserves; the window is the button, so it takes no other touches.
// hypr/phone.lua lets it work over the lock screen too (above_lock 2).
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  // Nothing to summon: it follows the keyboard.
  function open(payloadJson) {
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "omamobile.keyboard")
    })
  }
  function close() {}

  // `shell call omamobile.keyboard state ''`
  function state() {
    return JSON.stringify({ keyboard: oskOpen, folded: userHidden, watcher: oskWatch.running, button: button.visible })
  }

  // `shell call omamobile.keyboard hideKeyboard ''` / `showKeyboard ''` /
  // `toggleKeyboard ''` (not show/hide: the IPC command line takes `show`
  // for itself)
  function hideKeyboard() { userHidden = true; setVisible(false); return "ok" }
  function showKeyboard() { setVisible(true); return "ok" }
  function toggleKeyboard() { setVisible(!oskOpen); return oskOpen ? "hiding" : "showing" }

  function setVisible(visible) {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0",
                             "sm.puri.OSK0", "SetVisible", "b", visible ? "true" : "false"])
  }

  property bool oskOpen: false
  // Folded by our button; cleared when the keyboard unfolds again.
  property bool userHidden: false
  onOskOpenChanged: if (oskOpen) userHidden = false

  // ...or after a while unused: left in the corner of the home screen, it
  // covered the edit mode's Done button.
  Timer {
    running: root.userHidden
    interval: 10000
    onTriggered: root.userHidden = false
  }

  // ...or when another window takes focus: its fields get a focus-in of
  // their own, and a closed terminal shouldn't leave the button behind.
  Connections {
    target: ToplevelManager
    ignoreUnknownSignals: true
    function onActiveToplevelChanged() { root.userHidden = false }
  }

  Process {
    id: oskWatch
    command: ["omamobile-osk-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var words = String(line).trim().split(" ")
        if (words[0] === "visible") root.oskOpen = words[1] === "true"
      }
    }
    onExited: {
      root.oskOpen = false
      restart.restart()
    }
  }

  Timer {
    id: restart
    interval: 3000
    onTriggered: oskWatch.running = true
  }

  readonly property int size: Math.max(44, Style.space(44))

  PanelWindow {
    id: button

    visible: root.oskOpen || root.userHidden
    anchors { bottom: true; right: true }
    margins { right: Style.space(8); bottom: Style.space(6) }
    implicitWidth: root.size + Style.space(8)
    implicitHeight: Math.round(root.size * 0.8)
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-osk-hide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, Style.cornerRadius + 6)
        color: tap.pressed ? Qt.darker(Commons.Color.bar.background, 1.3) : Commons.Color.bar.background
        opacity: 0.92
        border.width: 1
        border.color: Qt.rgba(Commons.Color.bar.text.r, Commons.Color.bar.text.g, Commons.Color.bar.text.b, 0.25)
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        // nf-md-keyboard_close, or nf-md-keyboard while folded
        text: String.fromCodePoint(root.oskOpen ? 0xF030F : 0xF030C)
        color: Commons.Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Math.round(root.size * 0.5)
      }

      MouseArea {
        id: tap
        anchors.fill: parent
        onClicked: root.oskOpen ? root.hideKeyboard() : root.showKeyboard()
      }
    }
  }
}
