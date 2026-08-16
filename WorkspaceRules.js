// WorkspaceRules.js
//
// Derives each monitor's split-monitor-workspaces (SMW) assigned range
// (base offset + size) from `hyprctl -j workspacerules` output, instead of
// assuming a uniform block size. SMW registers a persistent workspace_rule
// for every workspace in a monitor's assigned range (when
// enable_persistent_workspaces is on, which is SMW's own default), so
// grouping persistent rules by monitor gives the live, per-monitor range -
// correct even when different monitors have different max_workspaces.
//
// The range (not just the base) matters: Hyprland can still report
// `workspace.monitor` for a workspace that used to belong to a monitor but
// fell outside its range after a live SMW reconfiguration (e.g. it still
// has windows, so it wasn't destroyed/reassigned). Bounding to the known
// range keeps such stale workspaces out of the per-monitor list.
//
// Pure JS, no QML dependencies, mirrors the KeyboardLayoutModel.js
// convention used elsewhere in this bar.

// { monitorName: { base: int, count: int } }
function rangeByMonitor(rules) {
    var idsByMonitor = {}

    for (var i = 0; i < rules.length; i++) {
        var rule = rules[i]
        if (!rule || rule.persistent !== true || !rule.monitor)
            continue

        var raw = String(rule.workspaceString).trim()
        var n = Number(raw)
        if (!isFinite(n) || n <= 0 || String(n) !== raw)
            continue

        if (!idsByMonitor[rule.monitor])
            idsByMonitor[rule.monitor] = []

        idsByMonitor[rule.monitor].push(n)
    }

    var result = {}

    for (var name in idsByMonitor) {
        var ids = idsByMonitor[name]
        ids.sort(function(a, b) { return a - b })

        var min = ids[0]
        var max = ids[ids.length - 1]

        // Only trust this as SMW's own contiguous block. A stray/manual
        // workspace_rule sharing this monitor (unrelated to SMW) would
        // otherwise silently corrupt the range - reject instead of guessing.
        if (max - min + 1 !== ids.length)
            continue

        result[name] = { base: min - 1, count: ids.length }
    }

    return result
}

if (typeof module !== "undefined")
    module.exports = { rangeByMonitor: rangeByMonitor }
