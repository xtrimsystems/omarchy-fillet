import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Third-party widgets only get a facade of the bar, but this item is rendered
// inside the bar's scene, so it can walk up to the bar window and down to
// every panel widget's popup and restyle it in place. Popups are matched by
// shape (cardOrigin/gap/borderSpec), which covers anything built on Omarchy's
// KeyboardPanel, first- or third-party.
Item {
    id: root

    property var bar: null
    property string moduleName: ""
    property var settings: ({})

    implicitWidth: 0
    implicitHeight: 0

    readonly property int seamRadius: Math.max(4, Number(setting("seamRadius", 12)))
    readonly property bool outline: boolSetting("outline", true)
    readonly property bool barEdge: boolSetting("barEdge", true)
    readonly property string barPos: bar ? String(bar.position) : "top"
    readonly property bool horizontalBar: barPos === "top" || barPos === "bottom"
    readonly property var barWindow: root.QsWindow.window
    readonly property int lineWidth: Math.max(1, Border.top(Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))))
    property var patched: []

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function boolSetting(name, fallback) {
        var value = setting(name, fallback)
        return value !== false && String(value) !== "false"
    }

    function sceneRoot() {
        var p = root
        while (p.parent) p = p.parent
        return p
    }

    function isPanelOwner(o) {
        return o && ("ipcTarget" in o) && ("opened" in o) && ("controller" in o)
    }

    function isPopup(o) {
        return o && ("cardOrigin" in o) && ("gap" in o) && ("contentItem" in o) && ("borderSpec" in o)
    }

    function collectPopups(owner, out) {
        var res = owner.resources
        if (!res) return
        for (var i = 0; i < res.length; i++) if (isPopup(res[i])) out.push(res[i])
    }

    function walk(item, out) {
        if (!item) return
        if (isPanelOwner(item)) collectPopups(item, out)
        var kids = item.children
        if (!kids) return
        for (var i = 0; i < kids.length; i++) walk(kids[i], out)
    }

    // A window that has never been mapped has no contentItem yet; its declared
    // children are still reachable through the `data` list.
    function findCard(popup) {
        var lists = []
        if (popup.contentItem && popup.contentItem.children) lists.push(popup.contentItem.children)
        if (popup.data) lists.push(popup.data)
        for (var l = 0; l < lists.length; l++) {
            var list = lists[l]
            for (var i = 0; i < list.length; i++) {
                var k = list[i]
                if (k && ("borderSpec" in k) && ("contentTopInset" in k)) return k
            }
        }
        return null
    }

    function patch(popup) {
        for (var i = 0; i < patched.length; i++) if (patched[i] === popup) return
        var card = findCard(popup)
        if (!card) return
        var strokeWidth = Math.max(1, Border.top(popup.borderSpec))

        popup.gap = 0
        popup.margin = Style.gapsOut + root.seamRadius
        card.color = "transparent"
        card.borderSpec = Border.none()
        card.padding = popup.padding + strokeWidth

        var s = silhouette.createObject(card, {
            panel: popup,
            card: card,
            seamRadius: root.seamRadius,
            strokeWidth: root.outline ? strokeWidth : 0
        })
        if (s) patched.push(popup)
    }

    function scan() {
        var found = []
        walk(sceneRoot(), found)
        for (var i = 0; i < found.length; i++) patch(found[i])
    }

    Component {
        id: silhouette
        Silhouette { }
    }

    // Widgets load asynchronously: sweep a few times after start-up, then on
    // every popout change (the facade flips activePopout even for foreign
    // popouts), which patches late-created panels before their first frame.
    Timer {
        id: sweep
        property int pass: 0
        interval: 400
        repeat: true
        running: root.bar !== null
        onTriggered: {
            root.scan()
            if (++pass >= 8) running = false
        }
    }

    Connections {
        target: root.bar
        ignoreUnknownSignals: true
        function onActivePopoutChanged() { root.scan() }
        function onLayoutConfigChanged() { sweep.pass = 0; sweep.running = true }
    }

    // Straddles the bar edge by half the width, like a stroke centered on the
    // popup outline, so line and fillet curves meet flush at the tips.
    PanelWindow {
        screen: root.barWindow ? root.barWindow.screen : null
        visible: root.barEdge && root.horizontalBar && root.barWindow !== null
        color: Color.popups.border
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.lineWidth

        anchors {
            left: true
            right: true
            top: root.barPos === "top"
            bottom: root.barPos === "bottom"
        }
        margins {
            top: root.barPos === "top" ? (root.bar ? root.bar.barSize : 0) - Math.floor(root.lineWidth / 2) : 0
            bottom: root.barPos === "bottom" ? (root.bar ? root.bar.barSize : 0) - Math.floor(root.lineWidth / 2) : 0
        }

        WlrLayershell.namespace: "fillet-bar-edge"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {}
    }
}
