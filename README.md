# Split Monitor Workspaces

Omarchy bar-widget plugin that shows independent, per-monitor workspace
indicators for Hyprland's [split-monitor-workspaces](https://github.com/Duckonaut/split-monitor-workspaces)
(SMW) plugin.

Each monitor shows exactly the workspaces SMW has actually assigned to it -
auto-detected live, with no manual configuration needed even when different
monitors have different `max_workspaces`. Each monitor tracks and highlights
its *own* active workspace independently, so switching focus on one monitor
never mirrors onto or clears the indicator on another.

By default every workspace that currently exists on a monitor is shown,
which for the common `enable_persistent_workspaces = true` setup (SMW's own
default) means every slot in that monitor's assigned range, since SMW
pre-creates them all up front. Set `permanentWorkspaceCount` (below) to
show a smaller fixed count instead - anything beyond it still appears
whenever it's occupied or active, so a cap never hides where you currently
are.

## Prerequisite

Hyprland with [split-monitor-workspaces](https://github.com/Duckonaut/split-monitor-workspaces)
(SMW) installed and configured is required. This plugin only displays
workspace state that SMW already manages - it does not install or configure
SMW itself.

## Settings

- `permanentWorkspaceCount` (default `0`, unlimited): always show at least
  this many local workspace numbers per monitor. `0` shows every workspace
  that currently exists on that monitor.

## Install

```bash
omarchy plugin add https://github.com/Ziryt/omarchy-plugin-smw.git --enable
```

Or place this repo (or a symlink to it) at
`~/.config/omarchy/plugins/ziryt.split-workspaces/`, then:

```bash
omarchy plugin enable ziryt.split-workspaces
```

## Remove

```bash
omarchy plugin disable ziryt.split-workspaces
```

Then delete the plugin directory (or remove the symlink) at
`~/.config/omarchy/plugins/ziryt.split-workspaces/`.

## License

MIT - see [LICENSE](LICENSE).
