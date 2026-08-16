import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs.Commons
import qs.Ui

BarWidget {
    id: root

    moduleName: "community.split-workspaces"

    /*
     * Must match split-monitor-workspaces:
     *
     *   workspace_count = 9
     *
     * SMW currently does not expose its Lua configuration to Quickshell,
     * so this remains an explicit setting.
     */
    property int workspaceCount: 9

    /*
     * These workspaces are always visible.
     * Higher workspaces are displayed only while occupied or active.
     */
    property int permanentWorkspaceCount: 5

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
     * Determine which split-monitor-workspaces range belongs to this monitor.
     *
     * Do not use Hyprland monitor IDs for this.
     *
     * Hyprland monitor IDs describe Hyprland's monitor objects, but they are
     * not a reliable representation of split-monitor-workspaces' workspace
     * ordering, especially when monitors are added, removed, reordered, or
     * configured with monitor_priority.
     *
     * Instead, find the active workspace of this monitor and derive the
     * beginning of its SMW range from that workspace.
     *
     * Example:
     *
     *   workspace_count = 9
     *
     *   monitor A active workspace = 3
     *       -> range starts at 1
     *
     *   monitor B active workspace = 12
     *       -> range starts at 10
     *
     *   monitor C active workspace = 21
     *       -> range starts at 19
     *
     * If the monitor has no active workspace yet, fall back to zero. This
     * keeps the widget alive during monitor hotplug/startup transitions.
     */
    function monitorOffset() {
        if (!root.monitor || !root.monitor.activeWorkspace)
            return 0

        var activeId = Number(root.monitor.activeWorkspace.id)
        var count = Math.max(1, Number(root.workspaceCount))

        if (!isFinite(activeId) || activeId <= 0)
            return 0

        /*
         * Workspace IDs are arranged in blocks of workspaceCount:
         *
         *   1..count
         *   count+1..count*2
         *   count*2+1..count*3
         *
         * Find the block containing this monitor's currently active
         * workspace.
         */
        return Math.floor((activeId - 1) / count) * count
    }

    function globalWorkspaceId(localId) {
        return root.monitorOffset() + localId
    }

    function localWorkspaceId(globalId) {
        return globalId - root.monitorOffset()
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
        var values = Hyprland.toplevels.values

        for (var i = 0; i < values.length; i++) {
            var toplevel = values[i]

            if (!toplevel || !toplevel.workspace)
                continue

            if (toplevel.workspace.id === globalId)
                return true
        }

        return false
    }

    /*
     * IMPORTANT:
     *
     * Do NOT use Hyprland.focusedWorkspace here.
     *
     * That is one global focused workspace.
     *
     * We need the active workspace belonging to THIS monitor, so that:
     *
     *   monitor A -> its active workspace remains highlighted
     *   monitor B -> its active workspace is highlighted independently
     */
    function workspaceActiveOnThisMonitor(globalId) {
        if (!root.monitor || !root.monitor.activeWorkspace)
            return false

        return root.monitor.activeWorkspace.id === globalId
    }

    /*
     * Local workspace numbers that should be rendered.
     *
     * Always:
     *
     *   1 2 3 4 5
     *
     * Dynamically:
     *
     *   6..N when occupied or active
     */
    function workspaceIds() {
        var ids = []

        var count = Math.max(1, root.workspaceCount)
        var permanent = Math.min(
            root.permanentWorkspaceCount,
            count
        )

        for (var localId = 1; localId <= permanent; localId++)
            ids.push(localId)

        for (
            var extra = permanent + 1;
            extra <= count;
            extra++
        ) {
            var globalId = root.globalWorkspaceId(extra)

            if (
                root.workspaceOccupied(globalId) ||
                root.workspaceActiveOnThisMonitor(globalId)
            ) {
                ids.push(extra)
            }
        }

        return ids
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
         * Dispatch the GLOBAL workspace ID.
         *
         * Example with 9 workspaces per monitor:
         *
         *   monitor 1, local 3 -> workspace 3
         *   monitor 2, local 3 -> workspace 12
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
                        ? "\uDB85\uDCFB"
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
