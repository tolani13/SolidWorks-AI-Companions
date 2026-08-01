# SOLIDWORKS Bridge Action Contract

## Read-only actions

### `status`

Arguments: none.

Returns the running SOLIDWORKS revision and active-document summary.

### `inspect-active`

Arguments: none.

Returns document identity, type, active configuration, features, feature error
codes, document custom properties, and assembly component summaries.

## Modifying actions

Every modifying action requires explicit user approval in the sidecar.

### `rebuild`

Arguments: none. Rebuilds the active document in memory.

### `force-rebuild`

Arguments: none. Forces a top-level rebuild in memory.

### `save`

Arguments: none. Saves the active native document using its current path.
Refuses an unsaved document.

### `export-step`

Arguments:

```json
{"path":"C:\\absolute\\output.step","overwrite":false}
```

The active document must be a part or assembly.

### `export-pdf`

Arguments:

```json
{"path":"C:\\absolute\\output.pdf","overwrite":false}
```

The active document must be a drawing.

### `set-custom-property`

Arguments:

```json
{"name":"Description","value":"Bracket","configuration":""}
```

An empty configuration targets document-level properties. The action modifies
the open document in memory and does not save automatically.

## Safety invariants

- Reject actions outside this allowlist.
- Require absolute export paths.
- Refuse implicit overwrite.
- Never accept a script or command string.
- Return JSON for both success and failure.
- Never treat rebuild success as physical or regulatory validation.

