# Manifest schema

A manifest is a JSON file in `manifests/` that tells the engine what to do. Copy an example, rename it `local-<something>.json` (gitignored), and edit it.

```json
{
  "name": "Human-readable name",
  "description": "Optional notes for yourself.",
  "config": { ... },
  "steps": [ ... ]
}
```

## config

A flat object of string values. Each key is exported to step scripts as `CFG_<UPPERCASE_KEY>`. Keys used by the shipped steps:

| Key | Used by | Meaning |
| --- | --- | --- |
| `packageManager` | package-manager, packages | `brew` or `port` |
| `dotfilesRepo` | dotfiles | git URL to clone (SSH for private submodules) |
| `dotfilesCloneDir` | dotfiles | clone path relative to `$HOME` |
| `dotfilesInstall` | dotfiles | installer command run inside the repo (e.g. `./install.sh`) |
| `commitMonoUrl` | dotfiles | optional URL to a font zip staged before install |
| `brewfile` | packages | Brewfile path relative to the data dir (e.g. `manifest/Brewfile`) |
| `portfile` | packages | port list path relative to the data dir |
| `macportsPkgUrl` | package-manager | `.pkg` URL for your macOS version (MacPorts has no one-liner) |
| `secretsDmg` | secrets | encrypted bundle path relative to the data dir |
| `extraDefaults` | macos-defaults | optional extra `defaults` script path relative to the data dir |

You can add your own keys; they become `CFG_*` for any custom step you write.

## steps

An ordered array. Each step:

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | stable identifier, used by `--only` |
| `title` | yes | shown in the progress UI |
| `subtitle` | no | shown under the title in the GUI |
| `run` | yes | path to the step script, relative to the repo root (e.g. `steps/dotfiles.sh`) |
| `validation` | no | shell expression run with `bash -c`. If it passes BEFORE the step runs, the step is skipped. After the step runs it is re-checked to confirm success. Empty means "always run, no confirm". |
| `required` | no | `true` aborts the whole run on failure; otherwise the run warns and continues |

## Execution model

For each step the engine:

1. Skips it if `--only` is set to a different `id`.
2. Runs `validation`. If it passes, the step is marked "Already set" and skipped.
3. Otherwise runs `run` (output streams to the terminal and the log).
4. Re-runs `validation` if present. A still-failing validation is treated as a failure.
5. On failure: abort if `required`, else warn and continue.

## Step script contract

A step script is plain bash. It inherits this environment:

- `MIGRATE_ROOT` - the repo root (call `"$MIGRATE_ROOT/migrate" restore ...` to reuse restore phases)
- `MIGRATION_DATA` (and `BASE`, an alias) - the data directory (`payload/`, `manifest/`, `secrets/`)
- `KIT_DIR` - same as `MIGRATE_ROOT`
- `STEP_ID` - this step's id
- every `CFG_*` from `config`

Make it idempotent, return non-zero only on real failure, and prefer a `validation` in the manifest over re-checking inside the script.
