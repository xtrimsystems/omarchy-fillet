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
    readonly property bool hoverSwitch: boolSetting("hoverSwitch", false)
    readonly property bool attachMenu: boolSetting("attachMenu", false)
    readonly property string menuIcon: String(setting("menuIcon", "") || "")
    readonly property string menuIconFont: String(setting("menuIconFont", "") || "")
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

    function walk(item, out, menuButtons) {
        if (!item) return
        if (isPanelOwner(item)) collectPopups(item, out)
        else if (isMenuButton(item)) menuButtons.push(item)
        var kids = item.children
        if (!kids) return
        for (var i = 0; i < kids.length; i++) walk(kids[i], out, menuButtons)
    }

    function findDismissArea(popup) {
        var lists = []
        if (popup.contentItem && popup.contentItem.children) lists.push(popup.contentItem.children)
        if (popup.data) lists.push(popup.data)
        for (var l = 0; l < lists.length; l++) {
            var list = lists[l]
            for (var i = 0; i < list.length; i++) {
                var k = list[i]
                if (k && ("hoveringBar" in k) && typeof k.inBarRegion === "function" && typeof k.barPoint === "function") return k
            }
        }
        return null
    }

    // Some widgets keep their popup's owner as an invisible zero-size host
    // beside the visible bar button, so hit-test the button the popup is
    // anchored to rather than the owner.
    function popupAt(x, y) {
        for (var i = 0; i < patched.length; i++) {
            var p = patched[i]
            var a = p ? p.anchorItem : null
            if (!a || !a.visible || a.width <= 0) continue
            var pos = a.mapToItem(null, 0, 0)
            if (x >= pos.x && x < pos.x + a.width && y >= pos.y && y < pos.y + a.height) return p
        }
        return null
    }

    function openPopup(popup) {
        if (popup.owner && typeof popup.owner.open === "function") popup.owner.open()
        else popup.open = true
    }

    function hoverSwitchAt(popup, dismissArea, px, py) {
        if (!root.hoverSwitch || !popup.open) return
        if (!dismissArea.inBarRegion(px, py)) return
        var p = dismissArea.barPoint(px, py)
        var hit = popupAt(p.x, p.y)
        if (hit) {
            if (hit !== popup && !hit.open) openPopup(hit)
            return
        }
        if (root.attachMenu && menuShell && !menuOpen() && menuButtonAt(p.x, p.y)) {
            popup.close()
            menuShell.summon("omarchy.menu", "{\"menu\":\"root\"}")
        }
    }

    function menuHoverAt(win, x, y) {
        if (!root.hoverSwitch || !root.attachMenu || !menuOpen()) return
        if (!root.barWindow || !win.screen || !root.barWindow.screen || win.screen.name !== root.barWindow.screen.name) return
        var barSize = root.bar ? root.bar.barSize : 0
        var by = root.barPos === "bottom" ? y - (win.height - barSize) : y
        if (by < 0 || by >= barSize) return
        var hit = popupAt(x, by)
        if (!hit || hit.open) return
        if (typeof menuRoot.cancel === "function") menuRoot.cancel()
        else menuShell.hide("omarchy.menu")
        openPopup(hit)
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
        if (!s) return
        patched.push(popup)

        // While a popup is open its dismiss surface covers the bar, so bar
        // widgets never see hover; the surface's own pointer moves are the
        // only hover signal available.
        var dismissArea = findDismissArea(popup)
        if (dismissArea) dismissArea.positionChanged.connect(function(mouse) {
            root.hoverSwitchAt(popup, dismissArea, mouse.x, mouse.y)
        })
    }

    function scan() {
        var found = []
        var menuButtons = []
        walk(sceneRoot(), found, menuButtons)
        for (var i = 0; i < found.length; i++) patch(found[i])
        if (menuButtons.length > 0) menuButton = menuButtons[0]
        applyMenuIcon()
        if (root.attachMenu) patchMenu(findMenu(found))
    }

    // --- Omarchy menu ---------------------------------------------------------

    property var menuButton: null
    property var menuRoot: null
    property var menuShell: null
    property bool menuPatched: false
    property bool menuHoverHooked: false

    function menuOpen() {
        return !!menuRoot && menuRoot.opened === true
    }

    function menuButtonAt(x, y) {
        var b = menuButton
        if (!b || !b.visible || b.width <= 0) return false
        var pos = b.mapToItem(null, 0, 0)
        return x >= pos.x && x < pos.x + b.width && y >= pos.y && y < pos.y + b.height
    }

    Component {
        id: menuHoverArea
        MouseArea {
            property var win: null
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function(mouse) { root.menuHoverAt(win, mouse.x, mouse.y) }
        }
    }

    function isMenuButton(o) {
        return o && ("moduleName" in o) && String(o.moduleName) === "omarchy.menu" && ("bar" in o)
    }

    function applyMenuIcon() {
        var button = menuButton
        if (!button || !root.menuIcon) return
        var kids = button.children
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (!k || !("text" in k) || !("fontFamily" in k) || typeof k.triggerPress !== "function") continue
            if (k.text !== root.menuIcon) k.text = root.menuIcon
            var font = root.menuIconFont || (root.bar ? root.bar.fontFamily : "")
            if (font && k.fontFamily !== font) k.fontFamily = font
            return
        }
    }

    // The menu is loaded by the shell in its own window, outside any bar
    // scene. First-party widgets hold the real bar object, which leads to the
    // shell and its table of loaded panel plugins.
    function findMenu(popups) {
        for (var i = 0; i < popups.length; i++) {
            var owner = popups[i].owner
            var realBar = owner && owner.bar && ("shell" in owner.bar) && ("moduleSlots" in owner.bar) ? owner.bar : null
            if (!realBar || !realBar.shell) continue
            var loaders = realBar.shell.panelLoaders
            var loader = loaders ? loaders["omarchy.menu"] : null
            var menu = loader ? loader.item : null
            if (menu) {
                menuRoot = menu
                menuShell = realBar.shell
            }
            return menu
        }
        return null
    }

    function menuWindowOf(menu) {
        var res = menu ? menu.resources : null
        if (!res) return null
        for (var i = 0; i < res.length; i++) if (res[i] && ("cardTop" in res[i]) && ("effectiveCardTop" in res[i])) return res[i]
        return null
    }

    function menuParts(win) {
        var parts = { scrim: null, card: null, dismiss: null }
        var list = win.data
        if (!list) return parts
        for (var i = 0; i < list.length; i++) {
            var k = list[i]
            if (!k) continue
            if (("borderSpec" in k) && ("contentTopInset" in k)) parts.card = k
            else if (("pressed" in k) && ("hoverEnabled" in k)) parts.dismiss = k
            else if (("color" in k) && !("borderSpec" in k) && !parts.scrim) parts.scrim = k
        }
        return parts
    }

    function menuIconCenterX() {
        var b = menuButton
        if (!b || !b.visible || b.width <= 0) return -1
        return b.mapToItem(null, 0, 0).x + b.width / 2
    }

    function patchMenu(menu) {
        if (menuPatched || !menu || !root.horizontalBar) return
        var win = menuWindowOf(menu)
        if (!win) return
        var parts = menuParts(win)
        if (!parts.card) return
        var card = parts.card

        // One hover area per bar instance: each answers only for its own screen.
        if (parts.dismiss && !menuHoverHooked) {
            menuHoverArea.createObject(parts.dismiss, { win: win })
            menuHoverHooked = true
        }

        for (var i = 0; i < card.children.length; i++) if ("seamRadius" in card.children[i]) { menuPatched = true; return }

        var strokeWidth = Math.max(1, Border.top(card.borderSpec))
        var barSize = root.bar ? root.bar.barSize : 0
        if (parts.scrim) parts.scrim.visible = false
        card.color = "transparent"
        card.borderSpec = Border.none()
        card.padding = card.padding + strokeWidth

        var placeTop = function() {
            if (root.barPos === "top" && win.visible && win.cardTop < 0) win.cardTop = barSize
        }
        placeTop()
        win.visibleChanged.connect(placeTop)
        if (root.barPos === "bottom") card.y = Qt.binding(function() { return win.height - barSize - card.height })

        card.anchors.horizontalCenter = undefined
        card.x = Qt.binding(function() {
            var cx = root.menuIconCenterX()
            var x = cx >= 0 ? cx - card.width / 2 : (win.width - card.width) / 2
            var edge = Style.gapsOut + root.seamRadius
            return Math.round(Math.max(edge, Math.min(x, win.width - card.width - edge)))
        })

        silhouette.createObject(card, {
            panel: { barPos: root.barPos },
            card: card,
            seamRadius: root.seamRadius,
            strokeWidth: root.outline ? strokeWidth : 0
        })
        menuPatched = true
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

    onMenuIconChanged: applyMenuIcon()
    onMenuIconFontChanged: applyMenuIcon()
    onAttachMenuChanged: if (attachMenu) scan()

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
