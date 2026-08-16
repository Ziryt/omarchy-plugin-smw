# Split Monitor Workspaces

Omarchy bar-widget plugin that shows independent, per-monitor workspace
indicators for Hyprland's [split-monitor-workspaces](https://github.com/Duckonaut/split-monitor-workspaces)
plugin.

Each monitor gets its own contiguous block of `workspaceCount` workspaces.
The first `permanentWorkspaceCount` are always shown; higher ones appear
only while occupied or active. Each monitor tracks and highlights its *own*
active workspace independently, so switching focus on one monitor never
mirrors onto or clears the indicator on another.

## Requirements

- Hyprland with `split-monitor-workspaces` installed and configured
- `workspaceCount` in `Widget.qml` must match that plugin's `workspace_count`
  (SMW doesn't currently expose this setting to Quickshell)

## Install

Place this repo (or a symlink to it) at
`~/.config/omarchy/plugins/community.split-workspaces/`, then:

```bash
omarchy plugin enable community.split-workspaces
```
