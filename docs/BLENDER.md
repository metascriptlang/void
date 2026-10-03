# Blender control — house rules

How the agent in this repo drives Blender. Scope: what is specific to this machine
and this user's conventions. The MCP server ships its own instructions (node
lookups by type, never hardcode enums, verify with screenshots) — they are
injected into every session automatically and are not repeated here.

## Setup on this machine

| Piece | Value |
|---|---|
| MCP server (omp) | `blender` → `uvx mcp-for-blender`, stdio, `~/.omp/agent/mcp.json` |
| Safe mode | ON (`BLENDER_MCP_SAFE_MODE=1`) — scripts are validated; file I/O, subprocess, network inside `execute_blender_code` are blocked |
| Request timeout | 120 s (Blender ops exceed the 30 s default) |
| Blender | 5.2.1 LTS, `/Applications/Blender.app` — binary: `/Applications/Blender.app/Contents/MacOS/Blender` |
| Addon | `blender_mcp.py` in `~/Library/Application Support/Blender/5.2/scripts/addons/` |
| Socket | localhost:9876, no auth — the Blender-side server is stopped when not in use |
| Second instance | port 9877: addon panel port + `uvx mcp-for-blender --port 9877` as a separate omp server entry |

## Decision rules

| Task | Path |
|---|---|
| Live scene work (inspect, build, iterate with GUI open) | MCP tools |
| One-shot batch, render, CI, export without GUI | headless bash: `<blender> -b file.blend -P script.py --python-exit-code 1` |
| File on disk the socket can't reach (safe mode blocks I/O) | `export_scene` tool, or headless CLI |
| Long deterministic pipeline | write a .py, run headless; do not loop `execute_blender_code` |

## House rules

1. **Read before write.** `get_addon_status` + `get_scene_info` before changing
   anything; `get_scene_info` + `get_viewport_screenshot` after. A green script
   is not proof — the screenshot is.
2. **Never delete or rename user-made objects/data-blocks without asking.**
   Report what would be removed first.
3. **`execute_blender_code` scripts must not assume scene contents.** Guard by
   type/name lookups, not by "the scene should have X". Safe mode rejections
   are respected — do not work around them with the socket; move that step to
   `export_scene` or headless CLI.
4. **Scripts passed to headless CLI always use `--python-exit-code 1`** and
   `--factory-startup` unless user preferences/addons are the point. Arguments
   to the script go after `--` and are parsed from `sys.argv[-args:]`.
5. **Fail loud.** No silent fallback, no auto-repair of unexpected scene state —
   report the case and stop.
6. **Exports land in `exports/`** (git-ignored), format GLB unless told
   otherwise.

## Conventions (defaults — user overrides win)

- Object prefixes: `GEO-` meshes, `LGT-` lights, `CAM-` cameras, `TEX-`
  textures, `WLD-` world, `SCN-` scene, `GRP-` collections (Blender Lab style).
- Units: metric, 1 unit = 1 m.
- Before mass rename: show the old → new mapping, apply only on approval.

## Known papercuts

- Installer `uvx mcp-for-blender install-addon` cannot find the addons dir on a
  Blender that has never launched (empty user dir). Fix:
  `mkdir -p "$HOME/Library/Application Support/Blender/5.2/scripts/addons"` and
  set `BLENDERMCP_ADDONS_DIR` to it.
- uvx lives under mise (`~/.local/share/mise/installs/python/3.11.11/bin/uvx`);
  if omp fails to spawn the server, use that absolute path in
  `~/.omp/agent/mcp.json`.
