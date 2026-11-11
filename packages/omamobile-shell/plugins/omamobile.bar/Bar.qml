// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "StatusModel.js" as StatusModel

// Phone status bar, a full `bar` option that replaces omarchy.bar.
//
// The phone has no window list, tray or workspaces to show, so this bar only
// reports state: the clock on the left and connectivity, do-not-disturb and
// battery on the right. The middle stays empty for the camera cutout. The
// whole strip is one touch target: a tap or a downward pull opens the quick
// settings sheet.
Item {
  id: root

  // Injected by the host (see shell.qml configureBar).
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  // Scalar bar state the host mirrors to other plugins (notifications and the
  // OSD place themselves clear of the bar with these).
  readonly property bool barHidden: false
  readonly property string position: "top"
  readonly property bool vertical: false
  readonly property string fontFamily: Style.font.family
  // A phone status bar is a touch target, and the Pixel's camera cutout sits
  // in it, so it is never thinner than 44 logical px. In desktop mode it is a
  // pointer's bar on a landscape screen, so thinner.
  readonly property int barSize: desktopMode ? 36 : Math.max(44, Style.bar.sizeHorizontal)

  // Desktop mode (omamobile-desktop-mode): the bar shows the desktop layout
  // (docs/design/desktop-mode), and a tap opens the status card of
  // omamobile.desktop instead of the quick settings sheet. The mode script
  // says when it changes; this asks once at load.
  property bool desktopMode: false
  readonly property string desktopId: "omamobile.desktop"

  Process {
    command: ["omamobile-desktop-mode", "status"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.desktopMode = String(text || "").trim() === "on"
    }
  }

  readonly property color foreground: Commons.Color.bar.text
  readonly property color background: Commons.Color.bar.background
  readonly property color urgent: Commons.Color.bar.active

  function setting(name, fallback) {
    var value = barConfig ? barConfig[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string clockFormat: String(setting("clockFormat", "HH:mm"))
  readonly property bool showBatteryPercent: setting("showBatteryPercent", true) !== false
  readonly property string quickSettingsId: String(setting("quickSettings", "omamobile.quicksettings"))

  // A full bar may read the notification service's do-not-disturb state
  // through the host's narrow proxy.
  readonly property var notifications: shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool doNotDisturb: notifications ? notifications.doNotDisturb === true : false

  // ---------------------------------------------------------------- state

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: StatusModel.findDevice(networkDevices, DeviceType.Wifi)
  readonly property var wiredDevice: StatusModel.findDevice(networkDevices, DeviceType.Wired)
  readonly property var wifiNetwork: StatusModel.connectedNetwork(wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : [])
  readonly property string networkKind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (wifiNetwork) return "wifi"
    return wifiDevice && !Networking.wifiEnabled ? "off" : "disconnected"
  }
  readonly property string networkIcon: StatusModel.networkIcon(networkKind,
    wifiNetwork ? Math.round((wifiNetwork.signalStrength || 0) * 100) : -1)

  // The mobile network, from ModemManager's API through
  // bin/omamobile-cell-watch (omamobile-mmd serves it on the Pixel 7 Pro).
  // No modem, no icon.
  property var cell: null
  readonly property string cellGlyph: StatusModel.cellGlyph(cell)
  readonly property string cellText: StatusModel.cellText(cell)

  Process {
    id: cellWatch
    command: ["omamobile-cell-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var c = StatusModel.parseCell(line)
        if (c) root.cell = c
      }
    }
    onExited: { root.cell = null; cellRestart.restart() }
  }
  Timer { id: cellRestart; interval: 5000; onTriggered: cellWatch.running = true }

  // A call in progress: a chip with its time beside the clock. omatel's
  // agent through bin/omamobile-call-watch --observe (the call card runs
  // the waking, name-holding copy).
  property string callLine: ""
  property double nowMs: Date.now()
  readonly property string callChip: StatusModel.callChip(callLine, nowMs) || ""

  Process {
    id: callWatch
    command: ["omamobile-call-watch", "--observe"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.callLine = String(line) } }
    onExited: { root.callLine = ""; callRestart.restart() }
  }
  Timer { id: callRestart; interval: 5000; onTriggered: callWatch.running = true }
  Timer {
    interval: 1000
    repeat: true
    running: root.callChip !== ""
    onTriggered: root.nowMs = Date.now()
  }

  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothConnected: {
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) return true
    return false
  }

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent === true
  readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: hasBattery && !UPower.onBattery
  readonly property string batteryIcon: StatusModel.batteryIcon(batteryPercent, charging,
    hasBattery && battery.state === UPowerDeviceState.FullyCharged)

  // ---------------------------------------------------------------- host API

  // The host calls these on whatever bar is active. A phone bar hosts no
  // widget panels, so every per-widget route answers "not here".
  function summonBarWidget(id) { return false }
  function hideBarWidget(id) { return false }
  function isBarWidgetOpen(id) { return false }
  function panelWidgetIdAt(section, index) { return "" }
  function debugBarGeometry() { return [{ position: position, size: barSize }] }

  function openQuickSettings() {
    if (shell && typeof shell.summon === "function")
      shell.summon(quickSettingsId, JSON.stringify({ source: "bar" }))
  }

  function toggleQuickSettings() {
    if (shell && typeof shell.toggle === "function")
      shell.toggle(quickSettingsId, JSON.stringify({ source: "bar" }))
  }

  function toggleDesktopCard() {
    if (shell && typeof shell.toggle === "function")
      shell.toggle(desktopId, JSON.stringify({ source: "bar" }))
  }

  // Edge-swipe gestures and hardware keys reach the sheet through here, e.g.
  // `omarchy-shell omamobile.bar pullDown` from a Hyprland gesture bind.
  IpcHandler {
    target: "omamobile.bar"

    function pullDown(): string {
      root.openQuickSettings()
      return "ok"
    }

    function toggleQuickSettings(): string {
      root.toggleQuickSettings()
      return "ok"
    }

    function setDesktopMode(state: string): string {
      root.desktopMode = state === "on"
      return "ok"
    }
  }

  // ---------------------------------------------------------------- surface

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: barWindow

      required property var modelData
      screen: modelData

      anchors { top: true; left: true; right: true }
      implicitHeight: root.barSize
      exclusionMode: ExclusionMode.Auto
      color: root.background
      WlrLayershell.namespace: "omarchy-bar"
      WlrLayershell.layer: WlrLayer.Top

      // Above the strip's touch area (below), so the call chip takes its
      // own taps; nothing else in here handles touches, so the rest still
      // reaches the pull-down.
      Item {
        z: 1
        visible: !root.desktopMode
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.huge
        anchors.rightMargin: Style.spacing.huge

        Text {
          id: clockText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Qt.formatDateTime(clock.date, root.clockFormat)
          color: root.foreground
          // The time in a sans, like the home screen's words; glyphs keep
          // the shell font.
          font.family: "Adwaita Sans"
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // The call in progress, beside the clock; a tap opens the Phone
        // app's in-call screen (the bar is never shown over the lock).
        Rectangle {
          id: callChipPill
          objectName: "callChip"
          visible: root.callChip !== ""
          z: 2
          anchors.left: clockText.right
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          height: Math.round(root.barSize * 0.66)
          width: chipRow.implicitWidth + Style.spacing.lg * 2
          radius: height / 2
          color: chipTap.pressed ? Qt.darker("#1e9e53", 1.2) : "#1e9e53"

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.spacing.xs
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: String.fromCodePoint(0xF03F2); color: "white"; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: root.callChip; color: "white"; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
          }

          MouseArea {
            id: chipTap
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["omaphone", "--in-call"])
          }
        }

        Row {
          id: status
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xl

          StatusGlyph {
            visible: root.doNotDisturb
            text: "󰂛"
          }

          StatusGlyph {
            visible: !!root.btAdapter && root.btAdapter.enabled
            text: root.bluetoothConnected ? "󰂱" : "󰂯"
          }

          Row {
            visible: root.cellGlyph !== ""
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.cell && root.cell.state === "searching" ? 0.55 : 1

            StatusGlyph { text: root.cellGlyph }
            Text {
              visible: text !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.cellText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          StatusGlyph {
            visible: root.networkIcon !== ""
            text: root.networkIcon
            opacity: root.networkKind === "off" || root.networkKind === "disconnected" ? 0.55 : 1
          }

          Row {
            visible: root.hasBattery
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            StatusGlyph {
              text: root.batteryIcon
              color: root.batteryPercent >= 0 && root.batteryPercent <= 10 && !root.charging ? root.urgent : root.foreground
            }

            Text {
              visible: root.showBatteryPercent
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.batteryPercent + "%"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }

      // Desktop mode: the logo and the mode's name on the left; status, the
      // battery and the date on the right.
      Item {
        z: 1
        visible: root.desktopMode
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.xl
        anchors.rightMargin: Style.spacing.xl

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.md

          Rectangle {
            width: 24; height: 24; radius: 7
            color: Commons.Color.accent
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰍹"
              color: Commons.Color.popups.background
              font.family: root.fontFamily
              font.pixelSize: 14
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "DESKTOP MODE"
            color: Commons.Color.bar.text
            opacity: 0.7
            font.family: "Adwaita Sans"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.6
          }
        }

        // The focused window: windows have no title bar in desktop mode, so
        // its name, maximize and close live here.
        Row {
          id: windowControls
          readonly property var toplevel: ToplevelManager.activeToplevel
          visible: !!toplevel
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 360)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: windowControls.toplevel ? (windowControls.toplevel.title || windowControls.toplevel.appId || "") : ""
            color: root.foreground
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            font.bold: true
          }

          WindowButton {
            glyph: windowControls.toplevel && windowControls.toplevel.maximized ? "󰘕" : "󰊓"
            // Through Hyprland, not the toplevel's own request: Omarchy
            // suppresses every window's maximize event (windows.lua), so
            // setting `maximized` did nothing. fullscreen_state 1 is
            // Hyprland's maximize: the bar stays, the desktop's dock steps aside.
            onActivated: {
              if (!windowControls.toplevel) return
              var state = windowControls.toplevel.maximized ? 0 : 1
              Quickshell.execDetached(["hyprctl", "dispatch",
                "hl.dsp.window.fullscreen_state({ internal = " + state + ", client = 0 })"])
            }
          }

          WindowButton {
            glyph: "󰅖"
            danger: true
            onActivated: if (windowControls.toplevel) windowControls.toplevel.close()
          }
        }

        // The status icons and the date: the only part of the bar that opens
        // the status card in desktop mode. A maximized window's top edge sits
        // right under the bar, and a tap anywhere on it opened the card.
        Item {
          id: statusCluster
          anchors.right: parent.right
          anchors.rightMargin: -Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          width: statusRow.implicitWidth + Style.spacing.md * 2
          height: 28

          Rectangle {
            anchors.fill: parent
            radius: 8
            color: root.foreground
            opacity: statusTouch.pressed ? 0.16 : statusTouch.containsMouse ? 0.08 : 0
          }

          MouseArea {
            id: statusTouch
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleDesktopCard()
          }

          Row {
            id: statusRow
            anchors.centerIn: parent
            spacing: Style.spacing.lg

            DesktopGlyph { visible: root.doNotDisturb; text: "󰂛" }
            DesktopGlyph {
              visible: !!root.btAdapter && root.btAdapter.enabled
              text: root.bluetoothConnected ? "󰂱" : "󰂯"
            }
            DesktopGlyph {
              visible: root.networkIcon !== ""
              text: root.networkIcon
              opacity: root.networkKind === "off" || root.networkKind === "disconnected" ? 0.55 : 1
            }
            Row {
              visible: root.hasBattery
              spacing: Style.spacing.xs
              anchors.verticalCenter: parent.verticalCenter
              DesktopGlyph {
                text: root.batteryIcon
                color: root.batteryPercent >= 0 && root.batteryPercent <= 10 && !root.charging ? root.urgent : root.foreground
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.batteryPercent + "%"
                color: root.foreground
                opacity: 0.8
                font.family: "Adwaita Sans"
                font.pixelSize: 12
              }
            }
            Rectangle { width: 1; height: 16; color: root.foreground; opacity: 0.15; anchors.verticalCenter: parent.verticalCenter }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: clock.date.toLocaleString(Qt.locale("en_US"), "ddd d MMM · HH:mm")
              color: root.foreground
              font.family: "Adwaita Sans"
              font.pixelSize: 12
              font.bold: true
            }
          }
        }
      }

      // The whole strip is the touch target. A downward pull past a small
      // threshold opens the sheet; a tap toggles it (in desktop mode, the
      // status card, which leads to the sheet). Not in desktop mode: there
      // only the status icons open the card (statusCluster), so a click or a
      // drag at a window's top edge doesn't.
      MouseArea {
        id: touch
        anchors.fill: parent
        enabled: !root.desktopMode
        property real pressY: 0
        property bool pulled: false
        readonly property real pullThreshold: Style.space(14)

        onPressed: function(mouse) { pressY = mouse.y; pulled = false }
        onPositionChanged: function(mouse) {
          if (!pulled && mouse.y - pressY > pullThreshold) {
            pulled = true
            root.openQuickSettings()
          }
        }
        onClicked: if (!pulled) root.toggleQuickSettings()
      }
    }
  }

  component WindowButton: Rectangle {
    id: windowButton
    property string glyph: ""
    property bool danger: false
    signal activated()

    width: 26; height: 26; radius: 13
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: windowArea.containsMouse
      ? (danger ? "#e5484d" : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12))
      : "transparent"

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: windowButton.glyph
      color: windowArea.containsMouse && windowButton.danger ? "white" : root.foreground
      font.family: root.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: windowArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: windowButton.activated()
    }
  }

  component DesktopGlyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 15
  }

  component StatusGlyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.iconLarge
  }
}
