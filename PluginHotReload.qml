// PluginHotReload.qml: live-reload host for developing MuseScore 4 plugins.
// Loads a QML file (the "target") into a dialog and reloads it on save,
// with a separate debug window for errors, a log, and reload controls.
// See README.md for usage and the requirements for the target file.
//
//   Dialog       -> mainItem  : your target only, at your plugin's size
//   Debug window -> debugItem : path, reload, auto-reload, errors, log
//
// Written for MuseScore 4.4+. For 4.0-4.3, change the imports "Muse.Ui" to
// "MuseScore.Ui" and "Muse.UiComponents" to "MuseScore.UiComponents".
//
// The debug window is a Qt.Dialog with a stay-on-top hint so that it floats
// above MuseScore when MuseScore is in full screen on macOS.

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import MuseScore 3.0
import FileIO 3.0
import Muse.Ui 1.0
import Muse.UiComponents 1.0

MuseScore {
    id: host
    version: "1.0"
    title: "Plugin Hot Reload"
    description: "Loads a QML file into a dialog and reloads it on save, with a separate debug window."
    categoryCode: "development"
    pluginType: "dialog"
    requiresScore: false

    // MATCH THESE to the plugin you are developing.
    width: 400
    height: 600

    // ---------- state ----------
    property string targetPath: ""      // full path to the QML file to load
    property var target: null           // the currently loaded object
    property string lastSource: ""
    property string lastError: ""
    property int reloadCount: 0
    property bool autoReload: true
    property string logText: ""

    readonly property bool isMac: Qt.platform.os === "osx" || Qt.platform.os === "macos"
    readonly property string debugKeyHint: isMac ? "Control+D" : "F12"

    FileIO { id: sourceIO }

    // ---------- functions ----------

    function timeStamp() {
        var d = new Date()
        function p(n) { return (n < 10 ? "0" : "") + n }
        return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }

    function log() {
        var parts = []
        for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i]
            if (a !== null && typeof a === "object") {
                try { parts.push(JSON.stringify(a)) } catch (e) { parts.push(String(a)) }
            } else {
                parts.push(String(a))
            }
        }
        var msg = parts.join(" ")
        var line = timeStamp() + "  " + msg
        logText = logText ? (logText + "\n" + line) : line
        if (logText.length > 20000) logText = logText.slice(-15000)
        console.log("[HotReload] " + msg)
    }

    // Accepts pasted paths: trims spaces, strips quotes and a file:// prefix.
    function normalizePath(p) {
        var q = String(p).trim().replace(/^["']|["']$/g, "")
        if (q.indexOf("file://") === 0) q = q.slice(7)
        return q
    }

    function toFileUrl(p) {
        var q = p.replace(/\\/g, "/")
        return (q.charAt(0) === "/") ? ("file://" + q) : ("file:///" + q)
    }

    function readSource() {
        if (targetPath === "") return ""
        try {
            sourceIO.source = targetPath
            var s = sourceIO.read()
            return (s === undefined || s === null) ? "" : s
        } catch (e) {
            return ""
        }
    }

    function formatError(e) {
        if (e && e.qmlErrors && e.qmlErrors.length) {
            var out = []
            for (var i = 0; i < e.qmlErrors.length; i++) {
                var q = e.qmlErrors[i]
                out.push("line " + q.lineNumber + ":" + q.columnNumber + "  " + q.message)
            }
            return out.join("\n")
        }
        return String(e)
    }

    function unload() {
        if (!target) return
        try {
            if (typeof target.dispose === "function") target.dispose()
        } catch (e) {
            log("ERROR in dispose():", formatError(e))
        }
        target.destroy()
        target = null
    }

    function reload(reason) {
        if (targetPath === "") {
            lastError = "Enter the path to your QML file in the debug window."
            log("ERROR:", lastError)
            return
        }

        var src = readSource()
        if (src === "") {
            lastError = "Cannot read, or file is empty: " + targetPath
            log("ERROR:", lastError)
            return
        }
        lastSource = src
        unload()

        try {
            target = Qt.createQmlObject(src, targetHost, toFileUrl(targetPath))
            target.anchors.fill = targetHost
        } catch (e) {
            target = null
            lastError = formatError(e)
            log("COMPILE ERROR (" + reason + "):\n" + lastError)
            return
        }

        reloadCount++
        lastError = ""
        log("Loaded #" + reloadCount + " (" + reason + ")")

        try {
            if (typeof target.run === "function") target.run()
        } catch (e) {
            lastError = "run(): " + formatError(e)
            log("ERROR in", lastError)
        }
    }

    // Polls the file twice a second and reloads when the content changes.
    Timer {
        interval: 500
        repeat: true
        running: host.autoReload
        onTriggered: {
            var s = host.readSource()
            if (s !== "" && s !== host.lastSource) host.reload("file changed")
        }
    }

    onRun: {
        debugWindow.show()
        reload("startup")
    }

    Component.onDestruction: {
        unload()
        debugWindow.close()
    }

    // =====================================================================
    // DIALOG -> mainItem (the target only)
    // =====================================================================

    Item {
        id: mainItem
        anchors.fill: parent

        Item {
            id: targetHost
            anchors.fill: parent
        }

        StyledTextLabel {
            anchors.centerIn: parent
            visible: host.target === null
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.6
            text: "Nothing loaded.\nOpen the debug window: " + host.debugKeyHint
        }

        Shortcut {
            sequences: host.isMac ? ["Meta+D", "F12"] : ["Ctrl+Shift+D", "F12"]
            onActivated: {
                debugWindow.show()
                debugWindow.raise()
                debugWindow.requestActivate()
            }
        }
    }

    // =====================================================================
    // DEBUG WINDOW -> debugItem (controls, errors, log)
    // =====================================================================

    Window {
        id: debugWindow
        title: "Plugin Hot Reload Debug"
        width: 560
        height: 420
        visible: false
        flags: Qt.Dialog | Qt.WindowStaysOnTopHint
        color: ui.theme.backgroundPrimaryColor   // match MuseScore's theme

        Item {
            id: debugItem
            anchors.fill: parent

            // ---- inputs ----
            property string logText: host.logText
            property string errorText: host.lastError
            property int loads: host.reloadCount
            property string path: host.targetPath
            property bool autoReload: host.autoReload

            // ---- outputs ----
            signal reloadRequested()
            signal clearRequested()
            signal autoReloadChangeRequested(bool on)
            signal pathChangeRequested(string newPath)

            onReloadRequested: host.reload("manual")
            onClearRequested: host.logText = ""
            onAutoReloadChangeRequested: host.autoReload = on
            onPathChangeRequested: {
                host.targetPath = host.normalizePath(newPath)
                host.lastSource = ""    // force a reload even if content matches
                host.reload("path changed")
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    FlatButton {
                        text: "Reload"
                        accentButton: true
                        onClicked: debugItem.reloadRequested()
                    }

                    CheckBox {
                        text: "Auto-reload on save"
                        checked: debugItem.autoReload
                        // MuseScore's CheckBox doesn't toggle itself; flip the value.
                        onClicked: debugItem.autoReloadChangeRequested(!checked)
                    }

                    Item { Layout.fillWidth: true }

                    FlatButton {
                        text: "Clear log"
                        onClicked: debugItem.clearRequested()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledTextLabel {
                        text: "Loads: " + debugItem.loads
                    }

                    TextInputField {
                        Layout.fillWidth: true
                        hint: "/path/to/YourPlugin.qml"
                        currentText: debugItem.path
                        onTextEditingFinished: function(newTextValue) {
                            debugItem.pathChangeRequested(newTextValue)
                        }
                    }
                }

                // Error banner
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: errLabel.implicitHeight + 16
                    visible: debugItem.errorText !== ""
                    color: "transparent"
                    border.color: "#d9534f"
                    border.width: 1
                    radius: 3

                    StyledTextLabel {
                        id: errLabel
                        anchors.fill: parent
                        anchors.margins: 8
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.Wrap
                        color: "#e05a55"
                        font.family: "monospace"
                        text: debugItem.errorText
                    }
                }

                // Log
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: ui.theme.textFieldColor
                    border.color: ui.theme.strokeColor
                    border.width: 1
                    radius: 3

                    Flickable {
                        id: logFlick
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        contentWidth: width
                        contentHeight: logEdit.paintedHeight

                        TextEdit {
                            id: logEdit
                            width: logFlick.width
                            text: debugItem.logText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            color: ui.theme.fontPrimaryColor
                            selectionColor: ui.theme.accentColor
                            font.family: "monospace"
                            font.pixelSize: ui.theme.bodyFont.pixelSize
                            onTextChanged: logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)
                        }
                    }
                }
            }
        }
    }
}
