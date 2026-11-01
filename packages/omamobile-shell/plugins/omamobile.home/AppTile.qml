// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// An app shortcut: icon over its name, launched the way the app drawer
// launches apps (omamobile-launch: uwsm-app -- gtk-launch on a new empty
// workspace, or the app's open window focused).
// An app that is no longer installed stays, dimmed, until it is removed in
// edit mode (it may come back with its package).
Item {
  id: tile

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property var desktopEntry: home && entry ? home.entryFor(entry.app) : null
  readonly property bool missing: !desktopEntry
  readonly property var library: home ? home.appLibrary : null

  opacity: missing ? 0.45 : 1

  Rectangle {
    anchors.centerIn: icon
    width: icon.width + 12
    height: width
    radius: width * 0.3
    color: touch.pressed ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
  }

  Image {
    id: icon
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round((tile.height - height - 7 - name.implicitHeight) / 2)
    // The design's proportion: a 64 px icon on a 113 px row.
    width: Math.min(64, Math.max(36, Math.min(tile.width * 0.6, tile.height * 0.57)))
    height: width
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: tile.library ? tile.library.iconSource(tile.desktopEntry ? tile.desktopEntry.icon : "") : ""
  }

  Text {
    id: name
    anchors.top: icon.bottom
    anchors.topMargin: 7
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.xs
    anchors.rightMargin: Style.spacing.xs
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: tile.missing ? (tile.entry ? tile.entry.app : "") : (tile.library ? tile.library.entryName(tile.desktopEntry) : tile.desktopEntry.name)
    color: tile.home ? tile.home.foreground : "white"
    // An outline keeps the name readable on a light wallpaper; it costs
    // nothing like a blur or a drop shadow would.
    style: Text.Outline
    styleColor: Util.alpha(Commons.Color.menu.background, 0.55)
    font.family: tile.home && tile.home.textFont ? tile.home.textFont : Style.font.family
    font.pixelSize: 13
    font.weight: Font.Medium
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  MouseArea {
    id: touch
    anchors.fill: parent
    enabled: !tile.editing
    onClicked: {
      if (!tile.home) return
      if (tile.missing) tile.home.flash("Not installed: hold to edit")
      else tile.home.launch(tile.entry.app)
    }
  }
}
