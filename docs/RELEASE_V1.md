# V1 Release Notes

## Target

Ship the first complete Synapse version ready for GitHub publishing.

## Delivered

1. Command workflow
- Slash command list and prefix matching
- Unified command mapping and intent preview
- Exit/close semantic split: `/quit` vs `/close`

2. Search and system tools
- Absolute path file search
- Click-to-open file path
- IP/battery/date cards and clearer semantics

3. AI workflow
- Codex-only AI path (knowledge/code/writing)
- model/reasoning/response mode settings
- retry strategy for transient CLI/MCP startup failures

4. UI and interaction
- adaptive panel expand/collapse
- help panel visibility and scrollability
- selectable output + explicit copy action
- execution animation and contextual status text

## Validation

```bash
swift build
swift test --skip-build
```

Both commands pass in the current workspace.
