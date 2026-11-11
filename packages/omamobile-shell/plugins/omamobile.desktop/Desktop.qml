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

// The desktop for desktop mode (bin/omamobile-desktop-mode, the Desktop
// tile; design in docs/design/desktop-mode). While the mode is on:
//
//   - a plain backdrop over the wallpaper, where the phone's home screen
//     steps aside (omamobile.home hides itself);
//   - a dock at the bottom: the app launcher, then the apps last opened
//     (omamobile-launch's recent-apps list), with a dot under the ones
//     that have a window; a click focuses the window or starts the app
//     through omamobile-launch, which keeps it on this screen in desktop mode.
//     It hides while the focused window fills the screen, and the bottom
//     edge brings it back;
//   - a status card under the bar's right end (the bar opens it through the
//     host): the screen, Bluetooth, Wi-Fi and the battery, quick
//     settings, and the way back to phone mode.
//
// The mode script says when the mode changes (IPC setDesktopMode); this asks
// once at load. The phone's surfaces are untouched while the mode is off.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.desktop"
  property bool opened: false
  property bool desktopMode: false

  readonly property color background: Commons.Color.popups.background
  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property string glyphFont: Style.font.family
  readonly property string textFont: "Adwaita Sans"

  // ---------------------------------------------------------------- lifecycle

  // The bar's tap; the card only exists in desktop mode.
  function open(payloadJson) { opened = desktopMode }
  function close() { opened = false }
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // Also checks the scale when the mode comes on or the shell loads into it:
  // it may have drifted while nothing here was listening.
  onDesktopModeChanged: {
    if (!desktopMode) close()
    else reapplyTimer.restart()
  }

  Process {
    command: ["omamobile-desktop-mode", "status"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.desktopMode = String(text || "").trim() === "on"
    }
  }

  IpcHandler {
    target: "omamobile.desktop"

    function setDesktopMode(state: string): string {
      root.desktopMode = state === "on"
      return "ok"
    }

    function state(): string {
      return JSON.stringify({ desktopMode: root.desktopMode, opened: root.opened, dock: root.dockApps })
    }
  }

  // ---------------------------------------------------------------- dock apps

  // The apps last opened, newest first: omamobile-launch keeps the list (the
  // launcher's Recent row reads the same file). Ids that no longer name an
  // installed, shown app are skipped.
  readonly property int dockLimit: 7
  property var recentIds: []
  readonly property var dockApps: {
    var out = []
    for (var i = 0; i < recentIds.length && out.length < dockLimit; i++) {
      var entry = entryFor(recentIds[i])
      if (!entry || entry.noDisplay) continue
      if (appLibrary && typeof appLibrary.isHiddenEntry === "function" && appLibrary.isHiddenEntry(entry)) continue
      out.push(recentIds[i])
    }
    return out
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omamobile/recent-apps"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var out = []
      String(text() || "").split(/\r?\n/).forEach(function(line) {
        var id = line.trim()
        if (id && out.indexOf(id) < 0) out.push(id)
      })
      root.recentIds = out
    }
    onLoadFailed: root.recentIds = []
    onFileChanged: reload()
  }

  readonly property var appLibrary: shell && shell.appLibrary ? shell.appLibrary : null

  function entryFor(appId) {
    return DesktopEntries.byId(appId) || DesktopEntries.byId(appId + ".desktop") || null
  }

  function iconFor(entry) {
    var name = entry ? entry.icon : ""
    if (appLibrary && typeof appLibrary.iconSource === "function") return appLibrary.iconSource(name)
    return name ? Quickshell.iconPath(name, true) : ""
  }

  // A window of this app is open: its Wayland app id is the desktop id, or
  // the entry's StartupWMClass.
  function running(appId, entry) {
    var want = [String(appId).toLowerCase().replace(/\.desktop$/, "")]
    if (entry && entry.startupClass) want.push(String(entry.startupClass).toLowerCase())
    var list = ToplevelManager.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i].appId || "").toLowerCase()
      if (want.indexOf(id) >= 0) return true
    }
    return false
  }

  function launch(appId) {
    Quickshell.execDetached(["omamobile-launch", "app", String(appId)])
  }

  // Through the CLI, like the launcher's recent apps: the host lets a plugin
  // summon only its own panels, and refuses others' without a word.
  function openLauncher() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omamobile.launcher", "{}"])
  }

  function openQuickSettings() {
    dismiss()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.quicksettings", JSON.stringify({ source: "desktop" })])
  }

  // Through the Desktop tile, so the switch back runs behind its cover.
  function phoneMode() {
    dismiss()
    Quickshell.execDetached(["omarchy-shell", "shell", "call", "omamobile.quicksettings", "toggleTile", "desktop"])
  }

  // ---------------------------------------------------------------- status

  readonly property var connectedDevices: {
    var out = []
    var list = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].connected) out.push(list[i])
    return out
  }

  readonly property bool bluetoothOn: !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
  readonly property string bluetoothText: {
    if (!bluetoothOn) return "Off"
    if (connectedDevices.length === 0) return "Nothing connected"
    var names = []
    for (var i = 0; i < connectedDevices.length; i++)
      names.push(connectedDevices[i].name || connectedDevices[i].deviceName || "Device")
    return names.join(", ")
  }

  // The Wi-Fi network in use, found as the bar finds it.
  readonly property var wifiNetwork: {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== DeviceType.Wifi || !device.networks) continue
      var networks = device.networks.values
      for (var j = 0; j < networks.length; j++)
        if (networks[j] && networks[j].connected) return networks[j]
    }
    return null
  }
  readonly property string wifiText: wifiNetwork ? (wifiNetwork.name || "Connected")
    : Networking.wifiEnabled ? "Not connected" : "Off"

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent === true
  readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: hasBattery && !UPower.onBattery

  readonly property var panel: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

  // On markw the panel went back to the phone's scale a second after waking
  // from idle, with no Hyprland event to say so; its size changing is the
  // sign. The mode script reloads only if the scale is really off.
  Connections {
    target: root.panel
    ignoreUnknownSignals: true
    function onWidthChanged() { if (root.desktopMode) reapplyTimer.restart() }
    function onHeightChanged() { if (root.desktopMode) reapplyTimer.restart() }
  }

  Timer {
    id: reapplyTimer
    interval: 600
    onTriggered: Quickshell.execDetached(["omamobile-desktop-mode", "reapply"])
  }

  // ---------------------------------------------------------------- backdrop

  PanelWindow {
    id: backdrop

    visible: root.desktopMode
    screen: root.panel
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: root.background
    WlrLayershell.namespace: "omamobile-desktop"
    // Bottom: over the wallpaper, under every window (as the home screen).
    WlrLayershell.layer: WlrLayer.Bottom

    // A faint light from the lower right, as in the design.
    Rectangle {
      width: parent.width * 0.9
      height: width
      radius: width / 2
      x: parent.width * 0.55
      y: parent.height * 0.45
      color: root.accent
      opacity: 0.05
    }
  }

  // ---------------------------------------------------------------- dock

  // The dock hides while the focused window fills the screen (maximized or
  // fullscreen) and gives it the dock's room; the pointer at the bottom edge,
  // or a tap there, brings it back over the window until the pointer leaves.
  readonly property var activeWindow: ToplevelManager.activeToplevel
  readonly property bool windowFills: !!activeWindow && (activeWindow.maximized || activeWindow.fullscreen)
  property bool dockPeek: false
  readonly property bool dockHidden: windowFills && !dockPeek

  onWindowFillsChanged: if (windowFills) dockPeek = false

  Timer {
    id: dockHideTimer
    interval: 700
    onTriggered: root.dockPeek = false
  }

  Timer {
    id: dockTouchTimer
    interval: 4000
    onTriggered: root.dockPeek = false
  }

  PanelWindow {
    id: dockWindow

    visible: root.desktopMode
    screen: root.panel
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 76
    // Hidden, it reserves nothing, so a maximized window reaches the bottom.
    exclusionMode: root.windowFills ? ExclusionMode.Ignore : ExclusionMode.Auto
    color: "transparent"
    WlrLayershell.namespace: "omamobile-desktop-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Only the dock itself takes the pointer, or while it hides, a strip
    // along the bottom edge; the rest is the windows'.
    // While it peeks over a window, the whole strip it stands in, so it
    // stays until the pointer leaves that strip.
    mask: Region { item: root.dockHidden ? dockEdge : root.windowFills ? dockZone : dock }

    // The strip the dock stands in: leaving it hides a peeking dock. A touch
    // has no pointer to leave, so a dock raised by a tap hides after a while.
    Item {
      id: dockZone
      anchors.fill: parent

      HoverHandler {
        onHoveredChanged: {
          if (hovered) dockHideTimer.stop()
          else if (root.dockPeek) dockHideTimer.restart()
        }
      }

      Item {
        id: dockEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 4

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: { dockHideTimer.stop(); root.dockPeek = true }
          onPressed: { root.dockPeek = true; dockTouchTimer.restart() }
        }
      }

      Rectangle {
        id: dock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.dockHidden ? -height - 4 : 12
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        opacity: root.dockHidden ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 180 } }
        height: 56
        width: dockRow.implicitWidth + 12
        radius: 18
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

        Row {
          id: dockRow
          anchors.centerIn: parent
          spacing: 4

          DockButton {
            highlighted: true
            glyph: "󰀻"
            onActivated: root.openLauncher()
          }

          Rectangle {
            visible: root.dockApps.length > 0
            width: 1; height: 26
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            opacity: 0.12
          }

          Repeater {
            model: root.dockApps
            delegate: DockButton {
              required property string modelData
              readonly property var entry: root.entryFor(modelData)
              icon: root.iconFor(entry)
              glyph: icon === "" ? "󰀻" : ""
              showDot: root.running(modelData, entry)
              onActivated: root.launch(modelData)
            }
          }
        }
      }
    }
  }

  component DockButton: Rectangle {
    id: button
    property bool highlighted: false
    property string icon: ""
    property string glyph: ""
    property bool showDot: false
    signal activated()

    width: 44; height: 44; radius: 12
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: highlighted ? root.accent
      : hover.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

    Image {
      visible: button.icon !== ""
      anchors.centerIn: parent
      width: 28; height: 28
      source: button.icon
      sourceSize.width: 56
      sourceSize.height: 56
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }

    Text {
      visible: button.glyph !== ""
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: button.highlighted ? root.background : root.foreground
      font.family: root.glyphFont
      font.pixelSize: 20
    }

    Rectangle {
      visible: button.showDot
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 3
      width: 4; height: 4; radius: 2
      color: root.accent
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }

  // ---------------------------------------------------------------- status card

  PanelWindow {
    id: cardWindow

    visible: root.opened && root.desktopMode
    screen: root.panel
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-desktop-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The windows behind dim a little; a click outside closes the card.
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: 0.2
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: 42
      anchors.rightMargin: 14
      width: 300
      height: cardColumn.implicitHeight + 24
      radius: 16
      color: root.background
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

      focus: root.opened
      Keys.onEscapePressed: root.dismiss()

      // Clicks on the card stay on it.
      MouseArea { anchors.fill: parent }

      Column {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 2

        Row {
          spacing: 10
          bottomPadding: 10

          Rectangle {
            width: 34; height: 34; radius: 10
            color: root.accent
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰍹"
              color: root.background
              font.family: root.glyphFont
              font.pixelSize: 18
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            CardText { text: "Phone screen"; font.bold: true; font.pixelSize: 14 }
            CardText {
              text: root.panel ? "Landscape · " + root.panel.width + " × " + root.panel.height : "Landscape"
              muted: true
              font.pixelSize: 11
            }
          }
        }

        Rectangle {
          width: parent.width; height: 1
          color: root.foreground
          opacity: 0.08
        }

        StatusRow {
          glyph: root.connectedDevices.length > 0 ? "󰂱" : "󰂯"
          label: "Bluetooth"
          value: root.bluetoothText
          good: root.connectedDevices.length > 0
        }
        StatusRow {
          glyph: root.wifiNetwork ? "󰤨" : "󰤭"
          label: "Wi-Fi"
          value: root.wifiText
          good: !!root.wifiNetwork
        }
        StatusRow {
          visible: root.hasBattery
          glyph: root.charging ? "󰂄" : "󰁹"
          label: "Battery"
          value: root.batteryPercent + "%" + (root.charging ? " · charging" : " · not charging")
          good: root.charging
        }

        Item { width: 1; height: 6 }

        Row {
          width: parent.width
          spacing: 8

          CardButton {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰒓"
            label: "Settings"
            onActivated: root.openQuickSettings()
          }
          CardButton {
            width: (parent.width - parent.spacing) / 2
            glyph: "󰄜"
            label: "Phone mode"
            onActivated: root.phoneMode()
          }
        }
      }
    }
  }

  component CardText: Text {
    property bool muted: false
    textFormat: Text.PlainText
    color: root.foreground
    opacity: muted ? 0.65 : 1
    elide: Text.ElideRight
    font.family: root.textFont
    font.pixelSize: 13
  }

  component StatusRow: Item {
    property string glyph: ""
    property string label: ""
    property string value: ""
    property bool good: false
    width: parent ? parent.width : 0
    height: 34

    Text {
      id: rowGlyph
      anchors.left: parent.left
      anchors.leftMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      width: 20
      textFormat: Text.PlainText
      text: parent.glyph
      color: root.foreground
      opacity: 0.65
      font.family: root.glyphFont
      font.pixelSize: 15
    }
    CardText {
      anchors.left: rowGlyph.right
      anchors.leftMargin: 8
      anchors.right: rowValue.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
    }
    CardText {
      id: rowValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      // Device and network names can be long: a share of the row, elided.
      width: Math.min(implicitWidth, parent.width * 0.62)
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
      text: parent.value
      muted: !parent.good
      color: parent.good ? root.accent : root.foreground
      font.bold: parent.good
      font.pixelSize: 12
    }
  }

  component CardButton: Rectangle {
    id: cardButton
    property string glyph: ""
    property string label: ""
    signal activated()

    height: 38
    radius: 11
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, buttonArea.containsMouse ? 0.12 : 0.07)

    Row {
      anchors.centerIn: parent
      spacing: 7
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: cardButton.glyph
        color: root.foreground
        font.family: root.glyphFont
        font.pixelSize: 15
      }
      CardText {
        anchors.verticalCenter: parent.verticalCenter
        text: cardButton.label
        font.bold: true
        font.pixelSize: 12
      }
    }

    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cardButton.activated()
    }
  }
}
