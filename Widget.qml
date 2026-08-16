import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.Commons
import qs.Ui

import "WorkspaceRules.js" as WorkspaceRules

BarWidget {
    id: root

    moduleName: "ziryt.split-workspaces"

    /*
     * BarWidget is instantiated separately for every screen, but the base
     * BarWidget (qs.Ui.BarWidget) does not inject a `screen` property -
     * only `bar`, `moduleName`, and `settings` are set on it.
     *
     * Resolve the enclosing PanelWindow via Quickshell's QsWindow attached
     * property (the same pattern omarchy's own shell uses in Tray.qml /
     * PopupCard.qml / KeyboardPanel.qml to find "which window is this item
     * in"), then read that window's `screen`. That screen is what actually
     * identifies which monitor THIS widget instance is rendering on.
     */
    readonly property var window: root.QsWindow.window
    readonly property var screen: root.window ? root.window.screen : null

    readonly property var monitor:
        root.screen ? Hyprland.monitorFor(root.screen) : null

    /*
     * split-monitor-workspaces (SMW) does not lay monitors out in uniform
     * blocks. Each monitor's range width is `max_workspaces[monitor]` (a
     * per-monitor override) or the global `workspace_count` default, and
     * monitors are packed contiguously in `monitor_priority` order - so
     * different monitors can have different-sized ranges. Assuming a fixed
     * block size here would be wrong whenever a user's max_workspaces
     * differs across monitors.
     *
     * Rather than reimplement SMW's block math, this widget:
     *
     *   - Lists the workspaces that ACTUALLY belong to this monitor right
     *     now (workspaceList() below), read directly from Hyprland's own
     *     live monitor association - always correct, no assumptions.
     *   - Auto-detects this monitor's assigned range (base offset + size,
     *     for a nicer "1, 2, 3..." local numbering and to bound the list
     *     above) from `hyprctl -j workspacerules`, since SMW registers a
     *     persistent workspace_rule for every workspace in a monitor's
     *     full assigned range when enable_persistent_workspaces is on
     *     (SMW's own default). See WorkspaceRules.js.
     *
     *     The bound matters: after a live SMW reconfiguration (monitor
     *     unplugged/replugged, config reload with different
     *     max_workspaces), Hyprland can keep reporting `workspace.monitor`
     *     for a workspace that no longer belongs to that monitor's SMW
     *     range - e.g. an occupied workspace that wasn't force-relocated.
     *     Filtering by monitor name alone would leak these stale
     *     workspaces into the list; bounding to the known range keeps them
     *     out (verified live: shrinking DP-2's max_workspaces surfaced
     *     exactly this - leftover workspaces from its old, larger range
     *     kept reporting monitor=DP-2).
     */
    property var rangeByMonitor: ({})
    property bool rulesResolved: false
    property bool rulesRequestPending: false

    function refreshWorkspaceRules() {
        if (rulesProc.running) {
            root.rulesRequestPending = true
            return
        }

        root.rulesRequestPending = false
        rulesProc.running = true
    }

    Component.onCompleted: root.refreshWorkspaceRules()

    onMonitorChanged: root.refreshWorkspaceRules()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event || !event.name)
                return

            var name = String(event.name)
            if (name === "configreloaded" ||
                name.indexOf("monitoradded") !== -1 ||
                name.indexOf("monitorremoved") !== -1) {
                root.refreshWorkspaceRules()
            }
        }
    }

    Process {
        id: rulesProc
        command: ["hyprctl", "-j", "workspacerules"]
        onRunningChanged: {
            if (running) {
                rulesStallTimer.restart()
                return
            }

            rulesStallTimer.stop()
            if (root.rulesRequestPending)
                root.refreshWorkspaceRules()
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var rules
                try {
                    rules = JSON.parse(text || "[]")
                } catch (e) {
                    return
                }

                if (!Array.isArray(rules))
                    return

                root.rangeByMonitor = WorkspaceRules.rangeByMonitor(rules)
                root.rulesResolved = true
            }
        }
    }

    Timer {
        id: rulesStallTimer
        interval: 5000
        onTriggered: {
            rulesProc.running = false
            root.rulesRequestPending = true
        }
    }

    // Safety-net retry until the first successful parse lands - covers a
    // process that failed at shell startup (e.g. hyprctl not yet ready).
    Timer {
        interval: 10000
        running: !root.rulesResolved
        repeat: true
        onTriggered: root.refreshWorkspaceRules()
    }

    /*
     * This monitor's auto-detected assigned range, or undefined if
     * hyprctl -j workspacerules hasn't resolved a trustworthy one yet
     * (persistence disabled, query still pending, or a non-contiguous
     * rule set for this monitor - see WorkspaceRules.js).
     */
    function monitorRange() {
        var name = root.monitor ? root.monitor.name : ""
        return name ? root.rangeByMonitor[name] : undefined
    }

    /*
     * Real Hyprland workspaces currently tagged to this monitor, sorted by
     * id, with NO range bound applied. `.monitor.name` (not numeric id) is
     * the join key: it's the same stable string SMW's own config uses
     * (max_workspaces/monitor_priority keys) and is not reassigned across a
     * hotplug the way numeric monitor ids can be.
     */
    function monitorWorkspacesUnbounded() {
        if (!root.monitor)
            return []

        var name = root.monitor.name
        var values = Hyprland.workspaces.values
        var out = []

        for (var i = 0; i < values.length; i++) {
            var workspace = values[i]

            if (workspace && workspace.id > 0 && workspace.monitor && workspace.monitor.name === name)
                out.push(workspace)
        }

        out.sort(function(a, b) { return a.id - b.id })
        return out
    }

    /*
     * Real workspaces belonging to this monitor, bounded to its known SMW
     * range once one has been auto-detected. Without this bound, a stale
     * workspace Hyprland still tags to this monitor from before a live
     * reconfiguration (see comment above rangeByMonitor) would otherwise
     * leak into the display.
     */
    function monitorWorkspaces() {
        var out = root.monitorWorkspacesUnbounded()
        var range = root.monitorRange()
        if (range === undefined)
            return out

        var lo = range.base + 1
        var hi = range.base + range.count
        return out.filter(function(workspace) {
            return workspace.id >= lo && workspace.id <= hi
        })
    }

    /*
     * This monitor's base offset: absolute workspace id = base + local id.
     *
     * Prefer the auto-detected value from hyprctl -j workspacerules; fall
     * back to deriving it from whatever real workspaces already exist on
     * this monitor (unbounded - there's no known range yet to bound
     * against); worst case (nothing resolved yet, nothing exists yet)
     * fall back to 0, i.e. show raw absolute ids until something resolves.
     */
    function autoBase() {
        var range = root.monitorRange()
        if (range !== undefined)
            return range.base

        var live = root.monitorWorkspacesUnbounded()
        if (live.length > 0)
            return live[0].id - 1

        return 0
    }

    function globalWorkspaceId(localId) {
        return root.autoBase() + localId
    }

    function localWorkspaceId(globalId) {
        return globalId - root.autoBase()
    }

    /*
     * Local workspace numbers to render.
     *
     * By default (permanentWorkspaceCount = 0) every workspace that
     * currently exists on this monitor is shown - accurate for the common
     * enable_persistent_workspaces=true setup, where SMW pre-creates the
     * monitor's whole assigned range up front.
     *
     * When permanentWorkspaceCount is set to N > 0, only the first N are
     * always shown; anything beyond N still shows if it's occupied or
     * active, so a cap never hides where you currently are or a workspace
     * with windows on it.
     */
    function workspaceIds() {
        var live = root.monitorWorkspaces()
        var base = root.autoBase()
        var cap = Math.max(0, Number(root.setting("permanentWorkspaceCount", 0)))

        var ids = []
        for (var i = 0; i < live.length; i++) {
            var workspace = live[i]
            var localId = workspace.id - base
            var withinCap = cap === 0 || localId <= cap
            var overflow = workspace.toplevels.values.length > 0 || workspace.active

            if (withinCap || overflow)
                ids.push(localId)
        }

        return ids
    }

    function workspaceById(globalId) {
        var values = Hyprland.workspaces.values

        for (var i = 0; i < values.length; i++) {
            var workspace = values[i]

            if (workspace && workspace.id === globalId)
                return workspace
        }

        return null
    }

    function workspaceOccupied(globalId) {
        var workspace = root.workspaceById(globalId)
        return !!workspace && workspace.toplevels.values.length > 0
    }

    /*
     * IMPORTANT:
     *
     * Do NOT use Hyprland.focusedWorkspace/workspace.focused here.
     *
     * `focused` means "active on its monitor AND that monitor has input
     * focus" - a single global notion. We need "active on THIS monitor"
     * regardless of which monitor currently has input focus, which is
     * exactly HyprlandWorkspace.active (see workspace.hpp: "If this
     * workspace is currently active on its monitor. See also @focused.").
     */
    function workspaceActiveOnThisMonitor(globalId) {
        var workspace = root.workspaceById(globalId)
        return !!workspace && workspace.active === true
    }

    function focusWorkspace(localId) {
        var globalId = root.globalWorkspaceId(localId)

        if (!root.bar)
            return

        /*
         * This Hyprland setup only accepts Lua dispatcher calls (hl.dsp.*),
         * not the plain "workspace <id>" form - Hyprland.dispatch() and a
         * raw IPC "dispatch workspace <id>" both get rejected with
         * "hl.dispatch: expected a dispatcher". Match the working pattern
         * omarchy.workspaces itself uses (Workspaces.qml, focusWorkspace()):
         * shell out through hyprctl with the Lua dispatcher call as text.
         *
         * Dispatch the GLOBAL workspace ID - correct regardless of which
         * monitor is currently focused, unlike SMW's own keybind dispatcher
         * (which resolves relative to whichever monitor has input focus).
         */
        root.bar.run(
            "hyprctl dispatch " +
            Util.shellQuote("hl.dsp.focus({ workspace = \"" + globalId + "\" })")
        )
    }

    readonly property real trailingGap:
        root.vertical ? 0 : Style.spaceReal(1.5)

    implicitWidth:
        grid.implicitWidth + trailingGap

    implicitHeight:
        grid.implicitHeight

    GridLayout {
        id: grid

        anchors.fill: parent
        anchors.rightMargin: root.trailingGap

        columns:
            root.vertical
                ? 1
                : root.workspaceIds().length

        columnSpacing:
            root.vertical
                ? 0
                : Style.space(1)

        rowSpacing:
            root.vertical
                ? Style.space(2)
                : 0

        Repeater {
            model: root.workspaceIds()

            WidgetButton {
                required property int modelData

                readonly property int localId:
                    modelData

                readonly property int globalId:
                    root.globalWorkspaceId(localId)

                readonly property bool occupied:
                    root.workspaceOccupied(globalId)

                readonly property bool active:
                    root.workspaceActiveOnThisMonitor(globalId)

                bar: root.bar

                text:
                    active
                        ? "󱓻"
                        : String(localId)

                opacity:
                    occupied || active
                        ? 1
                        : 0.5

                horizontalMargin: 6
                verticalPadding: 6

                fixedWidth:
                    root.vertical
                        ? root.barSize
                        : Style.space(20)

                fixedHeight:
                    root.barSize

                onPressed:
                    root.focusWorkspace(localId)
            }
        }
    }
}
