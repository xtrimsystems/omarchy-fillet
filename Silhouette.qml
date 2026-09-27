import QtQuick
import QtQuick.Shapes
import qs.Commons

// Painted behind a popup's card: square along the bar, curving out into it at
// both ends, rounded only on the exposed corners, outlined only on the
// exposed edges.
Item {
    id: root

    required property var panel
    required property var card
    property int seamRadius: 12
    property int strokeWidth: 2
    property color fillColor: Color.popups.background
    property color strokeColor: Color.popups.border
    property bool barClear: false

    readonly property string barPos: panel && panel.barPos ? String(panel.barPos) : "top"
    readonly property bool connectors: barPos === "top" || barPos === "bottom"
    readonly property bool fade: barClear && connectors
    readonly property int flare: connectors ? seamRadius : 0
    readonly property int half: Math.floor(strokeWidth / 2)
    readonly property int w: card ? Math.round(card.width) : 0
    readonly property int h: card ? Math.round(card.height) : 0

    x: -flare
    y: 0
    width: w + flare * 2
    height: h
    z: -1

    readonly property string outlinePath: {
        var r = seamRadius
        var c = Math.min(r, Math.floor(Math.min(w, h) / 2))
        if (barPos === "top") {
            return "M 0 0"
                + " A " + r + " " + r + " 0 0 1 " + r + " " + r
                + " L " + r + " " + (h - c)
                + " A " + c + " " + c + " 0 0 0 " + (r + c) + " " + h
                + " L " + (r + w - c) + " " + h
                + " A " + c + " " + c + " 0 0 0 " + (r + w) + " " + (h - c)
                + " L " + (r + w) + " " + r
                + " A " + r + " " + r + " 0 0 1 " + (2 * r + w) + " 0"
        }
        if (barPos === "bottom") {
            return "M 0 " + h
                + " A " + r + " " + r + " 0 0 0 " + r + " " + (h - r)
                + " L " + r + " " + c
                + " A " + c + " " + c + " 0 0 1 " + (r + c) + " 0"
                + " L " + (r + w - c) + " 0"
                + " A " + c + " " + c + " 0 0 1 " + (r + w) + " " + c
                + " L " + (r + w) + " " + (h - r)
                + " A " + r + " " + r + " 0 0 0 " + (2 * r + w) + " " + h
        }
        if (barPos === "left") {
            return "M 0 0"
                + " L " + (w - c) + " 0"
                + " A " + c + " " + c + " 0 0 1 " + w + " " + c
                + " L " + w + " " + (h - c)
                + " A " + c + " " + c + " 0 0 1 " + (w - c) + " " + h
                + " L 0 " + h
        }
        return "M " + w + " 0"
            + " L " + c + " 0"
            + " A " + c + " " + c + " 0 0 0 0 " + c
            + " L 0 " + (h - c)
            + " A " + c + " " + c + " 0 0 0 " + c + " " + h
            + " L " + w + " " + h
    }

    // The fill overlaps the bar by half the stroke so the bar edge line drawn
    // there stays hidden under the popup body.
    readonly property string fillPath: {
        if (barPos === "top") return outlinePath + " L " + width + " " + (-half) + " L 0 " + (-half) + " Z"
        if (barPos === "bottom") return outlinePath + " L " + width + " " + (h + half) + " L 0 " + (h + half) + " Z"
        return outlinePath + " Z"
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            fillColor: root.fillColor
            strokeWidth: -1
            PathSvg { path: root.fillPath }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth > 0 && !root.fade ? root.strokeWidth : -1
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.outlinePath }
        }
    }

    // On a see-through bar the outline fades in from the bar along the sides.
    // Drawn as a filled band because a stroke cannot take a gradient.
    readonly property int bandWidth: Math.max(1, strokeWidth)
    readonly property string bandPath: {
        var sw = bandWidth
        var c = Math.min(seamRadius, Math.floor(Math.min(w, h) / 2))
        var ci = Math.max(0, c - sw)
        if (barPos === "bottom") {
            return "M 0 " + h + " L 0 " + c
                + " A " + c + " " + c + " 0 0 1 " + c + " 0"
                + " L " + (w - c) + " 0"
                + " A " + c + " " + c + " 0 0 1 " + w + " " + c
                + " L " + w + " " + h + " L " + (w - sw) + " " + h
                + " L " + (w - sw) + " " + (sw + ci)
                + " A " + ci + " " + ci + " 0 0 0 " + (w - sw - ci) + " " + sw
                + " L " + (sw + ci) + " " + sw
                + " A " + ci + " " + ci + " 0 0 0 " + sw + " " + (sw + ci)
                + " L " + sw + " " + h + " Z"
        }
        return "M 0 0 L 0 " + (h - c)
            + " A " + c + " " + c + " 0 0 0 " + c + " " + h
            + " L " + (w - c) + " " + h
            + " A " + c + " " + c + " 0 0 0 " + w + " " + (h - c)
            + " L " + w + " 0 L " + (w - sw) + " 0"
            + " L " + (w - sw) + " " + (h - sw - ci)
            + " A " + ci + " " + ci + " 0 0 1 " + (w - sw - ci) + " " + (h - sw)
            + " L " + (sw + ci) + " " + (h - sw)
            + " A " + ci + " " + ci + " 0 0 1 " + sw + " " + (h - sw - ci)
            + " L " + sw + " 0 Z"
    }

    Shape {
        visible: root.fade && root.strokeWidth > 0
        x: root.flare
        width: root.w
        height: root.h
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; x2: 0
                y1: root.barPos === "bottom" ? root.h : 0
                y2: root.barPos === "bottom" ? root.h * 0.4 : root.h * 0.6
                GradientStop { position: 0; color: Qt.rgba(root.strokeColor.r, root.strokeColor.g, root.strokeColor.b, 0) }
                GradientStop { position: 1; color: root.strokeColor }
            }
            PathSvg { path: root.bandPath }
        }
    }
}
