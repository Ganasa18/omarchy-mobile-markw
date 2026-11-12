// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.services as OmarchyServices
import "LauncherModel.js" as LauncherModel

// The phone's home surface, after Omalauncher: one bar at the bottom of the
// screen that is app search, app list and coding-agent prompt at once.
//
// Collapsed, it is a gesture bar (a swipe up raises the app drawer with the
// input focused) or, with "dock": "search", a dock holding a single search
// pill that raises it on a tap. The drawer: the input, recent apps, then
// every app as a list. Typing filters the list; text that reads
// like a sentence (or matches no app) offers "Ask <agent>" (the user's
// Omarchy default agent) instead, and Enter
// takes whichever is on top: the first app, or a terminal running the agent
// with the text as its first prompt.
//
// Apps come from Omarchy's application library (services/AppLibrary.qml: the
// same entries, hidden-entry filters, icons and launch path as the Omarchy
// menu). The host shares its instance with `menu` plugins; see the Loader
// below for why this one is a `panel` that runs its own for now.
Item {
  id: root

  // Desktop mode (omamobile-desktop-mode): the home bar steps aside for the
  // desktop's backdrop and dock (omamobile.desktop). The mode script says
  // when it changes; this asks once at load.
  property bool desktopMode: false

  Process {
    command: ["omamobile-desktop-mode", "status"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.desktopMode = String(text || "").trim() === "on"
    }
  }

  IpcHandler {
    target: "omamobile.launcher"
    function setDesktopMode(state: string): string {
      root.desktopMode = state === "on"
      return "ok"
    }
  }

  // Injected by the host.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.launcher"
  readonly property var appLibrary: shell && shell.appLibrary ? shell.appLibrary : localLibrary.item

  // The host hands its application library only to `menu` plugins, and in
  // this Omarchy build a third-party menu loses its whole shell facade on the
  // next config change (phone/plugins/README.md has the details). So the
  // launcher declares `panel` and runs Omarchy's own AppLibrary type here: the
  // same entries, hidden-entry filters, icon index and launch path, in a
  // second instance. If the host ever provides one, that wins.
  Loader {
    id: localLibrary
    active: !!root.shell && !root.shell.appLibrary
    sourceComponent: Component { OmarchyServices.AppLibrary { } }
  }

  // `opened` is the drawer; the dock is always on screen.
  property bool opened: false
  property string query: ""
  property var apps: []
  property int appsRevision: 0

  // ---------------------------------------------------------------- settings

  property var shellConfig: ({})
  readonly property var settings: LauncherModel.mergedSettings(
    manifest && manifest.settings ? manifest.settings.defaults : ({}), shellConfig, pluginId)

  // The coding agent is the user's choice, made the Omarchy way:
  // omarchy-default-agent stores it in ~/.config/omarchy/defaults/agent and
  // leaves it unset until the user picks one. Read it live so a choice made
  // in Omarchy's menu shows up here at once.
  property string agentId: ""
  readonly property string agentName: LauncherModel.agentName(agentId)
  readonly property bool hasAgent: agentId.length > 0
  readonly property string agentIcon: hasAgent
    ? Util.fileUrl(omarchyPath + "/shell/plugins/agents/assets/" + agentId + ".svg") : ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.agentId = LauncherModel.agentId(text())
    onLoadFailed: root.agentId = ""
  }

  readonly property int columns: Math.max(3, Math.min(6, Number(settings.columns) || 4))
  readonly property int sentenceWords: Math.max(2, Number(settings.sentenceWords) || 3)

  // Plugin entries in shell.json carry their settings inline, but the host
  // only hands those to bar widgets, so read our own entry from the file.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.shellConfig = JSON.parse(text() || "{}") } catch (e) { root.shellConfig = ({}) }
    }
  }

  // ---------------------------------------------------------------- results

  // Words in the drawer are set in a sans, as on the home screen; the
  // shell's own font stays for glyphs.
  readonly property string textFont: "Adwaita Sans"
  readonly property bool darkSheet: Commons.Color.menu.background.hslLightness < 0.5

  // The Recent row: what omamobile-launch last started, one row of what is
  // still installed and shown.
  property var recentIds: []
  readonly property var recentEntries: {
    var out = []
    var revision = apps // re-evaluated when the app list changes
    for (var i = 0; i < recentIds.length && out.length < columns; i++) {
      var e = DesktopEntries.byId(recentIds[i]) || DesktopEntries.byId(recentIds[i] + ".desktop")
      if (e && !(appLibrary && appLibrary.isHiddenEntry && appLibrary.isHiddenEntry(e))) out.push(e)
    }
    return out
  }
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omamobile/recent-apps"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.recentIds = LauncherModel.recentIds(text())
    onLoadFailed: root.recentIds = []
  }

  readonly property bool promptMode: LauncherModel.looksLikePrompt(query, apps.length, sentenceWords)
  readonly property bool hasQuery: query.trim().length > 0

  function refreshApps() {
    // sortedEntries() yields ranked rows of { entry, score, ... }; the grid
    // wants the DesktopEntry objects themselves.
    var rows = appLibrary ? appLibrary.sortedEntries(query) : []
    var entries = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i] && rows[i].entry) entries.push(rows[i].entry)
    apps = entries
  }

  onQueryChanged: refreshApps()
  onAppLibraryChanged: refreshApps()

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.refreshApps() }
  }

  // ---------------------------------------------------------------- actions

  // Not AppLibrary.launch: omamobile-launch starts the app the same way
  // (uwsm-app -- gtk-launch) on a new empty workspace, or focuses it on its
  // own if it is already open. Omarchy's "Launching…" feedback stays.
  // On the phone the drawer stays up as the app's splash (LaunchSplash) until
  // its window opens: closing it at once showed the home screen for about a
  // second, as if the tap had done nothing.
  function launchApp(entry) {
    if (!entry || !entry.id) return
    if (appLibrary && typeof appLibrary.beginLaunchFeedback === "function")
      appLibrary.beginLaunchFeedback(appLibrary.entryName(entry))
    Quickshell.execDetached(LauncherModel.appArgv(entry.id))
    if (!desktopMode && appLibrary) {
      if (input) input.focus = false
      launchSplash.show(appLibrary.iconSource(entry.icon || ""), appLibrary.entryName(entry))
    } else {
      dismiss()
    }
  }

  // Long-press in the drawer: put the app on the home screen
  // (omamobile.home), on the page it shows, and go there, as on Android.
  // Through IPC, like the switcher: a plugin only summons its own panels.
  function addToHome(entry) {
    if (!entry) return
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call",
                             "omamobile.home", "addApp", String(entry.id)])
    dismiss()
  }

  function askAgent(prompt) {
    var text = String(prompt || "").trim()
    if (!text) return "empty"
    if (!hasAgent) {
      Util.execArgv(LauncherModel.PICK_AGENT_ARGV)
      dismiss()
      return "pick-agent"
    }
    Util.execArgv(LauncherModel.promptArgv(text))
    dismiss()
    return "ok"
  }

  // Enter: the agent when the text reads as a prompt, else the top app.
  function activate() {
    if (!hasQuery) return
    if (promptMode || apps.length === 0) askAgent(query)
    else launchApp(apps[0])
  }

  // ---------------------------------------------------------------- desktop menu

  // Desktop mode's menu: a grid, A–Z until something is typed (then ranked
  // as on the phone), walked with the arrow keys.
  readonly property int desktopColumns: 6
  property int desktopIndex: 0
  readonly property color menuBackground: Commons.Color.menu.background
  readonly property var desktopApps: {
    if (hasQuery || !appLibrary) return apps
    var lib = appLibrary
    return apps.slice().sort(function(a, b) {
      return String(lib.entryName(a)).localeCompare(String(lib.entryName(b)), undefined, { sensitivity: "base" })
    })
  }
  onDesktopAppsChanged: desktopIndex = 0

  function moveDesktop(step) {
    var count = desktopApps.length
    if (count === 0) return
    desktopIndex = Math.max(0, Math.min(count - 1, desktopIndex + step))
    desktopGrid.positionViewAtIndex(desktopIndex, GridView.Contain)
  }

  function activateDesktop() {
    if (hasQuery && (promptMode || desktopApps.length === 0)) askAgent(query)
    else if (desktopApps.length > 0) launchApp(desktopApps[Math.min(desktopIndex, desktopApps.length - 1)])
  }

  // ---------------------------------------------------------------- lifecycle

  // `shell summon omamobile.launcher '{"query":"..."}'` opens the
  // drawer, optionally pre-filled.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    query = typeof payload.query === "string" ? payload.query : ""
    if (appLibrary) appLibrary.refreshIcons()
    refreshApps()
    opened = true
  }

  // Host-initiated close (`shell hide`).
  function close() {
    opened = false
    query = ""
    launchSplash.reset()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function expand() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
    else open("{}")
  }

  // `shell call omamobile.launcher <method> <arg>` entry points.
  function search(text) {
    if (!opened) expand()
    query = String(text || "")
    return JSON.stringify({ mode: promptMode ? "agent" : "apps", apps: apps.slice(0, 8).map(function(e) { return e.id }) })
  }

  function ask(prompt) { return askAgent(prompt) }

  function state() {
    return JSON.stringify({
      opened: opened,
      query: query,
      mode: hasQuery ? (promptMode ? "agent" : "apps") : "idle",
      apps: apps.length,
      library: shell && shell.appLibrary ? "host" : (appLibrary ? "local" : "none"),
      agent: agentId,
      command: hasAgent ? LauncherModel.promptArgv("<prompt>") : LauncherModel.PICK_AGENT_ARGV
    })
  }

  // Anything that opens a window (an app, the screensaver) closes the drawer,
  // as on Android: left open, it stays on top and keeps the keyboard focus.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.opened && event && event.name === "openwindow") root.dismiss()
    }
  }

  // ---------------------------------------------------------------- geometry

  readonly property color foreground: Commons.Color.menu.text
  readonly property int touch: Math.max(44, Style.space(44))
  readonly property int inputHeight: Math.max(48, Style.space(48))
  // The dock: Android's gesture bar by default (a handle; swipe up for the
  // drawer, further for recent apps, tap for home), or the search pill
  // ("dock": "search" in the plugin's settings).
  readonly property bool gestureDock: settings.dock !== "search"
  // The drawer's input row keeps the search pill's height either way.
  readonly property int inputRowHeight: inputHeight + Style.spacing.xxl * 2
  readonly property int dockHeight: gestureDock ? Math.max(28, Style.space(28)) : inputRowHeight

  // As the switcher's Home: the home screen (an empty workspace) on its home page.
  function goHome() {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"empty\" })"])
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call", "omamobile.home", "goHome", ""])
  }

  function showRecents() {
    // Through the CLI, like Omarchy's background does: a plugin may only
    // summon panels it owns, and the switcher is its own plugin.
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.switcher", "{}"])
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // ---------------------------------------------------------------- dock

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      // Hidden while the drawer is open, so the on-screen keyboard takes the
      // bottom edge and the drawer's input sits right above it.
      visible: !root.opened && !root.desktopMode
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.dockHeight
      exclusionMode: ExclusionMode.Auto
      // The gesture bar is only its handle, on the wallpaper (or the app above it).
      color: root.gestureDock ? "transparent" : Commons.Color.bar.background
      WlrLayershell.namespace: "omamobile-dock"
      // Bottom, not Top: its exclusive zone still keeps windows off it, and
      // fullscreen windows (the screensaver, video) cover it. On Top it was
      // drawn over a fullscreen window when it re-mapped after the drawer.
      WlrLayershell.layer: WlrLayer.Bottom

      // The gesture bar: swipe up for the drawer, a long swipe (a quarter of
      // the screen; the touch stays with this surface past its edge) for
      // recent apps (omamobile.switcher), a tap for home. The search pill:
      // any swipe up for recent apps, a tap for the drawer.
      Item {
        id: dockArea
        anchors.fill: parent
        readonly property real longSwipe: Math.max(120, (modelData.height || 960) / 4)

        DragHandler {
          target: null
          xAxis.enabled: false
          property real swipeY: 0
          onActiveTranslationChanged: swipeY = activeTranslation.y
          onActiveChanged: {
            if (active) { swipeY = 0; return }
            if (swipeY >= -24) return
            if (!root.gestureDock || -swipeY >= dockArea.longSwipe) root.showRecents()
            else root.expand()
          }
        }

        TapHandler {
          enabled: root.gestureDock
          onTapped: root.goHome()
        }

        Rectangle {
          visible: root.gestureDock
          anchors.centerIn: parent
          width: Math.max(96, Style.space(108))
          height: Math.max(4, Style.space(4))
          radius: height / 2
          color: root.foreground
          opacity: 0.7
        }

        SearchPill {
          visible: !root.gestureDock
          anchors.fill: parent
          anchors.margins: Style.spacing.xxl
          placeholder: (root.hasAgent ? "Search apps or ask " + root.agentName + "…" : "Search apps…")
          onTapped: root.expand()
        }
      }
    }
  }

  // ---------------------------------------------------------------- drawer

  PanelWindow {
    id: drawer

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: fit between the bar and the on-screen keyboard, like Android's
    // adjustResize.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-launcher"
    WlrLayershell.layer: WlrLayer.Top
    // OnDemand, not Exclusive: Hyprland sends no touch to other layers while
    // one holds exclusive focus, and that includes the on-screen keyboard.
    // In desktop mode there is no on-screen keyboard, and the menu should
    // take typing at once without a click first: Exclusive.
    WlrLayershell.keyboardFocus: !root.opened ? WlrKeyboardFocus.None
      : root.desktopMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    // The keyboard comes up only to type: on a tap in the input, or when the
    // drawer opens with text already in it. Opened by a swipe, the list shows
    // whole, as in the design.
    // In desktop mode the search takes the keyboard at once: there is no
    // on-screen keyboard to raise, and typing is how a desktop launcher works.
    onVisibleChanged: {
      if (visible && root.desktopMode) Qt.callLater(function() { desktopInput.forceActiveFocus() })
      else if (visible && root.hasQuery) Qt.callLater(function() { input.forceActiveFocus() })
    }

    // The tapped app's splash over the drawer (launchApp). A new window
    // closes the drawer anyway (onRawEvent above); a focused one, a tap or
    // the timeout closes it here.
    LaunchSplash {
      id: launchSplash
      anchors.fill: parent
      z: 1000
      onFinished: root.dismiss()
    }

    Rectangle {
      id: sheet
      visible: !root.desktopMode
      width: parent.width
      height: parent.height
      y: Math.round((1 - root.reveal) * Style.space(80))
      opacity: root.reveal
      color: Commons.Color.menu.background

      // ---------- Header: the title and a collapse control
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: Style.spacing.sm
        height: root.touch + Style.spacing.lg

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.hasQuery ? (root.apps.length === 1 ? "1 app" : root.apps.length + " apps") : "Apps"
          color: root.foreground
          font.family: root.textFont
          font.pixelSize: 34
          font.weight: Font.Bold
        }

        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: root.touch
          height: root.touch
          iconText: "󰅀"
          iconSize: Style.font.iconLarge
          foreground: root.foreground
          onClicked: root.dismiss()
        }
      }

      // ---------- The one input, under the title
      Item {
        id: inputRow
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(root.touch, Style.space(52)) + Style.spacing.sm * 2

        TextField {
          id: input
          anchors.fill: parent
          anchors.leftMargin: 22
          anchors.rightMargin: 22
          anchors.topMargin: Style.spacing.sm
          anchors.bottomMargin: Style.spacing.sm
          verticalAlignment: TextInput.AlignVCenter
          font.family: root.textFont
          font.pixelSize: 16
          // A filled, borderless field, as in the design.
          background: Rectangle {
            radius: 16
            color: root.darkSheet ? Qt.rgba(1, 1, 1, input.activeFocus ? 0.11 : 0.07) : Qt.rgba(0, 0, 0, input.activeFocus ? 0.08 : 0.05)
          }
          leftPadding: Style.spacing.controlPaddingX + Style.font.iconLarge + Style.spacing.xl
          placeholderText: root.hasAgent ? "Search apps or ask " + root.agentName + "…" : "Search apps and commands"
          foreground: root.foreground
          text: root.query
          onTextEdited: root.query = text
          Keys.onReturnPressed: root.activate()
          Keys.onEnterPressed: root.activate()
          Keys.onEscapePressed: {
            if (root.query) root.query = ""
            else root.dismiss()
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.promptMode ? "󰚩" : "󰍉"
            color: root.promptMode ? Commons.Color.accent : Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }
        }
      }

      // ---------- Ask the agent, while typing
      BorderSurface {
        id: askRow
        visible: root.hasQuery
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: inputRow.bottom
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        anchors.topMargin: Style.spacing.sm
        height: visible ? Math.max(root.touch, Style.space(52)) : 0
        radius: Style.cornerRadius
        color: askTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : root.promptMode ? Commons.Color.menu.selectedBackground : "transparent"
        borderSpec: root.promptMode
          ? Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth))
          : Border.controlSpec("normal", root.foreground, Commons.Color.accent)

        Item {
          id: askIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.xl
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.display
          height: Style.font.display

          Image {
            id: askImage
            anchors.fill: parent
            source: root.agentIcon
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
          }

          Text {
            anchors.centerIn: parent
            visible: askImage.status !== Image.Ready
            textFormat: Text.PlainText
            text: "󰚩"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.display
          }
        }

        Column {
          anchors.left: askIcon.right
          anchors.leftMargin: Style.spacing.xl
          anchors.right: askEnter.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasAgent ? "Ask " + root.agentName : "Choose your agent"
            color: root.promptMode ? Commons.Color.menu.selectedText : root.foreground
            font.family: root.textFont
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.query.trim()
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.textFont
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          id: askEnter
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xl
          anchors.verticalCenter: parent.verticalCenter
          visible: root.promptMode
          textFormat: Text.PlainText
          text: "󰌑"
          color: Commons.Color.menu.selectedText
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }

        MouseArea {
          id: askTouch
          anchors.fill: parent
          onClicked: root.askAgent(root.query)
        }
      }

      // ---------- Recent apps, then every app as a list
      ListView {
        id: list
        anchors.top: askRow.visible ? askRow.bottom : inputRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.spacing.md
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.apps
        opacity: root.promptMode ? 0.5 : 1

        header: Column {
          width: list.width
          spacing: Style.spacing.md
          bottomPadding: Style.spacing.sm

          SectionLabel {
            visible: !root.hasQuery && root.recentEntries.length > 0
            text: "RECENT"
          }
          Row {
            visible: !root.hasQuery && root.recentEntries.length > 0
            width: parent.width
            Repeater {
              model: root.hasQuery ? [] : root.recentEntries
              delegate: AppCell {
                required property var modelData
                width: list.width / root.columns
                height: Math.max(96, Style.space(100))
                entry: modelData
                onTapped: root.launchApp(modelData)
                onHeld: root.addToHome(modelData)
              }
            }
          }
          SectionLabel {
            visible: !root.hasQuery
            text: "ALL APPS"
          }
        }

        delegate: AppRow {
          required property var modelData
          required property int index
          width: list.width
          entry: modelData
          last: index === root.apps.length - 1
          highlighted: index === 0 && root.hasQuery && !root.promptMode
          onTapped: root.launchApp(modelData)
          onHeld: root.addToHome(modelData)
        }
      }

      Text {
        anchors.centerIn: list
        visible: root.hasQuery && root.apps.length === 0
        textFormat: Text.PlainText
        text: "No apps match"
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.textFont
        font.pixelSize: Style.font.body
      }
    }

    // ---------- Desktop mode: a menu over the dock instead of the sheet
    // (docs/design/desktop-mode/launcher.png). The window already sits
    // between the bar and the desktop's dock; a click beside the menu closes it.
    Rectangle {
      anchors.fill: parent
      visible: root.desktopMode
      color: Qt.rgba(0, 0, 0, 0.4 * root.reveal)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Rectangle {
      id: menu
      visible: root.desktopMode
      width: Math.min(660, parent.width - 32)
      height: Math.min(500, parent.height - 24)
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - height - 8 + Math.round((1 - root.reveal) * 24)
      opacity: root.reveal
      radius: 22
      color: Qt.rgba(root.menuBackground.r, root.menuBackground.g, root.menuBackground.b, 0.97)
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.08)

      // Swallows clicks between the cells, so they don't reach the dim layer.
      MouseArea { anchors.fill: parent }

      TextField {
        id: desktopInput
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 18
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 42
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.textFont
        font.pixelSize: 14
        background: Rectangle {
          radius: 13
          color: Util.alpha(root.foreground, 0.07)
          border.width: 1
          border.color: desktopInput.activeFocus ? Util.alpha(Commons.Color.accent, 0.5) : "transparent"
        }
        leftPadding: 42
        placeholderText: root.hasAgent ? "Search apps or ask " + root.agentName + "…" : "Search apps…"
        foreground: root.foreground
        text: root.query
        onTextEdited: root.query = text
        Keys.onReturnPressed: root.activateDesktop()
        Keys.onEnterPressed: root.activateDesktop()
        Keys.onEscapePressed: {
          if (root.query) root.query = ""
          else root.dismiss()
        }
        Keys.onUpPressed: root.moveDesktop(-root.desktopColumns)
        Keys.onDownPressed: root.moveDesktop(root.desktopColumns)
        Keys.onLeftPressed: root.moveDesktop(-1)
        Keys.onRightPressed: root.moveDesktop(1)
        Keys.onTabPressed: root.moveDesktop(1)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.promptMode ? "󰚩" : "󰍉"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: 17
        }
      }

      // Text that reads as a prompt: Enter asks the agent.
      Rectangle {
        id: desktopAsk
        visible: root.hasQuery && (root.promptMode || root.desktopApps.length === 0)
        anchors.top: desktopInput.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: visible ? 44 : 0
        radius: 12
        color: root.promptMode ? Commons.Color.menu.selectedBackground : Util.alpha(root.foreground, 0.05)

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (root.hasAgent ? "Ask " + root.agentName : "Choose your agent") + "  ·  " + root.query.trim()
          color: root.promptMode ? Commons.Color.menu.selectedText : root.foreground
          font.family: root.textFont
          font.pixelSize: 13
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.askAgent(root.query)
        }
      }

      Item {
        id: desktopLabel
        anchors.top: desktopAsk.visible ? desktopAsk.bottom : desktopInput.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: 22

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.hasQuery ? "RESULTS" : "ALL APPS"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.textFont
          font.pixelSize: 11
          font.weight: Font.Bold
          font.letterSpacing: 1.6
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.desktopApps.length + (root.desktopApps.length === 1 ? " app" : " apps") + (root.hasQuery ? "" : " · A–Z")
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.textFont
          font.pixelSize: 11
        }
      }

      GridView {
        id: desktopGrid
        anchors.top: desktopLabel.bottom
        anchors.bottom: desktopFoot.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: Math.floor(width / root.desktopColumns)
        cellHeight: 92
        model: root.desktopApps
        currentIndex: root.desktopIndex
        highlightFollowsCurrentItem: false
        opacity: root.promptMode ? 0.5 : 1

        delegate: DesktopCell {
          required property var modelData
          required property int index
          width: desktopGrid.cellWidth
          height: desktopGrid.cellHeight
          entry: modelData
          highlighted: index === root.desktopIndex && !root.promptMode
          onHovered: root.desktopIndex = index
          onTapped: root.launchApp(modelData)
        }

        Text {
          anchors.centerIn: parent
          visible: root.hasQuery && root.desktopApps.length === 0 && !desktopAsk.visible
          textFormat: Text.PlainText
          text: "No apps match"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.textFont
          font.pixelSize: 13
        }
      }

      Rectangle {
        id: desktopFoot
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: 44
        color: "transparent"

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.08)
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14
          Repeater {
            model: [["↑ ↓ ← →", "select"], ["Enter", root.promptMode ? "ask" : "open"], ["Esc", "close"]]
            delegate: Row {
              required property var modelData
              spacing: 6
              Rectangle {
                width: keyText.implicitWidth + 12
                height: 20
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: Util.alpha(root.foreground, 0.07)
                Text {
                  id: keyText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: modelData[0]
                  color: Qt.darker(root.foreground, 1.2)
                  font.family: root.textFont
                  font.pixelSize: 11
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData[1]
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.textFont
                font.pixelSize: 11
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Type to search"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.textFont
          font.pixelSize: 11
        }
      }
    }
  }

  // ---------------------------------------------------------------- parts

  // The collapsed bar: looks like the input it turns into.
  component SearchPill: BorderSurface {
    id: pill

    property string placeholder: ""
    signal tapped()

    radius: Style.cornerRadius
    color: pillTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : Style.normalFill
    borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

    Text {
      id: pillIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX + pill.borderLeft
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰍉"
      color: Qt.darker(root.foreground, 1.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    Text {
      anchors.left: pillIcon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: pill.placeholder
      color: Qt.darker(root.foreground, 1.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    // A TapHandler, not a MouseArea: it lets go once the touch turns into a
    // drag, so the dock's swipe-up (recent apps) still sees it.
    TapHandler {
      id: pillTouch
      onTapped: pill.tapped()
    }
  }

  // A small capital heading over a section of the drawer.
  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.textFont
    font.pixelSize: 13
    font.weight: Font.DemiBold
    font.letterSpacing: 0.6
  }

  // One app in the list: icon, name, and its generic name on the right.
  component AppRow: Item {
    id: row

    property var entry: null
    property bool highlighted: false
    property bool last: false
    signal tapped()
    signal held()

    height: Math.max(64, Style.space(64))

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 2
      anchors.bottomMargin: 2
      radius: Style.cornerRadius
      color: rowTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
        : row.highlighted ? Commons.Color.menu.selectedBackground : "transparent"
    }

    Image {
      id: rowIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(40, Style.space(44))
      height: width
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: root.appLibrary && row.entry ? root.appLibrary.iconSource(row.entry.icon) : ""
    }

    Text {
      id: rowName
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: rowGeneric.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.appLibrary && row.entry ? root.appLibrary.entryName(row.entry) : ""
      color: row.highlighted ? Commons.Color.menu.selectedText : root.foreground
      font.family: root.textFont
      font.pixelSize: 16
      elide: Text.ElideRight
    }

    Text {
      id: rowGeneric
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, row.width * 0.4)
      textFormat: Text.PlainText
      text: root.appLibrary && row.entry ? LauncherModel.sideText(root.appLibrary.entryName(row.entry), root.appLibrary.entrySubtext(row.entry)) : ""
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.textFont
      font.pixelSize: 13
      elide: Text.ElideRight
    }

    Rectangle {
      visible: !row.last
      anchors.bottom: parent.bottom
      anchors.left: rowName.left
      anchors.right: parent.right
      height: 1
      color: Util.alpha(root.foreground, 0.08)
    }

    MouseArea {
      id: rowTouch
      anchors.fill: parent
      onClicked: row.tapped()
      onPressAndHold: row.held()
    }
  }

  // One app in desktop mode's menu: icon over a one-line name; the pointer
  // selects it, as the arrow keys do.
  component DesktopCell: Item {
    id: dcell

    property var entry: null
    property bool highlighted: false
    signal tapped()
    signal hovered()

    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      radius: 14
      color: dcellMouse.pressed ? Util.alpha(root.foreground, 0.14)
        : dcell.highlighted ? Util.alpha(root.foreground, 0.08) : "transparent"
    }

    Image {
      id: dcellIcon
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 14
      width: 42
      height: 42
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: root.appLibrary && dcell.entry ? root.appLibrary.iconSource(dcell.entry.icon) : ""
    }

    Text {
      anchors.top: dcellIcon.bottom
      anchors.topMargin: 8
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.appLibrary && dcell.entry ? root.appLibrary.entryName(dcell.entry) : ""
      color: root.foreground
      opacity: dcell.highlighted ? 1 : 0.8
      font.family: root.textFont
      font.pixelSize: 12
      elide: Text.ElideRight
    }

    MouseArea {
      id: dcellMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: dcell.hovered()
      onClicked: dcell.tapped()
    }
  }

  // One app in the grid: icon over a two-line name.
  component AppCell: Item {
    id: cell

    property var entry: null
    property bool highlighted: false
    signal tapped()
    signal held()

    BorderSurface {
      anchors.fill: parent
      anchors.margins: Style.spacing.xs
      radius: Style.cornerRadius
      color: cellTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
        : cell.highlighted ? Commons.Color.menu.selectedBackground : "transparent"
      borderSpec: cell.highlighted ? Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth)) : Border.none()
    }

    Image {
      id: icon
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.xl
      width: Math.max(40, Style.space(44))
      height: width
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      // Decode at physical pixels so PNG icons stay sharp at scale 3.
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: root.appLibrary && cell.entry ? root.appLibrary.iconSource(cell.entry.icon) : ""
    }

    Text {
      anchors.top: icon.bottom
      anchors.topMargin: Style.spacing.md
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.sm
      anchors.rightMargin: Style.spacing.sm
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.appLibrary && cell.entry ? root.appLibrary.entryName(cell.entry) : ""
      color: cell.highlighted ? Commons.Color.menu.selectedText : root.foreground
      font.family: root.textFont
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    MouseArea {
      id: cellTouch
      anchors.fill: parent
      onClicked: cell.tapped()
      onPressAndHold: cell.held()
    }
  }
}
