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
// keyboard" button until the keyboard unfolds again or another window takes
// focus (markw, 2026-10-27).
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
  function hideKeyboard() { fold(); setVisible(false); return "ok" }
  function showKeyboard() { setVisible(true); return "ok" }
  function toggleKeyboard() { setVisible(!oskOpen); return oskOpen ? "hiding" : "showing" }

  // Showing also turns squeekboard back on: the screensaver turns it off
  // while it runs, and a keyboard left off ignores SetVisible.
  function setVisible(visible) {
    var call = "busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b " + (visible ? "true" : "false")
    if (visible)
      call = "gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true; sleep 0.2; " + call
    Quickshell.execDetached(["sh", "-c", call])
  }

  property bool oskOpen: false
  // Folded, by our button or by anything else (the screen going off and the
  // lock coming up folds it too); cleared when the keyboard unfolds again.
  // A field that keeps its focus across the lock gets no new focus-in, so
  // without the button nothing brought the keyboard back (markw).
  property bool userHidden: false
  // Folded over an app's window rather than a shell surface (the drawer's
  // search, the lock).
  property bool foldedInApp: false
  // The app it was folded over (or the last one, folded over the lock).
  property var foldedOn: null
  property var lastApp: null
  onOskOpenChanged: oskOpen ? (userHidden = false) : fold()

  function fold() {
    var active = ToplevelManager.activeToplevel
    foldedInApp = active !== null
    foldedOn = active !== null ? active : lastApp
    userHidden = true
  }

  // ...or after a while unused, but only when folded over a shell surface
  // and not locked: left in the corner of the home screen, it covered the
  // edit mode's Done button.
  Timer {
    id: unusedTimer
    running: root.userHidden && !root.foldedInApp
    interval: 10000
    onTriggered: lockCheck.running = true
  }
  Process {
    id: lockCheck
    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (String(text).trim() === "true") unusedTimer.restart()
        else root.userHidden = false
      }
    }
  }

  // ...or when another app takes focus: its fields get a focus-in of their
  // own, and a closed terminal shouldn't leave the button behind. Coming
  // back to the same app (from the lock) keeps it.
  Connections {
    target: ToplevelManager
    ignoreUnknownSignals: true
    function onActiveToplevelChanged() {
      var active = ToplevelManager.activeToplevel
      if (active === null) return
      if (active !== root.foldedOn) root.userHidden = false
      root.lastApp = active
    }
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
